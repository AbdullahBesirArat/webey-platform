<?php
declare(strict_types=1);
/**
 * api/mobile/customer/device-token.php
 * POST - Customer mobil uygulama FCM device token kaydi.
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';

wb_method('POST');

$auth = mobile_auth($pdo, 'customer');
$userId = (int)$auth['user_id'];
$body = wb_body();

$token = trim((string)($body['token'] ?? ''));
$platform = strtolower(trim((string)($body['platform'] ?? 'android')));
$deviceId = trim((string)($body['device_id'] ?? ''));

if ($token === '') {
    wb_err('token zorunlu', 422, 'missing_token');
}

if (!in_array($platform, ['android', 'ios', 'web', 'unknown'], true)) {
    $platform = 'android';
}

$deviceIdValue = $deviceId !== '' ? mb_substr($deviceId, 0, 120) : null;
$token = mb_substr($token, 0, 255);

try {
    $stmt = $pdo->prepare("
        INSERT INTO mobile_device_tokens
            (user_id, business_id, token, platform, device_id, is_active,
             created_at, updated_at, last_seen_at)
        VALUES
            (?, NULL, ?, ?, ?, 1, NOW(), NOW(), NOW())
        ON DUPLICATE KEY UPDATE
            user_id = VALUES(user_id),
            business_id = NULL,
            platform = VALUES(platform),
            device_id = VALUES(device_id),
            is_active = 1,
            updated_at = NOW(),
            last_seen_at = NOW()
    ");
    $stmt->execute([$userId, $token, $platform, $deviceIdValue]);

    wb_ok([
        'registered' => true,
        'platform' => $platform,
    ]);
} catch (Throwable $e) {
    error_log('[mobile/customer/device-token.php] ' . $e->getMessage());
    wb_err('Cihaz token kaydedilemedi', 500, 'device_token_failed');
}
