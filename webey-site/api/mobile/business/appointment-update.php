<?php
declare(strict_types=1);
/**
 * api/mobile/business/appointment-update.php
 * POST - Token sahibi isletmenin randevu durumunu gunceller.
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';
require_once __DIR__ . '/_helpers.php';
require_once __DIR__ . '/../../_appointment_log.php';
require_once __DIR__ . '/../../_appointment_push.php';
require_once __DIR__ . '/../../_user_notifications.php';
require_once __DIR__ . '/../_cancellation.php';

wb_method('POST');

$auth = mobile_auth($pdo, ['business', 'admin']);
$ctx = mobile_business_context($pdo, $auth);
$businessId = (int)$ctx['business_id'];
$actorUserId = (int)$ctx['user_id'];

$body = wb_body();
$appointmentId = (int)($body['appointment_id'] ?? $body['id'] ?? 0);
$status = strtolower(trim((string)($body['status'] ?? '')));
$noteProvided = array_key_exists('note', $body);
$note = $noteProvided ? mb_substr(trim((string)$body['note']), 0, 2000) : null;

$allowedStatuses = ['approved', 'rejected', 'completed', 'cancelled', 'no_show'];
if ($appointmentId <= 0) {
    wb_err('appointment_id zorunlu', 400, 'missing_param');
}
if (!in_array($status, $allowedStatuses, true)) {
    wb_err('Gecersiz status degeri', 400, 'invalid_status');
}

try {
    $pdo->beginTransaction();

    $appt = mobile_business_require_appointment($pdo, $businessId, $appointmentId, true);
    $prevStatus = (string)($appt['status'] ?? '');

    if (in_array($status, ['completed', 'no_show'], true)) {
        if ($prevStatus !== 'approved') {
            $pdo->rollBack();
            wb_err('Bu islem yalnizca onaylanmis randevular icin yapilabilir', 409, 'invalid_transition');
        }
        $startAtRaw = (string)($appt['start_at'] ?? '');
        try {
            $tz = new DateTimeZone('Europe/Istanbul');
            $startAt = new DateTimeImmutable($startAtRaw, $tz);
            $now = new DateTimeImmutable('now', $tz);
            if ($startAt > $now) {
                $pdo->rollBack();
                wb_err('Randevu saati gecmeden musteri katilim durumu isaretlenemez', 409, 'appointment_not_started');
            }
        } catch (Throwable) {
            $pdo->rollBack();
            wb_err('Randevu zamani dogrulanamadi', 409, 'invalid_appointment_time');
        }
    }

    if (in_array($prevStatus, ['cancelled', 'rejected', 'declined', 'no_show', 'completed'], true)
        && $prevStatus !== $status) {
        $pdo->rollBack();
        wb_err('Terminal durumdaki randevu tekrar guncellenemez', 409, 'terminal_status');
    }

    $fields = ['status = ?'];
    $params = [$status];

    if ($status === 'completed') {
        $fields[] = 'attended = 1';
    } elseif ($status === 'no_show') {
        $fields[] = 'attended = 0';
    }

    if ($noteProvided) {
        $fields[] = 'notes = ?';
        $params[] = $note !== '' ? $note : null;
    }

    $params[] = $appointmentId;
    $params[] = $businessId;

    $updateSql = 'UPDATE appointments SET '
        . implode(', ', $fields)
        . ', updated_at = NOW() WHERE id = ? AND business_id = ?';
    $pdo->prepare($updateSql)->execute($params);

    // No-show finansal hesabı (snapshot politikadan, ödenmiş kapora üzerinden).
    $noShowFinancial = null;
    if ($status === 'no_show'
        && mobile_table_has_column($pdo, 'appointments', 'free_cancel_hours_snapshot')) {
        try {
            $depHasStatus = mobile_table_has_column($pdo, 'appointments', 'deposit_status');
            $selCols = 'start_at, deposit_required, deposit_amount'
                . ($depHasStatus ? ', deposit_status' : '')
                . ', free_cancel_hours_snapshot, late_cancel_fee_pct_snapshot, no_show_refund_pct_snapshot, paid_deposit_amount_snapshot';
            $dStmt = $pdo->prepare("SELECT $selCols FROM appointments WHERE id = ? LIMIT 1");
            $dStmt->execute([$appointmentId]);
            $dRow = $dStmt->fetch() ?: [];
            $quote = wb_cancellation_quote_for_appointment($pdo, $dRow, $businessId, 'no_show');
            $pdo->prepare(
                'UPDATE appointments SET
                    paid_deposit_amount_snapshot = ?, cancel_refund_amount = ?,
                    cancel_retained_amount = ?, cancel_rule_result = ?
                 WHERE id = ? AND business_id = ?'
            )->execute([
                $quote['paid_deposit'], $quote['refund_amount'],
                $quote['retained_amount'], $quote['rule_result'],
                $appointmentId, $businessId,
            ]);
            $noShowFinancial = [
                'paid_deposit'    => $quote['paid_deposit'],
                'refund_amount'   => $quote['refund_amount'],
                'retained_amount' => $quote['retained_amount'],
                'rule_result'     => $quote['rule_result'],
                'headline'        => $quote['headline'],
                'message'         => $quote['message'],
                'manual_refund'   => $quote['manual_refund'],
            ];
        } catch (Throwable $nsEx) {
            error_log('[mobile/business/appointment-update.php no_show] ' . $nsEx->getMessage());
        }
    }

    if ($prevStatus !== $status) {
        wb_appt_log($pdo, $appointmentId, 'status_changed', $prevStatus, $status, $actorUserId);
    }
    if ($noteProvided) {
        wb_appt_log($pdo, $appointmentId, 'note_updated', null, null, $actorUserId);
    }

    $notificationResult = match ($status) {
        'approved' => 'approved',
        'rejected' => 'rejected',
        'cancelled' => 'cancelled',
        default => 'info',
    };

    $pdo->prepare("
        UPDATE notifications
        SET result = ?, is_read = 1, read_at = NOW()
        WHERE appointment_id = ?
          AND business_id = ?
          AND type IN ('booking','cancellation')
          AND result = 'pending'
    ")->execute([$notificationResult, $appointmentId, $businessId]);

    try {
        $notifUserId = wbResolveAppointmentUserId($pdo, $appt);
        if ($notifUserId) {
            $notif = wbUserNotifFromStatus(
                $status,
                (string)($appt['business_name'] ?? 'Isletme'),
                (string)($appt['start_at'] ?? ''),
                (string)($appt['service_name'] ?? '')
            );
            wbInsertUserNotification(
                $pdo,
                $notifUserId,
                $appointmentId,
                $notif['type'],
                $notif['title'],
                $notif['message'],
                (string)($appt['business_name'] ?? '')
            );
        }
    } catch (Throwable $notifEx) {
        error_log('[mobile/business/appointment-update.php notif] ' . $notifEx->getMessage());
    }

    $pdo->commit();

    if ($prevStatus !== $status) {
        wb_appt_send_customer_status_push($pdo, $appointmentId, $status);
    }

    wb_ok([
        'updated' => true,
        'appointment_id' => $appointmentId,
        'status' => $status,
        'no_show_financial' => $noShowFinancial,
    ]);
} catch (Throwable $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    error_log('[mobile/business/appointment-update.php] ' . $e->getMessage());
    wb_err('Randevu guncellenemedi', 500, 'internal_error');
}
