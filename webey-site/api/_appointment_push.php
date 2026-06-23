<?php
declare(strict_types=1);

require_once __DIR__ . '/_fcm.php';

const WB_APPOINTMENT_ACTION_TTL_SECONDS = 86400;

function wb_appt_action_secret(): string
{
    $secret = getenv('APPOINTMENT_ACTION_SECRET');
    if ($secret === false || trim((string)$secret) === '') {
        $secret = $_ENV['APPOINTMENT_ACTION_SECRET'] ?? '';
    }
    if (trim((string)$secret) === '') {
        $secret = $_SERVER['APPOINTMENT_ACTION_SECRET'] ?? '';
    }
    if (trim((string)$secret) === '') {
        // File fallback: same pattern as wb_fcm_service_account_path().
        // Secret lives outside the public web root, owned by www-data, mode 640.
        $siblingSecurePath = dirname(__DIR__) . '-secure/appointment_action_secret';
        if (is_file($siblingSecurePath) && is_readable($siblingSecurePath)) {
            $raw = @file_get_contents($siblingSecurePath);
            if ($raw !== false) {
                $secret = trim($raw);
            }
        }
    }

    return trim((string)$secret);
}

function wb_appt_action_sign(int $appointmentId, int $businessId, string $action, int $expiresAt): string
{
    $secret = wb_appt_action_secret();
    if ($secret === '') {
        return '';
    }

    $payload = $appointmentId . '|' . $businessId . '|' . $action . '|' . $expiresAt;
    return hash_hmac('sha256', $payload, $secret);
}

function wb_appt_action_token(int $appointmentId, int $businessId, string $action, ?int $expiresAt = null): string
{
    if (!in_array($action, ['approve', 'reject'], true)) {
        return '';
    }

    $expiresAt ??= time() + WB_APPOINTMENT_ACTION_TTL_SECONDS;
    $signature = wb_appt_action_sign($appointmentId, $businessId, $action, $expiresAt);
    if ($signature === '') {
        error_log('[appointment_action] APPOINTMENT_ACTION_SECRET is not configured.');
        return '';
    }

    $raw = $appointmentId . '|' . $businessId . '|' . $action . '|' . $expiresAt . '|' . $signature;
    return rtrim(strtr(base64_encode($raw), '+/', '-_'), '=');
}

function wb_appt_verify_action_token(string $token, int $appointmentId, int $businessId, string $action): bool
{
    $token = trim($token);
    if ($token === '' || !in_array($action, ['approve', 'reject'], true)) {
        return false;
    }

    $decoded = base64_decode(strtr($token, '-_', '+/'), true);
    if ($decoded === false) {
        return false;
    }

    $parts = explode('|', $decoded);
    if (count($parts) !== 5) {
        return false;
    }

    [$tokenAppointmentId, $tokenBusinessId, $tokenAction, $expiresAt, $signature] = $parts;
    if ((int)$tokenAppointmentId !== $appointmentId
        || (int)$tokenBusinessId !== $businessId
        || $tokenAction !== $action
        || (int)$expiresAt < time()
    ) {
        return false;
    }

    $expected = wb_appt_action_sign($appointmentId, $businessId, $action, (int)$expiresAt);
    return $expected !== '' && hash_equals($expected, $signature);
}

function wb_appt_push_datetime_label(string $startsAt): ?string
{
    try {
        $dt = new DateTimeImmutable($startsAt, new DateTimeZone('Europe/Istanbul'));
    } catch (Throwable) {
        return null;
    }

    $months = [
        1 => 'Oca',
        2 => 'Şub',
        3 => 'Mar',
        4 => 'Nis',
        5 => 'May',
        6 => 'Haz',
        7 => 'Tem',
        8 => 'Ağu',
        9 => 'Eyl',
        10 => 'Eki',
        11 => 'Kas',
        12 => 'Ara',
    ];

    $month = $months[(int)$dt->format('n')] ?? null;
    if ($month === null) {
        return null;
    }

    return (int)$dt->format('j') . ' ' . $month . ' ' . $dt->format('H:i');
}

function wb_appt_business_push_body(string $customerName, string $serviceName, string $startsAt): string
{
    $name = trim($customerName);
    if ($name === '' || $name === 'Musteri' || $name === 'Müşteri') {
        $name = 'Yeni müşteri';
    }

    $service = trim($serviceName);
    if ($service === '') {
        $service = 'Yeni randevu';
    }

    $dateLabel = wb_appt_push_datetime_label($startsAt);
    $parts = [$name, $service];
    if ($dateLabel !== null) {
        $parts[] = $dateLabel;
    }

    return implode(' · ', $parts);
}

