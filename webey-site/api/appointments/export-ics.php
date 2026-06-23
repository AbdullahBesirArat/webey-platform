<?php
// api/appointments/export-ics.php
// Randevuyu iCal (.ics) formatinda indirir.
// Public signed link: GET ?id=<appointment_id>&sig=<hmac_sha256>
// Authenticated access: GET ?id=<appointment_id>
declare(strict_types=1);

require_once __DIR__ . '/../_public_bootstrap.php';

wb_method('GET');

$id = (int)($_GET['id'] ?? 0);
$sig = trim((string)($_GET['sig'] ?? ''));
$token = trim((string)($_GET['token'] ?? '')); // legacy param

if ($token !== '') {
    wb_err('Eski token formati desteklenmiyor', 410, 'legacy_token_removed');
}
if ($id <= 0) {
    wb_err('Gecersiz randevu id', 400, 'invalid_id');
}

function wb_get_app_secret(): string
{
    $secret = (string)(getenv('APP_SECRET') ?: ($_ENV['APP_SECRET'] ?? ''));
    return trim($secret);
}

function wb_build_ics_signature(int $apptId, string $createdAt, string $secret): string
{
    return hash_hmac('sha256', $apptId . '|' . $createdAt, $secret);
}

try {
    $baseStmt = $pdo->prepare("\n        SELECT a.*, b.name AS biz_name, b.address_line, b.city, b.district,\n               s.name AS service_name, st.name AS staff_name\n        FROM appointments a\n        LEFT JOIN businesses b  ON b.id = a.business_id\n        LEFT JOIN services   s  ON s.id = a.service_id\n        LEFT JOIN staff      st ON st.id = a.staff_id\n        WHERE a.id = ?\n        LIMIT 1\n    ");
    $baseStmt->execute([$id]);
    $appt = $baseStmt->fetch();

    if (!$appt) {
        wb_err('Randevu bulunamadi', 404, 'not_found');
    }

    if ($sig !== '') {
        $secret = wb_get_app_secret();
        if ($secret === '') {
            error_log('[export-ics] APP_SECRET is missing');
            wb_err('Servis gecici olarak kullanilamiyor', 503, 'misconfigured');
        }

        if (!preg_match('/^[a-f0-9]{64}$/', $sig)) {
            wb_err('Gecersiz imza formati', 400, 'invalid_signature');
        }

        $expectedSig = wb_build_ics_signature((int)$appt['id'], (string)$appt['created_at'], $secret);
        if (!hash_equals($expectedSig, strtolower($sig))) {
            wb_err('Randevu bulunamadi', 404, 'not_found');
        }
    } else {
        $sessionUserId = (int)($_SESSION['user_id'] ?? 0);
        $sessionRole = (string)($_SESSION['user_role'] ?? '');
        if ($sessionUserId <= 0) {
            wb_err('Yetkisiz erisim', 401, 'unauthorized');
        }

        $allowed = false;
        if ($sessionRole === 'superadmin') {
            $allowed = true;
        } elseif ($sessionRole === 'user') {
            $allowed = ((int)($appt['customer_user_id'] ?? 0) === $sessionUserId);
        } else {
            $ownerStmt = $pdo->prepare('SELECT id FROM businesses WHERE id = ? AND owner_id = ? LIMIT 1');
            $ownerStmt->execute([(int)$appt['business_id'], $sessionUserId]);
            $allowed = (bool)$ownerStmt->fetchColumn();
        }

        if (!$allowed) {
            wb_err('Randevu bulunamadi', 404, 'not_found');
        }
    }

    $tz = new DateTimeZone('Europe/Istanbul');
    $dtStamp = gmdate('Ymd\\THis\\Z');
    $dtStart = (new DateTimeImmutable($appt['start_at'], $tz))->format('Ymd\\THis');
    $dtEnd = (new DateTimeImmutable($appt['end_at'], $tz))->format('Ymd\\THis');
    $uid = 'appt-' . $appt['id'] . '@webey.com.tr';
    $summary = ($appt['service_name'] ?? 'Randevu') . ' - ' . ($appt['biz_name'] ?? '');
    $location = implode(', ', array_filter([
        $appt['address_line'] ?? '', $appt['district'] ?? '', $appt['city'] ?? ''
    ]));
    $staff = $appt['staff_name'] ? "\\nPersonel: " . $appt['staff_name'] : '';
    $desc = 'Webey randevunuz.' . $staff . '\\nRandevu ID: #' . $appt['id'];

    $fold = fn(string $line): string => preg_replace('/(.{75})/u', "$1\\r\\n ", $line);

    $ics = "BEGIN:VCALENDAR\r\n"
         . "VERSION:2.0\r\n"
         . "PRODID:-//Webey//Webey Randevu//TR\r\n"
         . "CALSCALE:GREGORIAN\r\n"
         . "METHOD:PUBLISH\r\n"
         . "BEGIN:VEVENT\r\n"
         . "UID:{$uid}\r\n"
         . "DTSTAMP:{$dtStamp}\r\n"
         . "DTSTART;TZID=Europe/Istanbul:{$dtStart}\r\n"
         . "DTEND;TZID=Europe/Istanbul:{$dtEnd}\r\n"
         . $fold("SUMMARY:{$summary}") . "\r\n"
         . $fold("LOCATION:{$location}") . "\r\n"
         . $fold("DESCRIPTION:{$desc}") . "\r\n"
         . "STATUS:CONFIRMED\r\n"
         . "BEGIN:VALARM\r\n"
         . "TRIGGER:-PT1H\r\n"
         . "ACTION:DISPLAY\r\n"
         . "DESCRIPTION:Randevunuza 1 saat kaldi!\r\n"
         . "END:VALARM\r\n"
         . "BEGIN:VALARM\r\n"
         . "TRIGGER:-PT24H\r\n"
         . "ACTION:DISPLAY\r\n"
         . "DESCRIPTION:Yarin randevunuz var!\r\n"
         . "END:VALARM\r\n"
         . "END:VEVENT\r\n"
         . "END:VCALENDAR\r\n";

    $filename = 'webey-randevu-' . $appt['id'] . '.ics';
    header('Content-Type: text/calendar; charset=utf-8');
    header('Content-Disposition: attachment; filename="' . $filename . '"');
    header('Cache-Control: no-store');
    echo $ics;
    exit;

} catch (Throwable $e) {
    error_log('[export-ics.php] ' . $e->getMessage());
    wb_err('ICS dosyasi olusturulamadi', 500, 'internal_error');
}