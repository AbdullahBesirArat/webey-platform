<?php
// api/billing/cron_reminders.php
// Appointment reminder cron (24h and 1h)
declare(strict_types=1);

if (PHP_SAPI !== 'cli' && ($_SERVER['REMOTE_ADDR'] ?? '') !== '127.0.0.1') {
    http_response_code(403);
    exit('Forbidden');
}

require __DIR__ . '/../../db.php';
require __DIR__ . '/../_mailer.php';
require __DIR__ . '/../_email_templates.php';
require __DIR__ . '/../_sms.php';

$now = new DateTimeImmutable('now', new DateTimeZone('Europe/Istanbul'));
$counts = ['email_24h' => 0, 'sms_24h' => 0, 'email_1h' => 0, 'sms_1h' => 0];
$errors = 0;
$appSecret = trim((string)(getenv('APP_SECRET') ?: ($_ENV['APP_SECRET'] ?? '')));

echo '[' . $now->format('Y-m-d H:i:s') . "] Reminder cron started\n";

function shouldSendReminder(PDO $pdo, int $apptId, string $channel, int $remindBefore): bool
{
    $check = $pdo->prepare('SELECT id FROM appointment_reminders WHERE appointment_id=? AND channel=? AND remind_before=? LIMIT 1');
    $check->execute([$apptId, $channel, $remindBefore]);
    if ($check->fetch()) {
        return false;
    }

    $pdo->prepare("INSERT INTO appointment_reminders (appointment_id, channel, remind_before, status, created_at) VALUES (?,?,?,'pending',NOW())")
        ->execute([$apptId, $channel, $remindBefore]);
    return true;
}

function markReminderSent(PDO $pdo, int $apptId, string $channel, int $remindBefore): void
{
    $pdo->prepare("UPDATE appointment_reminders SET status='sent', sent_at=NOW() WHERE appointment_id=? AND channel=? AND remind_before=?")
        ->execute([$apptId, $channel, $remindBefore]);
}

function fetchApptsInWindow(PDO $pdo, string $minInterval, string $maxInterval): array
{
    $stmt = $pdo->prepare("\n        SELECT a.id, a.start_at, a.created_at, a.customer_name, a.customer_email, a.customer_phone,\n               b.name AS biz_name, b.address_line, b.city, b.district,\n               s.name AS service_name, st.name AS staff_name\n        FROM appointments a\n        LEFT JOIN businesses b ON b.id = a.business_id\n        LEFT JOIN services s ON s.id = a.service_id\n        LEFT JOIN staff st ON st.id = a.staff_id\n        WHERE a.status IN ('approved','pending')\n          AND a.start_at BETWEEN DATE_ADD(NOW(), INTERVAL $minInterval)\n                           AND DATE_ADD(NOW(), INTERVAL $maxInterval)\n        LIMIT 200\n    ");
    $stmt->execute();
    return $stmt->fetchAll(PDO::FETCH_ASSOC);
}

function buildIcsUrl(int $apptId, string $createdAt, string $appSecret): string
{
    if ($appSecret === '') {
        return '';
    }
    $sig = hash_hmac('sha256', $apptId . '|' . $createdAt, $appSecret);
    return 'https://webey.com.tr/api/appointments/export-ics.php?id=' . $apptId . '&sig=' . $sig;
}

function buildReminderEmailHtml(array $d): string
{
    $icsBtn = '';
    if (!empty($d['ics_url'])) {
        $icsBtn = '<a href="' . $d['ics_url'] . '" style="display:inline-block;margin-top:14px;padding:10px 20px;background:#0ea5b3;color:#fff;border-radius:8px;text-decoration:none;font-size:14px;font-weight:600;">Takvime Ekle</a>';
    }

    $staffLine = '';
    if (!empty($d['staff'])) {
        $staffLine = '<p style="margin:4px 0;color:#555;">Personel: <strong>' . htmlspecialchars((string)$d['staff'], ENT_QUOTES, 'UTF-8') . '</strong></p>';
    }

    $customerName = htmlspecialchars((string)$d['customer_name'], ENT_QUOTES, 'UTF-8');
    $bizName = htmlspecialchars((string)$d['biz_name'], ENT_QUOTES, 'UTF-8');
    $service = htmlspecialchars((string)$d['service'], ENT_QUOTES, 'UTF-8');
    $date = htmlspecialchars((string)$d['date'], ENT_QUOTES, 'UTF-8');
    $time = htmlspecialchars((string)$d['time'], ENT_QUOTES, 'UTF-8');
    $address = htmlspecialchars((string)$d['address'], ENT_QUOTES, 'UTF-8');
    $period = htmlspecialchars((string)$d['period'], ENT_QUOTES, 'UTF-8');

    return "<!DOCTYPE html><html><head><meta charset='utf-8'/></head><body style='font-family:Inter,sans-serif;background:#f5f5f5;padding:24px;'><div style='max-width:520px;margin:0 auto;background:#fff;border-radius:16px;overflow:hidden;'><div style='background:linear-gradient(135deg,#0ea5b3,#0b6ef4);padding:28px 32px;text-align:center;'><h1 style='color:#fff;margin:0;font-size:22px;'>Randevu Hatirlatmasi</h1><p style='color:rgba(255,255,255,.8);margin:6px 0 0;font-size:14px;'>{$period} sonra randevunuz var</p></div><div style='padding:28px 32px;'><p style='color:#333;font-size:16px;'>Merhaba <strong>{$customerName}</strong>,</p><div style='background:#f8f9ff;border-radius:12px;padding:18px;margin:16px 0;border-left:4px solid #0ea5b3;'><p style='margin:4px 0;color:#333;font-size:17px;font-weight:700;'>{$bizName}</p><p style='margin:4px 0;color:#555;'>Hizmet: <strong>{$service}</strong></p>{$staffLine}<p style='margin:8px 0 4px;color:#555;'>Tarih: <strong>{$date}</strong> saat <strong>{$time}</strong></p><p style='margin:4px 0;color:#888;font-size:13px;'>Adres: {$address}</p></div>{$icsBtn}</div><div style='background:#f8f9fa;padding:16px 32px;text-align:center;'><p style='color:#aaa;font-size:12px;margin:0;'>© 2026 Webey</p></div></div></body></html>";
}

