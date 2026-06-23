<?php
declare(strict_types=1);
/**
 * api/mobile/customer/appointments/cancel.php
 * POST — Müşteri randevu iptali / iptal talebi.
 *
 * Body (JSON):
 *   appointment_id : int  (zorunlu)
 *   reason         : string (opsiyonel)
 *
 * Mevcut iş akışına göre sistem 'cancellation_requested' statüsüne
 * geçer; işletme onayladığında 'cancelled' olur.
 *
 * Faz 4A — Bearer token zorunlu, customer tipi.
 * TODO (Faz 4B): Email ve SMS bildirimlerini aktif et.
 */

require_once __DIR__ . '/../../_bootstrap.php';
require_once __DIR__ . '/../../_auth.php';
require_once __DIR__ . '/../../_cancellation.php';

wb_method('POST');

$session = mobile_auth($pdo, 'customer');
$userId  = $session['user_id'];

$in            = wb_body();
$appointmentId = (int)($in['appointment_id'] ?? 0);
$preview       = !empty($in['preview']);

if ($appointmentId <= 0) {
    wb_err('appointment_id zorunlu', 400, 'missing_param');
}

try {
    // ── Müşteri telefonu (kimlik çift-kontrolü için) ───────────────────────
    $cPhoneStmt = $pdo->prepare("SELECT phone FROM customers WHERE user_id = ? LIMIT 1");
    $cPhoneStmt->execute([$userId]);
    $rawPhone  = preg_replace('/\D/', '', (string)($cPhoneStmt->fetchColumn() ?: ''));
    $phone10   = $rawPhone !== '' ? substr($rawPhone, -10) : '';

    $knownPhones = [];
    if ($phone10 !== '') {
        $knownPhones[$phone10] = true;
    }

    // ── Randevuyu çek ─────────────────────────────────────────────────────
    $apptStmt = $pdo->prepare("
        SELECT
            a.id,
            a.status,
            a.start_at,
            a.business_id,
            a.customer_phone,
            a.customer_user_id,
            a.customer_name,
            s.name  AS service_name,
            b.name  AS business_name
        FROM appointments a
        LEFT JOIN services   s ON s.id = a.service_id
        LEFT JOIN businesses b ON b.id = a.business_id
        WHERE a.id = ?
        LIMIT 1
    ");
    $apptStmt->execute([$appointmentId]);
    $appt = $apptStmt->fetch();

    if (!$appt) {
        wb_err('Randevu bulunamadı', 404, 'not_found');
    }

    // ── Yetkilendirme: customer_user_id veya telefon eşleşmesi ───────────
    $authorized = ((int)($appt['customer_user_id'] ?? 0) === $userId);

    if (!$authorized) {
        $apptPhone10 = substr(preg_replace('/\D/', '', (string)($appt['customer_phone'] ?? '')), -10);
        if ($apptPhone10 !== '' && isset($knownPhones[$apptPhone10])) {
            $authorized = true;
        }
    }

    if (!$authorized) {
        wb_err('Bu randevuya erişim yetkiniz yok', 403, 'forbidden');
    }

    // ── Durum kontrolleri ─────────────────────────────────────────────────
    $prevStatus = strtolower((string)($appt['status'] ?? ''));

    if (in_array($prevStatus, ['cancelled', 'rejected', 'declined', 'cancellation_requested'], true)) {
        wb_err('Bu randevu zaten iptal edilmiş veya iptal talebi bekliyor', 409, 'already_cancelled');
    }

    if (in_array($prevStatus, ['completed', 'no_show'], true)) {
        wb_err('Tamamlanmış randevu iptal edilemez', 409, 'already_completed');
    }

    if (!in_array($prevStatus, ['pending', 'approved'], true)) {
        wb_err('Bu randevu iptal edilemez (durum: ' . $prevStatus . ')', 400, 'invalid_status');
    }

    if (empty($appt['start_at']) || strtotime((string)$appt['start_at']) <= time()) {
        wb_err('Geçmiş randevu iptal edilemez', 409, 'past_appointment');
    }

    // ── İptal finansal hesabı (snapshot politikadan, ödenmiş kapora üzerinden) ──
    $cancellationSummary = null;
    try {
        $hasCancelCols = mobile_table_has_column($pdo, 'appointments', 'free_cancel_hours_snapshot');
        $depHasStatus  = mobile_table_has_column($pdo, 'appointments', 'deposit_status');
        $selCols = 'start_at, deposit_required, deposit_amount'
            . ($depHasStatus ? ', deposit_status' : '')
            . ($hasCancelCols ? ', free_cancel_hours_snapshot, late_cancel_fee_pct_snapshot, no_show_refund_pct_snapshot, paid_deposit_amount_snapshot' : '');
        $detStmt = $pdo->prepare("SELECT $selCols FROM appointments WHERE id = ? LIMIT 1");
        $detStmt->execute([$appointmentId]);
        $detRow = $detStmt->fetch() ?: [];
        $detRow['business_id'] = (int)($appt['business_id'] ?? 0);

        $quote = wb_cancellation_quote_for_appointment(
            $pdo,
            $detRow,
            (int)($appt['business_id'] ?? 0),
            'customer_cancel'
        );

        if ($hasCancelCols && !$preview) {
            $pdo->prepare(
                'UPDATE appointments SET
                    paid_deposit_amount_snapshot = ?, cancel_refund_amount = ?,
                    cancel_retained_amount = ?, cancel_rule_result = ?
                 WHERE id = ?'
            )->execute([
                $quote['paid_deposit'], $quote['refund_amount'],
                $quote['retained_amount'], $quote['rule_result'], $appointmentId,
            ]);
        }
        $cancellationSummary = [
            'is_free'          => $quote['is_free'],
            'is_late'          => $quote['is_late'],
            'paid_deposit'     => $quote['paid_deposit'],
            'refund_amount'    => $quote['refund_amount'],
            'retained_amount'  => $quote['retained_amount'],
            'rule_result'      => $quote['rule_result'],
            'headline'         => $quote['headline'],
            'message'          => $quote['message'],
            'manual_refund'    => $quote['manual_refund'],
        ];
    } catch (Throwable $cancelEx) {
        error_log('[mobile/customer/appointments/cancel.php cancellation] ' . $cancelEx->getMessage());
    }

    // ── Statüyü güncelle ──────────────────────────────────────────────────
    if ($preview) {
        wb_ok([
            'preview'        => true,
            'appointment_id' => (string)$appointmentId,
            'status'         => $prevStatus,
            'cancellation'   => $cancellationSummary,
        ]);
    }

    $pdo->prepare("
        UPDATE appointments
        SET status = 'cancellation_requested', updated_at = NOW()
        WHERE id = ?
    ")->execute([$appointmentId]);

    // ── Appointment log (ana akışı kesmez) ────────────────────────────────
    require_once __DIR__ . '/../../../_appointment_log.php';
    wb_appt_log($pdo, $appointmentId, 'cancellation_requested', $prevStatus, 'cancellation_requested', $userId);

    // ── Müşteri bildirimi (opsiyonel — ana akışı kesmez) ──────────────────
    try {
        require_once __DIR__ . '/../../../_user_notifications.php';
        $notif = wbUserNotifFromStatus(
            'cancellation_requested',
            (string)($appt['business_name'] ?? 'İşletme'),
            (string)($appt['start_at'] ?? ''),
            (string)($appt['service_name'] ?? '')
        );
        wbInsertUserNotification(
            $pdo,
            $userId,
            $appointmentId,
            $notif['type'],
            $notif['title'],
            $notif['message'],
            (string)($appt['business_name'] ?? '')
        );
    } catch (Throwable $notifEx) {
        error_log('[mobile/customer/appointments/cancel.php notif] ' . $notifEx->getMessage());
    }

    // ── İşletme bildirimi (opsiyonel — ana akışı kesmez) ─────────────────
    try {
        $businessId = (int)($appt['business_id'] ?? 0);
        if ($businessId > 0) {
            $pdo->prepare("
                UPDATE notifications
                SET type = 'cancellation', result = 'pending', is_read = 0, created_at = NOW()
                WHERE appointment_id = ? AND business_id = ? AND type = 'booking'
                LIMIT 1
            ")->execute([$appointmentId, $businessId]);

            $affected = (int)$pdo->query('SELECT ROW_COUNT()')->fetchColumn();
            if ($affected === 0) {
                $pdo->prepare("
                    INSERT INTO notifications
                        (business_id, appointment_id, type, customer_name, customer_phone,
                         service_name, appointment_start, result, created_at)
                    VALUES (?, ?, 'cancellation', ?, ?, ?, ?, 'pending', NOW())
                ")->execute([
                    $businessId,
                    $appointmentId,
                    $appt['customer_name']  ?? null,
                    $appt['customer_phone'] ?? null,
                    $appt['service_name']   ?? null,
                    $appt['start_at']       ?? null,
                ]);
            }
        }
    } catch (Throwable $bizNotifEx) {
        error_log('[mobile/customer/appointments/cancel.php biz_notif] ' . $bizNotifEx->getMessage());
    }

    // TODO (Faz 4B): Email ve SMS bildirimleri — api/user/appointments/cancel.php referans alınacak

    wb_ok([
        'cancelled'              => false,
        'cancellation_requested' => true,
        'appointment_id'         => (string)$appointmentId,
        'status'                 => 'cancellation_requested',
        'message'                => 'İptal talebiniz işletmeye iletildi. Onaylandığında bilgilendirileceksiniz.',
        'cancellation'           => $cancellationSummary,
    ]);

} catch (Throwable $e) {
    error_log('[mobile/customer/appointments/cancel.php] ' . $e->getMessage());
    wb_err('İşlem tamamlanamadı. Lütfen tekrar deneyin.', 500, 'internal_error');
}