function wb_appt_customer_status_push_body(string $businessName, string $serviceName, string $startsAt): string
{
    $business = trim($businessName) !== '' ? trim($businessName) : 'İşletme';
    $service = trim($serviceName) !== '' ? trim($serviceName) : 'Randevu';
    $dateLabel = wb_appt_push_datetime_label($startsAt);
    $parts = [$business, $service];
    if ($dateLabel !== null) {
        $parts[] = $dateLabel;
    }
    return implode(' · ', $parts);
}

function wb_appt_deactivate_invalid_token(PDO $pdo, string $token, string $logPrefix): void
{
    try {
        $pdo->prepare(
            'UPDATE mobile_device_tokens SET is_active = 0, updated_at = NOW() WHERE token = ?'
        )->execute([$token]);
    } catch (Throwable $e) {
        error_log($logPrefix . ' deactivate token failed: ' . $e->getMessage());
    }
}

function wb_push_default_preferences(): array
{
    return [
        'appointment_enabled' => true,
        'review_enabled' => true,
        'payment_enabled' => true,
        'system_enabled' => true,
        'daily_summary' => false,
        'channel_push' => true,
        'sound' => true,
        'vibration' => true,
        'sound_mode' => 'sound',
    ];
}

function wb_push_preferences(PDO $pdo, string $userType, ?int $userId = null, ?int $businessId = null): array
{
    $prefs = wb_push_default_preferences();
    try {
        if (!function_exists('mobile_table_has_column') || !mobile_table_has_column($pdo, 'notification_preferences', 'prefs_json')) {
            return $prefs;
        }
        if ($userType === 'business' && $businessId !== null) {
            $stmt = $pdo->prepare(
                "SELECT prefs_json FROM notification_preferences
                 WHERE user_type = 'business' AND business_id = ? LIMIT 1"
            );
            $stmt->execute([$businessId]);
        } elseif ($userType === 'customer' && $userId !== null) {
            $stmt = $pdo->prepare(
                "SELECT prefs_json FROM notification_preferences
                 WHERE user_type = 'customer' AND user_id = ? LIMIT 1"
            );
            $stmt->execute([$userId]);
        } else {
            return $prefs;
        }
        $row = $stmt->fetch();
        if ($row && !empty($row['prefs_json'])) {
            $decoded = json_decode((string)$row['prefs_json'], true);
            if (is_array($decoded)) {
                $prefs = array_merge($prefs, $decoded);
            }
        }
    } catch (Throwable $e) {
        error_log('[push_preferences] ' . $e->getMessage());
    }
    return $prefs;
}

function wb_push_enabled(array $prefs, string $category): bool
{
    if (($prefs['channel_push'] ?? true) === false) {
        return false;
    }
    $key = $category . '_enabled';
    return ($prefs[$key] ?? true) !== false;
}

function wb_push_sound_mode(array $prefs): string
{
    $mode = (string)($prefs['sound_mode'] ?? '');
    if (in_array($mode, ['sound', 'vibrate', 'silent'], true)) {
        return $mode;
    }
    $sound = ($prefs['sound'] ?? true) !== false;
    $vibration = ($prefs['vibration'] ?? true) !== false;
    if ($sound) {
        return 'sound';
    }
    return $vibration ? 'vibrate' : 'silent';
}

function wb_push_channel_id(string $category, array $prefs): string
{
    $base = match ($category) {
        'review' => 'reviews',
        'payment' => 'payments',
        'system' => 'system',
        default => 'bookings',
    };
    return $base . '_' . wb_push_sound_mode($prefs) . '_v1';
}