$appts24 = fetchApptsInWindow($pdo, '23 HOUR', '25 HOUR');
echo '  24h window: ' . count($appts24) . " appointments\n";

foreach ($appts24 as $appt) {
    $apptId = (int)$appt['id'];
    $dt = new DateTimeImmutable($appt['start_at'], new DateTimeZone('Europe/Istanbul'));
    $date = $dt->format('d.m.Y');
    $time = $dt->format('H:i');
    $addr = implode(', ', array_filter([$appt['address_line'] ?? '', $appt['district'] ?? '', $appt['city'] ?? '']));

    if (!empty($appt['customer_email']) && shouldSendReminder($pdo, $apptId, 'email', 24)) {
        try {
            $icsUrl = buildIcsUrl($apptId, (string)$appt['created_at'], $appSecret);
            $subject = 'Yarin randevunuz var - ' . ($appt['biz_name'] ?? 'Webey');
            $html = buildReminderEmailHtml([
                'customer_name' => $appt['customer_name'],
                'biz_name' => $appt['biz_name'] ?? '',
                'service' => $appt['service_name'] ?? '',
                'staff' => $appt['staff_name'] ?? '',
                'date' => $date,
                'time' => $time,
                'address' => $addr,
                'ics_url' => $icsUrl,
                'period' => '24 saat',
            ]);
            $pdo->prepare("INSERT INTO email_queue (to_email,to_name,subject,body_html,status,created_at) VALUES (?,?,?,?,'pending',NOW())")
                ->execute([$appt['customer_email'], $appt['customer_name'], $subject, $html]);
            markReminderSent($pdo, $apptId, 'email', 24);
            $counts['email_24h']++;
        } catch (Throwable $e) {
            $errors++;
            error_log('[cron_reminders][email24] #' . $apptId . ' ' . $e->getMessage());
        }
    }

    if (!empty($appt['customer_phone']) && shouldSendReminder($pdo, $apptId, 'sms', 24)) {
        try {
            queueSms($pdo, $appt['customer_phone'], smsReminder24h($appt['biz_name'] ?? 'Webey', $date, $time), 'reminder_24h', $apptId);
            markReminderSent($pdo, $apptId, 'sms', 24);
            $counts['sms_24h']++;
        } catch (Throwable $e) {
            $errors++;
            error_log('[cron_reminders][sms24] #' . $apptId . ' ' . $e->getMessage());
        }
    }
}

$appts1h = fetchApptsInWindow($pdo, '50 MINUTE', '70 MINUTE');
echo '  1h window: ' . count($appts1h) . " appointments\n";

foreach ($appts1h as $appt) {
    $apptId = (int)$appt['id'];
    $dt = new DateTimeImmutable($appt['start_at'], new DateTimeZone('Europe/Istanbul'));
    $date = $dt->format('d.m.Y');
    $time = $dt->format('H:i');
    $addr = implode(', ', array_filter([$appt['address_line'] ?? '', $appt['district'] ?? '', $appt['city'] ?? '']));

    if (!empty($appt['customer_email']) && shouldSendReminder($pdo, $apptId, 'email', 1)) {
        try {
            $subject = '1 saate randevunuz var - ' . ($appt['biz_name'] ?? 'Webey');
            $html = buildReminderEmailHtml([
                'customer_name' => $appt['customer_name'],
                'biz_name' => $appt['biz_name'] ?? '',
                'service' => $appt['service_name'] ?? '',
                'staff' => $appt['staff_name'] ?? '',
                'date' => $date,
                'time' => $time,
                'address' => $addr,
                'ics_url' => '',
                'period' => '1 saat',
            ]);
            $pdo->prepare("INSERT INTO email_queue (to_email,to_name,subject,body_html,status,created_at) VALUES (?,?,?,?,'pending',NOW())")
                ->execute([$appt['customer_email'], $appt['customer_name'], $subject, $html]);
            markReminderSent($pdo, $apptId, 'email', 1);
            $counts['email_1h']++;
        } catch (Throwable $e) {
            $errors++;
            error_log('[cron_reminders][email1h] #' . $apptId . ' ' . $e->getMessage());
        }
    }

    if (!empty($appt['customer_phone']) && shouldSendReminder($pdo, $apptId, 'sms', 1)) {
        try {
            queueSms($pdo, $appt['customer_phone'], smsReminder1h($appt['biz_name'] ?? 'Webey', $time), 'reminder_1h', $apptId);
            markReminderSent($pdo, $apptId, 'sms', 1);
            $counts['sms_1h']++;
        } catch (Throwable $e) {
            $errors++;
            error_log('[cron_reminders][sms1h] #' . $apptId . ' ' . $e->getMessage());
        }
    }
}

echo '[' . date('H:i:s') . "] Completed - email24:{$counts['email_24h']} sms24:{$counts['sms_24h']} email1h:{$counts['email_1h']} sms1h:{$counts['sms_1h']} errors:{$errors}\n";