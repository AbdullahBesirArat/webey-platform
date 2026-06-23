<?php
declare(strict_types=1);
/**
 * api/mobile/business/appointment-deposit-confirm.php
 * POST — İşletme, müşterinin IBAN'a gönderdiğini bildirdiği kaporayı onaylar/reddeder.
 *
 * Body (JSON):
 *   appointment_id : int    (zorunlu)
 *   action         : string (zorunlu) — 'confirm' veya 'reject'
 *
 * confirm:
 *   - deposit_status = 'paid', deposit_paid_at = NOW()
 *   - randevu status = 'approved' (terminal değilse)
 *   - müşteriye "Kapora onaylandı / Randevu onaylandı" bildirimi + best-effort push
 * reject:
 *   - deposit_status = 'not_received'
 *   - randevu status değişmez
 *   - müşteriye "Ödeme doğrulanamadı" bildirimi + best-effort push
 *
 * Mevcut appointment-deposit.php ve iyzico akışını bozmaz; bu endpoint
 * manuel IBAN onay/red için action-bazlı sade bir sarmalayıcıdır.
 *
 * Auth: business/admin zorunlu; randevu bu işletmeye ait olmalı.
 *
 * Yanıt:
 *   success            : bool
 *   deposit_status     : string
 *   appointment_status : string
 *   message            : string
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';
require_once __DIR__ . '/_helpers.php';
require_once __DIR__ . '/../_payment_settings.php';
require_once __DIR__ . '/../../_appointment_log.php';
require_once __DIR__ . '/../../_appointment_push.php';
require_once __DIR__ . '/../../_user_notifications.php';

wb_method('POST');

$auth       = mobile_auth($pdo, ['business', 'admin']);
$ctx        = mobile_business_context($pdo, $auth);
$businessId = (int)$ctx['business_id'];
$actorId    = (int)($ctx['user_id'] ?? 0);

if (!mobile_table_has_column($pdo, 'appointments', 'deposit_status')) {
    wb_err('Kapora takibi servisi şu an kullanılamıyor', 503, 'deposit_unavailable');
}

$in            = wb_body();
$appointmentId = (int)($in['appointment_id'] ?? 0);
$action        = strtolower(trim((string)($in['action'] ?? '')));

if ($appointmentId <= 0) {
    wb_err('appointment_id zorunlu', 400, 'missing_param');
}
if (!in_array($action, ['confirm', 'reject'], true)) {
    wb_err('Geçersiz action (confirm veya reject olmalı)', 422, 'invalid_action');
}

// Randevu bu işletmeye ait mi? (değilse 404)
$appt = mobile_business_require_appointment($pdo, $businessId, $appointmentId);

// deposit_status'u ayrı sorgu ile çek (paylaşılan select SQL'inde yok).
$depStmt = $pdo->prepare('SELECT deposit_status FROM appointments WHERE id = ? AND business_id = ? LIMIT 1');
$depStmt->execute([$appointmentId, $businessId]);
$currentDepositStatus = strtolower((string)($depStmt->fetchColumn() ?: 'pending'));

if ($currentDepositStatus === 'paid' && $action === 'confirm') {
    wb_err('Kapora zaten onaylanmış', 409, 'already_paid');
}

$apptStatus    = strtolower((string)($appt['status'] ?? ''));
$businessName  = (string)($appt['business_name'] ?? 'Salon');
$startAt       = (string)($appt['start_at'] ?? '');
$serviceName   = (string)($appt['service_name'] ?? '');
$customerUserId = (int)($appt['customer_user_id'] ?? 0);

$newDepositStatus = $action === 'confirm' ? 'paid' : 'not_received';
$newApptStatus    = $apptStatus;

try {
    $pdo->beginTransaction();

    if ($action === 'confirm') {
        $referenceCode = wb_deposit_reference_code($appointmentId);
        $pdo->prepare(
            "UPDATE appointments
                SET deposit_status = 'paid',
                    deposit_reference_code = COALESCE(deposit_reference_code, ?),
                    deposit_paid_at = NOW(),
                    deposit_marked_by = ?,
                    deposit_marked_at = NOW(),
                    updated_at = NOW()
              WHERE id = ? AND business_id = ?"
        )->execute([$referenceCode, $actorId > 0 ? $actorId : null, $appointmentId, $businessId]);

        // Randevuyu onayla (terminal değilse).
        if (!in_array($apptStatus, ['cancelled', 'rejected', 'declined', 'no_show', 'completed'], true)) {
            $pdo->prepare(
                "UPDATE appointments SET status = 'approved', updated_at = NOW()
                  WHERE id = ? AND business_id = ?"
            )->execute([$appointmentId, $businessId]);
            $newApptStatus = 'approved';

            // İşletme bildirim kuyruğunu çöz (pending booking → approved).
            $pdo->prepare(
                "UPDATE notifications
                    SET result = 'approved', is_read = 1, read_at = NOW()
                  WHERE appointment_id = ? AND business_id = ?
                    AND type IN ('booking','deposit_sent') AND result = 'pending'"
            )->execute([$appointmentId, $businessId]);
        }
    } else {
        $pdo->prepare(
            "UPDATE appointments
                SET deposit_status = 'not_received',
                    deposit_marked_by = ?,
                    deposit_marked_at = NOW(),
                    updated_at = NOW()
              WHERE id = ? AND business_id = ?"
        )->execute([$actorId > 0 ? $actorId : null, $appointmentId, $businessId]);
    }

    wb_appt_log(
        $pdo,
        $appointmentId,
        $action === 'confirm' ? 'deposit_confirmed' : 'deposit_rejected',
        $currentDepositStatus,
        $newDepositStatus,
        $actorId
    );

    $pdo->commit();
} catch (Throwable $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    error_log('[mobile/business/appointment-deposit-confirm.php] ' . $e->getMessage());
    wb_err('Kapora durumu güncellenemedi. Lütfen tekrar deneyin.', 500, 'internal_error');
}

// ── Müşteri bildirimi (in-app garanti + best-effort push) ───────────────────────
if ($action === 'confirm') {
    $notifType    = 'deposit_paid';
    $notifTitle   = 'Kapora ödemeniz onaylandı';
    $notifMessage = $businessName . ' kapora ödemenizi onayladı. Randevunuz onaylandı.';
} else {
    $notifType    = 'deposit_not_received';
    $notifTitle   = 'Ödeme doğrulanamadı';
    $notifMessage = $businessName . ' kaporanızı henüz almadığını bildirdi. Lütfen salonla iletişime geçin.';
}

try {
    if ($customerUserId > 0) {
        wbInsertUserNotification(
            $pdo,
            $customerUserId,
            $appointmentId,
            $notifType,
            $notifTitle,
            $notifMessage,
            $businessName
        );
    }
} catch (Throwable $notifEx) {
    error_log('[mobile/business/appointment-deposit-confirm.php notif] ' . $notifEx->getMessage());
}

// Best-effort FCM: confirm → onay + status push; reject → deposit push.
try {
    wb_appt_send_customer_deposit_push(
        $pdo,
        $appointmentId,
        $newDepositStatus,
        $notifTitle,
        $notifMessage
    );
    if ($action === 'confirm' && $newApptStatus === 'approved') {
        wb_appt_send_customer_status_push($pdo, $appointmentId, 'approved');
    }
} catch (Throwable $pushEx) {
    error_log('[mobile/business/appointment-deposit-confirm.php push] ' . $pushEx->getMessage());
}

wb_ok([
    'success'            => true,
    'deposit_status'     => $newDepositStatus,
    'appointment_status' => $newApptStatus,
    'message'            => $action === 'confirm'
        ? 'Kapora onaylandı ve randevu onaylandı.'
        : 'Kapora alınmadı olarak işaretlendi.',
]);