function wb_appt_send_customer_status_push(PDO $pdo, int $appointmentId, string $status): void
{
    if (!in_array($status, ['approved', 'rejected', 'cancelled', 'declined'], true)) {
        return;
    }

    try {
        $stmt = $pdo->prepare(
            "SELECT
                a.id,
                a.business_id,
                a.customer_user_id,
                a.start_at,
                a.status,
                b.name AS business_name,
                s.name AS service_name
             FROM appointments a
             LEFT JOIN businesses b ON b.id = a.business_id
             LEFT JOIN services s ON s.id = a.service_id AND s.business_id = a.business_id
             WHERE a.id = ?
             LIMIT 1"
        );
        $stmt->execute([$appointmentId]);
        $appt = $stmt->fetch();
        if (!$appt || empty($appt['customer_user_id'])) {
            return;
        }

        $customerUserId = (int)$appt['customer_user_id'];
        $businessId = (int)$appt['business_id'];
        $prefs = wb_push_preferences($pdo, 'customer', $customerUserId);
        if (!wb_push_enabled($prefs, 'appointment')) {
            error_log('[customer_status_push] skipped by prefs appointment_id=' . $appointmentId);
            return;
        }
        $channelId = wb_push_channel_id('appointment', $prefs);
        $title = $status === 'approved' ? 'Randevunuz onaylandı' : 'Randevunuz reddedildi';
        $body = wb_appt_customer_status_push_body(
            (string)($appt['business_name'] ?? ''),
            (string)($appt['service_name'] ?? ''),
            (string)($appt['start_at'] ?? '')
        );

        $tokenStmt = $pdo->prepare(
            'SELECT DISTINCT token
               FROM mobile_device_tokens
              WHERE is_active = 1
                AND user_id = ?
                AND business_id IS NULL'
        );
        $tokenStmt->execute([$customerUserId]);
        $tokens = $tokenStmt->fetchAll(PDO::FETCH_COLUMN);

        $attempted = 0;
        $sent = 0;
        foreach ($tokens as $rawToken) {
            $token = trim((string)$rawToken);
            if ($token === '') {
                continue;
            }
            $attempted++;
            $result = wb_fcm_send_to_token(
                $token,
                $title,
                $body,
                [
                    'type' => 'appointment_status',
                    'appointment_id' => (string)$appointmentId,
                    'status' => $status,
                    'business_id' => (string)$businessId,
                    'service_name' => (string)($appt['service_name'] ?? ''),
                    'business_name' => (string)($appt['business_name'] ?? ''),
                    'appointment_start' => (string)($appt['start_at'] ?? ''),
                ],
                ['android_channel_id' => $channelId]
            );
            if (!empty($result['ok'])) {
                $sent++;
            } elseif (!empty($result['invalid_token'])) {
                wb_appt_deactivate_invalid_token($pdo, $token, '[customer_status_push]');
            }
        }

        error_log(
            '[customer_status_push] attempted=' . $attempted
            . ' sent=' . $sent
            . ' appointment_id=' . $appointmentId
            . ' status=' . $status
        );
    } catch (Throwable $e) {
        error_log('[customer_status_push] ' . $e->getMessage());
    }
}

/**
 * Müşteriye kapora durumu için bildirim push'u gönderir (best-effort).
 * Ana akışı kesmez; hata yalnızca loglanır.
 */
function wb_appt_send_customer_deposit_push(
    PDO $pdo,
    int $appointmentId,
    string $depositStatus,
    string $title,
    string $body
): void {
    try {
        $stmt = $pdo->prepare(
            'SELECT a.id, a.business_id, a.customer_user_id, b.name AS business_name
               FROM appointments a
               LEFT JOIN businesses b ON b.id = a.business_id
              WHERE a.id = ? LIMIT 1'
        );
        $stmt->execute([$appointmentId]);
        $appt = $stmt->fetch();
        if (!$appt || empty($appt['customer_user_id'])) {
            return;
        }

        $customerUserId = (int)$appt['customer_user_id'];
        $businessId = (int)$appt['business_id'];
        $prefs = wb_push_preferences($pdo, 'customer', $customerUserId);
        if (!wb_push_enabled($prefs, 'appointment')) {
            error_log('[customer_deposit_push] skipped by prefs appointment_id=' . $appointmentId);
            return;
        }
        $channelId = wb_push_channel_id('appointment', $prefs);

        $tokenStmt = $pdo->prepare(
            'SELECT DISTINCT token
               FROM mobile_device_tokens
              WHERE is_active = 1
                AND user_id = ?
                AND business_id IS NULL'
        );
        $tokenStmt->execute([$customerUserId]);
        $tokens = $tokenStmt->fetchAll(PDO::FETCH_COLUMN);

        $attempted = 0;
        $sent = 0;
        foreach ($tokens as $rawToken) {
            $token = trim((string)$rawToken);
            if ($token === '') {
                continue;
            }
            $attempted++;
            $result = wb_fcm_send_to_token(
                $token,
                $title,
                $body,
                [
                    'type' => 'deposit_status',
                    'appointment_id' => (string)$appointmentId,
                    'deposit_status' => $depositStatus,
                    'business_id' => (string)$businessId,
                    'business_name' => (string)($appt['business_name'] ?? ''),
                ],
                ['android_channel_id' => $channelId]
            );
            if (!empty($result['ok'])) {
                $sent++;
            } elseif (!empty($result['invalid_token'])) {
                wb_appt_deactivate_invalid_token($pdo, $token, '[customer_deposit_push]');
            }
        }

        error_log(
            '[customer_deposit_push] attempted=' . $attempted
            . ' sent=' . $sent
            . ' appointment_id=' . $appointmentId
            . ' deposit_status=' . $depositStatus
        );
    } catch (Throwable $e) {
        error_log('[customer_deposit_push] ' . $e->getMessage());
    }
}
