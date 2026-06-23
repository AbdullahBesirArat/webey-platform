<?php
declare(strict_types=1);
/**
 * api/appointments/setStatus.php
 * POST { id, status?, attended? } - randevu durumu guncelle
 * Admin auth gerekli
 */

require_once __DIR__ . '/../admin/_bootstrap.php';
require_once __DIR__ . '/../_appointment_log.php';
require_once __DIR__ . '/../_user_notifications.php';
wb_method('POST');

$businessId = (int)($_SESSION['business_id'] ?? 0);
if (!$businessId) {
    wb_err('Isletme bulunamadi', 403, 'no_business');
}

$data = wb_body();

$appointmentId = $data['id'] ?? $data['appointmentId'] ?? null;
if (!$appointmentId) {
    wb_err('Missing appointment id', 400, 'missing_param');
}

$status   = $data['status'] ?? null;
$attended = array_key_exists('attended', $data) ? $data['attended'] : null;

$fields = [];
$params = [];

if ($status !== null) {
    $allowedStatuses = ['pending', 'approved', 'cancelled', 'no_show', 'rejected', 'declined'];
    if (!in_array($status, $allowedStatuses, true)) {
        wb_err('Invalid status value', 400, 'invalid_status');
    }
    $fields[] = 'status = ?';
    $params[] = $status;
    if ($status === 'no_show') {
        $fields[] = 'attended = 0';
    }
}

if ($attended !== null) {
    $fields[] = 'attended = ?';
    $params[] = $attended ? 1 : 0;
}

if (!$fields) {
    wb_ok(['updated' => false, 'message' => 'Nothing to update']);
}

try {
    $pdo->beginTransaction();

    $prevRow = $pdo->prepare('SELECT status FROM appointments WHERE id = ? AND business_id = ? LIMIT 1 FOR UPDATE');
    $prevRow->execute([$appointmentId, $businessId]);
    $prevData = $prevRow->fetch();

    if (!$prevData) {
        $pdo->rollBack();
        wb_err('Randevu bulunamadi', 404, 'not_found');
    }

    $prevStatus = (string)$prevData['status'];

    $execParams   = $params;
    $execParams[] = $appointmentId;
    $execParams[] = $businessId;

    $sql = 'UPDATE appointments SET ' . implode(', ', $fields) . ', updated_at = NOW() WHERE id = ? AND business_id = ?';
    $pdo->prepare($sql)->execute($execParams);

    $actorUserId = (int)($_SESSION['user_id'] ?? 0) ?: null;

    if ($status !== null && $prevStatus !== $status) {
        wb_appt_log($pdo, $appointmentId, 'status_changed', $prevStatus, $status, $actorUserId);
    }
    if ($attended !== null) {
        wb_appt_log($pdo, $appointmentId, 'attended_marked', null, $attended ? 'attended' : 'no_show', $actorUserId);
    }

    $pdo->commit();

    if ($status !== null) {
        try {
            require_once __DIR__ . '/../_mailer.php';
            require_once __DIR__ . '/../_email_templates.php';

            $apptFull = $pdo->prepare(
                "SELECT a.*, b.name AS business_name, b.address_line, b.city, b.district,
                        b.phone AS business_phone, b.map_url, b.latitude, b.longitude,
                        s.name AS service_name, st.name AS staff_name,
                        u.email AS owner_email
                 FROM appointments a
                 LEFT JOIN businesses b ON b.id = a.business_id
                 LEFT JOIN services   s ON s.id = a.service_id
                 LEFT JOIN staff     st ON st.id = a.staff_id
                 LEFT JOIN users      u ON u.id = b.owner_id
                 WHERE a.id = ?
                 LIMIT 1"
            );
            $apptFull->execute([$appointmentId]);
            $row = $apptFull->fetch();

            if ($row) {
                $emailData = wbApptToEmailData($row, $pdo);
                $custEmail = (string)($row['customer_email'] ?? '');
                $custName  = (string)($row['customer_name'] ?? 'Musteri');

                if ($custEmail && filter_var($custEmail, FILTER_VALIDATE_EMAIL)) {
                    if ($status === 'approved') {
                        [$subj, $html] = wbEmailApptApproved($emailData);
                        wbMail($custEmail, $custName, $subj, $html);
                    } elseif (in_array($status, ['cancelled', 'rejected', 'declined'], true)) {
                        [$subj, $html] = wbEmailApptCancelled($emailData);
                        wbMail($custEmail, $custName, $subj, $html);
                    } else {
                        $emailData['status'] = $status;
                        [$subj, $html] = wbEmailApptConfirm($emailData);
                        wbMail($custEmail, $custName, $subj, $html);
                    }
                }

                $ownerEmail = (string)($emailData['ownerEmail'] ?? '');
                if ($ownerEmail && filter_var($ownerEmail, FILTER_VALIDATE_EMAIL)) {
                    [$ownerSubj, $ownerHtml] = wbEmailApptStatusBiz($emailData);
                    wbMail($ownerEmail, (string)($emailData['bizName'] ?? 'Isletme'), $ownerSubj, $ownerHtml);
                }

                $notifUserId = wbResolveAppointmentUserId($pdo, $row);
                if ($notifUserId) {
                    $notif = wbUserNotifFromStatus(
                        (string)$status,
                        (string)($row['business_name'] ?? 'Isletme'),
                        (string)($row['start_at'] ?? ''),
                        (string)($row['service_name'] ?? '')
                    );
                    wbInsertUserNotification(
                        $pdo,
                        (int)$notifUserId,
                        (int)$appointmentId,
                        $notif['type'],
                        $notif['title'],
                        $notif['message'],
                        (string)($row['business_name'] ?? '')
                    );
                }

                try {
                    require_once __DIR__ . '/../_sms.php';
                    $custPhone = (string)($row['customer_phone'] ?? '');
                    if ($custPhone) {
                        $dt      = new DateTimeImmutable((string)$row['start_at'], new DateTimeZone('Europe/Istanbul'));
                        $bizName = (string)($row['business_name'] ?? 'Isletme');
                        if ($status === 'approved') {
                            queueSms($pdo, $custPhone, smsApptApproved($bizName, $dt->format('d.m.Y'), $dt->format('H:i')), 'approved', (int)$appointmentId);
                        } elseif (in_array($status, ['cancelled', 'rejected', 'declined'], true)) {
                            queueSms($pdo, $custPhone, smsApptRejected($bizName), 'rejected', (int)$appointmentId);
                        }
                    }
                } catch (Throwable $smsEx) {
                    error_log('[setStatus.php sms] ' . $smsEx->getMessage());
                }
            }
        } catch (Throwable $mailEx) {
            error_log('[setStatus mail] ' . $mailEx->getMessage());
        }
    }

    wb_ok(['updated' => true, 'data' => ['id' => (string)$appointmentId, 'status' => $status, 'attended' => $attended]]);
} catch (Throwable $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    error_log('[appointments/setStatus.php] ' . $e->getMessage());
    wb_err('Randevu guncellenemedi', 500, 'internal_error');
}
