<?php
declare(strict_types=1);
/**
 * api/calendar/approve-cancellation.php
 * POST { id } - Iptal talebini onayla -> status = cancelled
 */

require_once __DIR__ . '/../admin/_bootstrap.php';
require_once __DIR__ . '/../../api/_appointment_log.php';
require_once __DIR__ . '/../../api/_user_notifications.php';
wb_method('POST');

$bid = (int)($user['business_id'] ?? 0);
if (!$bid) wb_err('Isletme bulunamadi', 404, 'business_not_found');

$in     = wb_body();
$apptId = (int)($in['id'] ?? 0);
if (!$apptId) wb_err('id zorunlu', 400, 'missing_id');

try {
    $check = $pdo->prepare("SELECT id, customer_name, customer_phone, customer_email FROM appointments WHERE id = ? AND business_id = ? AND status = 'cancellation_requested'");
    $check->execute([$apptId, $bid]);
    $appt = $check->fetch();

    if (!$appt) {
        $exists = $pdo->prepare('SELECT status FROM appointments WHERE id = ? AND business_id = ?');
        $exists->execute([$apptId, $bid]);
        $row = $exists->fetch();
        if ($row && $row['status'] === 'cancelled') {
            wb_ok(['id' => (string)$apptId, 'status' => 'cancelled', 'message' => 'Zaten iptal edilmis.']);
        }
        wb_err('Randevu bulunamadi veya iptal talebi durumunda degil', 404, 'not_found');
    }

    $pdo->prepare("UPDATE appointments SET status = 'cancelled', updated_at = NOW() WHERE id = ? AND business_id = ?")
        ->execute([$apptId, $bid]);

    wb_appt_log(
        $pdo,
        $apptId,
        'cancellation_approved',
        'cancellation_requested',
        'cancelled',
        (int)($_SESSION['user_id'] ?? 0) ?: null
    );

    try {
        require_once __DIR__ . '/../../api/_mailer.php';
        require_once __DIR__ . '/../../api/_email_templates.php';

        $fStmt = $pdo->prepare(
            "SELECT a.*, b.name AS business_name, s.name AS service_name, st.name AS staff_name, u.email AS owner_email
             FROM appointments a
             LEFT JOIN businesses b ON b.id = a.business_id
             LEFT JOIN services s ON s.id = a.service_id
             LEFT JOIN staff st ON st.id = a.staff_id
             LEFT JOIN users u ON u.id = b.owner_id
             WHERE a.id = ? LIMIT 1"
        );
        $fStmt->execute([$apptId]);
        $row = $fStmt->fetch();

        if ($row) {
            $emailData = wbApptToEmailData($row, $pdo);
            if (!empty($row['customer_email']) && filter_var((string)$row['customer_email'], FILTER_VALIDATE_EMAIL)) {
                [$subj, $html] = wbEmailCancelApproved($emailData);
                wbMail((string)$row['customer_email'], (string)($row['customer_name'] ?? 'Musteri'), $subj, $html);
            }
            $ownerEmail = (string)($emailData['ownerEmail'] ?? '');
            if ($ownerEmail && filter_var($ownerEmail, FILTER_VALIDATE_EMAIL)) {
                [$ownerSubj, $ownerHtml] = wbEmailApptStatusBiz($emailData);
                wbMail($ownerEmail, (string)($emailData['bizName'] ?? 'Isletme'), $ownerSubj, $ownerHtml);
            }

            $notifUserId = wbResolveAppointmentUserId($pdo, $row);
            if ($notifUserId) {
                $notif = wbUserNotifFromStatus(
                    'cancelled',
                    (string)($row['business_name'] ?? 'Isletme'),
                    (string)($row['start_at'] ?? ''),
                    (string)($row['service_name'] ?? '')
                );
                wbInsertUserNotification(
                    $pdo,
                    (int)$notifUserId,
                    (int)$apptId,
                    $notif['type'],
                    $notif['title'],
                    $notif['message'],
                    (string)($row['business_name'] ?? '')
                );
            }
        }
    } catch (Throwable $mailEx) {
        error_log('[approve-cancellation mail] ' . $mailEx->getMessage());
    }

    try {
        require_once __DIR__ . '/../../api/_sms.php';
        if (!empty($appt['customer_phone'])) {
            queueSms($pdo, (string)$appt['customer_phone'], 'Webey: Iptal talebiniz onaylandi. Randevunuz iptal edilmistir.', 'cancelled', $apptId);
        }
    } catch (Throwable $smsEx) {
        error_log('[approve-cancellation sms] ' . $smsEx->getMessage());
    }

    try {
        $pdo->prepare("UPDATE notifications SET result = 'cancel_approved', is_read = 0 WHERE appointment_id = ? AND business_id = ? AND type = 'cancellation' AND result = 'pending'")
            ->execute([$apptId, $bid]);
    } catch (Throwable $nErr) {
        error_log('[approve-cancellation notif] ' . $nErr->getMessage());
    }

    wb_ok(['id' => (string)$apptId, 'status' => 'cancelled', 'message' => 'Iptal onaylandi.']);
} catch (Throwable $e) {
    error_log('[calendar/approve-cancellation] ' . $e->getMessage());
    wb_err('Islem tamamlanamadi', 500, 'internal_error');
}
