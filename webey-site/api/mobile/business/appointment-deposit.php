<?php
declare(strict_types=1);
/**
 * api/mobile/business/appointment-deposit.php
 * POST — Salon, randevunun kapora durumunu manuel işaretler.
 *
 * Body (JSON):
 *   appointment_id : int    (zorunlu)
 *   status         : string (zorunlu) — pending | paid | not_received | waived | refunded
 *
 * MVP: Para Webey'de toplanmaz. Salon, müşteriden IBAN'a gelen kaporayı
 * manuel olarak "alındı/alınmadı" işaretler.
 *
 * Auth: business/admin zorunlu; randevu bu işletmeye ait olmalı.
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';
require_once __DIR__ . '/_helpers.php';
require_once __DIR__ . '/../_payment_settings.php';
require_once __DIR__ . '/../../_appointment_log.php';
require_once __DIR__ . '/../../_appointment_push.php';
require_once __DIR__ . '/../../_user_notifications.php';
require_once __DIR__ . '/../../_fcm.php';

wb_method('POST');

$auth = mobile_auth($pdo, ['business', 'admin']);
$ctx = mobile_business_context($pdo, $auth);
$businessId = (int)$ctx['business_id'];
$userId = (int)($auth['user_id'] ?? 0);

if (!mobile_table_has_column($pdo, 'appointments', 'deposit_status')) {
    wb_err('Kapora takibi servisi şu an kullanılamıyor', 503, 'deposit_unavailable');
}

$in = wb_body();
$appointmentId = (int)($in['appointment_id'] ?? 0);
$status = strtolower(trim((string)($in['status'] ?? '')));

if ($appointmentId <= 0) {
    wb_err('appointment_id zorunlu', 400, 'missing_param');
}
$allowed = ['pending', 'paid', 'not_received', 'waived', 'refunded'];
if (!in_array($status, $allowed, true)) {
    wb_err('Geçersiz kapora durumu', 422, 'invalid_status');
}

// Randevu bu işletmeye ait mi? (değilse 404)
$appt = mobile_business_require_appointment($pdo, $businessId, $appointmentId);

try {
    $referenceCode = wb_deposit_reference_code($appointmentId);
    $paidAt = $status === 'paid' ? date('Y-m-d H:i:s') : null;

    $pdo->prepare(
        "UPDATE appointments
            SET deposit_status = ?,
                deposit_reference_code = COALESCE(deposit_reference_code, ?),
                deposit_paid_at = ?,
                deposit_marked_by = ?,
                deposit_marked_at = NOW(),
                updated_at = NOW()
          WHERE id = ? AND business_id = ?"
    )->execute([
        $status,
        $referenceCode,
        $paidAt,
        $userId > 0 ? $userId : null,
        $appointmentId,
        $businessId,
    ]);
} catch (Throwable $e) {
    error_log('[mobile/business/appointment-deposit.php] ' . $e->getMessage());
    wb_err('Kapora durumu güncellenemedi. Lütfen tekrar deneyin.', 500, 'internal_error');
}

// ── Audit log (ana akışı kesmez) ─────────────────────────────────────────────
try {
    wb_appt_log($pdo, $appointmentId, 'deposit_' . $status, null, $status, $userId);
} catch (Throwable $logEx) {
    error_log('[mobile/business/appointment-deposit.php log] ' . $logEx->getMessage());
}

// ── Müşteri bildirimi (in-app + best-effort push) ────────────────────────────
$businessName = (string)($appt['business_name'] ?? 'Salon');
$notifMap = [
    'paid' => [
        'type' => 'deposit_paid',
        'title' => 'Kaporanız alındı',
        'message' => $businessName . ' kapora ödemenizi onayladı.',
    ],
    'not_received' => [
        'type' => 'deposit_not_received',
        'title' => 'Kapora bekleniyor',
        'message' => $businessName . ' kaporanızı henüz almadığını işaretledi.',
    ],
    'refunded' => [
        'type' => 'deposit_refunded',
        'title' => 'Kaporanız iade edildi',
        'message' => $businessName . ' kapora iadenizi işaretledi.',
    ],
];

if (isset($notifMap[$status])) {
    $notif = $notifMap[$status];
    try {
        $notifUserId = (int)($appt['customer_user_id'] ?? 0);
        if ($notifUserId > 0) {
            wbInsertUserNotification(
                $pdo,
                $notifUserId,
                $appointmentId,
                $notif['type'],
                $notif['title'],
                $notif['message'],
                $businessName
            );
        }
    } catch (Throwable $notifEx) {
        error_log('[mobile/business/appointment-deposit.php notif] ' . $notifEx->getMessage());
    }

    // Best-effort FCM (push hatası status update'i bozmaz)
    try {
        wb_appt_send_customer_deposit_push(
            $pdo,
            $appointmentId,
            $status,
            $notif['title'],
            $notif['message']
        );
    } catch (Throwable $pushEx) {
        error_log('[mobile/business/appointment-deposit.php push] ' . $pushEx->getMessage());
    }
}

$depositAmount = ($appt['deposit_amount'] ?? null) !== null ? (float)$appt['deposit_amount'] : null;

wb_ok([
    'deposit' => [
        'required' => (bool)($appt['deposit_required'] ?? false),
        'amount' => $depositAmount,
        'status' => $status,
        'reference_code' => wb_deposit_reference_code($appointmentId),
        'paid_at' => $status === 'paid' ? date('Y-m-d H:i:s') : null,
    ],
    'appointment_id' => (string)$appointmentId,
    'message' => 'Kapora durumu güncellendi.',
]);
