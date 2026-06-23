<?php
declare(strict_types=1);
/**
 * api/mobile/business/appointment-action.php
 * POST - FCM notification action token ile randevu onay/red islemi.
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/_helpers.php';
require_once __DIR__ . '/../../_appointment_log.php';
require_once __DIR__ . '/../../_appointment_push.php';
require_once __DIR__ . '/../../_user_notifications.php';

wb_method('POST');

$body = wb_body();
$appointmentId = (int)($body['appointment_id'] ?? $body['id'] ?? 0);
$action = strtolower(trim((string)($body['action'] ?? '')));
$actionToken = trim((string)($body['action_token'] ?? $body['token'] ?? ''));

if ($appointmentId <= 0) {
    wb_err('appointment_id zorunlu', 400, 'missing_appointment_id');
}
if (!in_array($action, ['approve', 'reject'], true)) {
    wb_err('Gecersiz action', 400, 'invalid_action');
}
if ($actionToken === '') {
    wb_err('action_token zorunlu', 400, 'missing_action_token');
}

$newStatus = $action === 'approve' ? 'approved' : 'rejected';
$finalStatuses = ['approved', 'rejected', 'cancelled', 'declined', 'completed', 'no_show'];
$statusChanged = false;
$currentStatus = '';

try {
    $pdo->beginTransaction();

    $stmt = $pdo->prepare(
        mobile_business_appointment_select_sql()
        . ' WHERE a.id = ? LIMIT 1 FOR UPDATE'
    );
    $stmt->execute([$appointmentId]);
    $appt = $stmt->fetch();
    if (!$appt) {
        $pdo->rollBack();
        wb_err('Randevu bulunamadi', 404, 'appointment_not_found');
    }

    $businessId = (int)$appt['business_id'];
    if (!wb_appt_verify_action_token($actionToken, $appointmentId, $businessId, $action)) {
        $pdo->rollBack();
        wb_err('Islem tokeni gecersiz veya suresi dolmus', 403, 'invalid_action_token');
    }

    $currentStatus = (string)($appt['status'] ?? '');
    if ($currentStatus === $newStatus
        || ($action === 'reject' && in_array($currentStatus, ['rejected', 'cancelled', 'declined'], true))
    ) {
        $pdo->commit();
        wb_ok([
            'updated' => false,
            'appointment_id' => $appointmentId,
            'status' => $currentStatus,
            'message' => 'Randevu zaten bu durumda.',
        ]);
    }

    if ($currentStatus !== 'pending' && in_array($currentStatus, $finalStatuses, true)) {
        $pdo->commit();
        wb_ok([
            'updated' => false,
            'appointment_id' => $appointmentId,
            'status' => $currentStatus,
            'message' => 'Randevu durumu degistirilmedi.',
        ]);
    }

    $pdo->prepare(
        'UPDATE appointments SET status = ?, updated_at = NOW() WHERE id = ? AND business_id = ?'
    )->execute([$newStatus, $appointmentId, $businessId]);

    if ($currentStatus !== $newStatus) {
        $statusChanged = true;
        wb_appt_log($pdo, $appointmentId, 'status_changed', $currentStatus, $newStatus, null);
    }

    $notificationResult = $newStatus === 'approved' ? 'approved' : 'rejected';
    $pdo->prepare(
        "UPDATE notifications
            SET result = ?, is_read = 1, read_at = NOW()
          WHERE appointment_id = ?
            AND business_id = ?
            AND type IN ('booking','cancellation')
            AND result = 'pending'"
    )->execute([$notificationResult, $appointmentId, $businessId]);

    try {
        $notifUserId = wbResolveAppointmentUserId($pdo, $appt);
        if ($notifUserId) {
            $notif = wbUserNotifFromStatus(
                $newStatus,
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
        error_log('[mobile/business/appointment-action.php notif] ' . $notifEx->getMessage());
    }

    $pdo->commit();
} catch (Throwable $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    error_log('[mobile/business/appointment-action.php] ' . $e->getMessage());
    wb_err('Randevu aksiyonu tamamlanamadi', 500, 'internal_error');
}

if ($statusChanged) {
    wb_appt_send_customer_status_push($pdo, $appointmentId, $newStatus);
}

wb_ok([
    'updated' => $statusChanged,
    'appointment_id' => $appointmentId,
    'status' => $newStatus,
]);
