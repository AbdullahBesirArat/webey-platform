<?php
declare(strict_types=1);

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../../_appointment_log.php';
require_once __DIR__ . '/../../_user_notifications.php';
wb_method('POST');

$userId = (int)($user['user_id'] ?? 0);

$in     = wb_body();
$apptId = (int)($in['appointmentId'] ?? $in['id'] ?? 0);

if (!$apptId) {
    wb_err('appointmentId zorunlu', 400, 'missing_param');
}

function wb_user_cancel_phone_norm(?string $phone): string
{
    return substr(preg_replace('/\D/', '', (string)$phone), -10);
}

try {
    $knownPhones = [];
    $pushPhone = static function (?string $candidate) use (&$knownPhones): void {
        $normalized = wb_user_cancel_phone_norm($candidate);
        if ($normalized !== '') {
            $knownPhones[$normalized] = true;
        }
    };

    $pushPhone((string)($user['phone'] ?? ''));

    $customerPhoneStmt = $pdo->prepare('SELECT phone FROM customers WHERE user_id = ? LIMIT 1');
    $customerPhoneStmt->execute([$userId]);
    $pushPhone((string)($customerPhoneStmt->fetchColumn() ?: ''));

    $apptStmt = $pdo->prepare("
        SELECT a.id, a.status, a.start_at, a.business_id, a.customer_phone, a.customer_name,
               a.customer_user_id, s.name AS service_name
        FROM appointments a
        LEFT JOIN services s ON s.id = a.service_id
        WHERE a.id = ?
        LIMIT 1
    ");
    $apptStmt->execute([$apptId]);
    $appt = $apptStmt->fetch();

    if (!$appt) {
        wb_err('Randevu bulunamadi', 404, 'not_found');
    }

    $authorized = ((int)($appt['customer_user_id'] ?? 0) === $userId);
    $apptPhone  = wb_user_cancel_phone_norm((string)($appt['customer_phone'] ?? ''));

    if (!$authorized && $apptPhone !== '' && isset($knownPhones[$apptPhone])) {
        $authorized = true;
    }

    if (!$authorized) {
        wb_err('Bu randevuya erisim yetkiniz yok.', 403, 'forbidden');
    }

    $prevStatus = strtolower((string)($appt['status'] ?? ''));

    if (in_array($prevStatus, ['cancelled', 'rejected', 'declined', 'cancellation_requested'], true)) {
        wb_err('Bu randevu zaten iptal edilmis veya iptal talebi bekliyor', 409, 'already_cancelled');
    }

    if (!in_array($prevStatus, ['pending', 'approved'], true)) {
        wb_err('Bu randevu iptal edilemez (durum: ' . $prevStatus . ')', 400, 'invalid_status');
    }

    if (strtotime((string)$appt['start_at']) <= time()) {
        wb_err('Gecmis randevu iptal edilemez', 409, 'past_appointment');
    }

    $pdo->prepare("UPDATE appointments SET status='cancellation_requested' WHERE id = ?")
        ->execute([$apptId]);

    wb_appt_log(
        $pdo,
        $apptId,
        'cancellation_requested',
        $prevStatus,
        'cancellation_requested',
        $userId ?: null
    );

    try {
        $detailStmt = $pdo->prepare("
            SELECT a.start_at, a.customer_phone, a.customer_user_id, b.name AS business_name, s.name AS service_name
            FROM appointments a
            LEFT JOIN businesses b ON b.id = a.business_id
            LEFT JOIN services s ON s.id = a.service_id
            WHERE a.id = ?
            LIMIT 1
        ");
        $detailStmt->execute([$apptId]);
        $detail = $detailStmt->fetch() ?: [];

        $notifUserId = wbResolveAppointmentUserId($pdo, $detail);
        if ($notifUserId) {
            $notif = wbUserNotifFromStatus(
                'cancellation_requested',
                (string)($detail['business_name'] ?? 'Isletme'),
                (string)($detail['start_at'] ?? ''),
                (string)($detail['service_name'] ?? '')
            );
            wbInsertUserNotification(
                $pdo,
                (int)$notifUserId,
                (int)$apptId,
                $notif['type'],
                $notif['title'],
                $notif['message'],
                (string)($detail['business_name'] ?? '')
            );
        }
    } catch (Throwable $uNotifEx) {
        error_log('[user/appointments/cancel user_notif] ' . $uNotifEx->getMessage());
    }

    try {
        require_once __DIR__ . '/../../../api/_mailer.php';
        require_once __DIR__ . '/../../../api/_email_templates.php';

        $apptFull = $pdo->prepare("
            SELECT a.*, b.name AS business_name, b.address_line, b.city, b.district,
                   s.name AS service_name, st.name AS staff_name,
                   u.email AS owner_email
            FROM appointments a
            LEFT JOIN businesses b ON b.id = a.business_id
            LEFT JOIN services s ON s.id = a.service_id
            LEFT JOIN staff st ON st.id = a.staff_id
            LEFT JOIN users u ON u.id = b.owner_id
            WHERE a.id = ?
            LIMIT 1
        ");
        $apptFull->execute([$apptId]);
        $row = $apptFull->fetch();

        if ($row) {
            $emailData = wbApptToEmailData($row, $pdo);
            $custEmail = (string)($row['customer_email'] ?? '');
            $custName  = (string)($row['customer_name'] ?? 'Musteri');

            if ($custEmail && filter_var($custEmail, FILTER_VALIDATE_EMAIL)) {
                [$subj, $html] = wbEmailCancelRequested($emailData);
                wbMail($custEmail, $custName, $subj, $html);
            }

            if (!empty($emailData['ownerEmail'])) {
                [$subj, $html] = wbEmailCancelRequestBiz($emailData);
                wbMail((string)$emailData['ownerEmail'], (string)($emailData['bizName'] ?? 'Isletme'), $subj, $html);
            }
        }
    } catch (Throwable $mailEx) {
        error_log('[user/appointments/cancel.php mail] ' . $mailEx->getMessage());
    }

    try {
        $businessId = (int)($appt['business_id'] ?? 0);

        $pdo->prepare("
            UPDATE notifications
            SET type = 'cancellation', result = 'pending', is_read = 0, created_at = NOW()
            WHERE appointment_id = ? AND business_id = ? AND type = 'booking'
            LIMIT 1
        ")->execute([$apptId, $businessId]);

        $affected = (int)$pdo->query('SELECT ROW_COUNT()')->fetchColumn();
        if ($affected === 0) {
            $pdo->prepare("
                INSERT INTO notifications
                  (business_id, appointment_id, type, customer_name, customer_phone,
                   service_name, appointment_start, result, created_at)
                VALUES (?, ?, 'cancellation', ?, ?, ?, ?, 'pending', NOW())
            ")->execute([
                $businessId,
                $apptId,
                $appt['customer_name'] ?? null,
                $appt['customer_phone'] ?? null,
                $appt['service_name'] ?? null,
                $appt['start_at'] ?? null,
            ]);
        }
    } catch (Throwable $notifEx) {
        error_log('[user/appointments/cancel.php notification] ' . $notifEx->getMessage());
    }

    try {
        require_once __DIR__ . '/../../../api/_sms.php';
        $custPhone = (string)($appt['customer_phone'] ?? '');
        if ($custPhone !== '') {
            queueSms(
                $pdo,
                $custPhone,
                'Webey: Iptal talebiniz isletmeye iletildi. Onay veya red bildirimi alacaksiniz.',
                'cancellation_requested',
                $apptId
            );
        }
    } catch (Throwable $smsEx) {
        error_log('[user/appointments/cancel.php sms] ' . $smsEx->getMessage());
    }

    wb_ok([
        'status' => 'cancellation_requested',
        'message' => 'Iptal talebiniz isletmeye iletildi. Onaylandiginda bilgilendirileceksiniz.',
    ]);
} catch (Throwable $e) {
    error_log('[user/appointments/cancel.php] ' . $e->getMessage());
    wb_err('Islem tamamlanamadi. Lutfen tekrar deneyin.', 500, 'internal_error');
}
