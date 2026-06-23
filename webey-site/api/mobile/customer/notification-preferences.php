<?php
declare(strict_types=1);
/**
 * api/mobile/customer/notification-preferences.php
 * GET — Token sahibi müşterinin bildirim tercihlerini döner.
 * POST — Müşterinin bildirim tercihlerini günceller.
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';

$session = mobile_auth($pdo, 'customer');
$userId = (int)$session['user_id'];

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
if ($method !== 'GET' && $method !== 'POST') {
    wb_err('Yöntem desteklenmiyor', 405, 'method_not_allowed');
}

$defaults = [
    'appointment_enabled' => true,
    'review_enabled' => true,
    'payment_enabled' => true,
    'system_enabled' => true,
    'appt_approved' => true,
    'appt_reminders' => true,
    'campaigns' => true,
    'channel_push' => true,
    'channel_email' => false,
    'channel_sms' => false,
    'sound' => true,
    'vibration' => true,
    'sound_mode' => 'sound',
];

$stringKeys = ['sound_mode'];

try {
    $check = $pdo->prepare(
        "SELECT COUNT(*) FROM information_schema.TABLES
         WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'notification_preferences'"
    );
    $check->execute();
    $tableExists = (int)$check->fetchColumn() > 0;

    if (!$tableExists) {
        wb_ok(['prefs' => $defaults, 'persisted' => false]);
    }

    if ($method === 'GET') {
        $stmt = $pdo->prepare(
            "SELECT prefs_json FROM notification_preferences
             WHERE user_type = 'customer' AND user_id = ? LIMIT 1"
        );
        $stmt->execute([$userId]);
        $row = $stmt->fetch();
        $prefs = $defaults;
        if ($row && !empty($row['prefs_json'])) {
            $decoded = json_decode((string)$row['prefs_json'], true);
            if (is_array($decoded)) {
                foreach ($decoded as $k => $v) {
                    $key = (string)$k;
                    if (in_array($key, $stringKeys, true)) {
                        $mode = (string)$v;
                        $prefs[$key] = in_array($mode, ['sound', 'vibrate', 'silent'], true) ? $mode : $defaults[$key];
                    } else {
                        $prefs[$key] = (bool)$v;
                    }
                }
            }
        }
        wb_ok(['prefs' => $prefs, 'persisted' => true]);
    }

    // POST
    $body = wb_body();
    $input = $body['prefs'] ?? $body;
    if (!is_array($input)) {
        wb_err('prefs zorunlu', 422, 'missing_prefs');
    }
    $merged = $defaults;
    foreach ($input as $k => $v) {
        $key = (string)$k;
        if (in_array($key, $stringKeys, true)) {
            $mode = (string)$v;
            $merged[$key] = in_array($mode, ['sound', 'vibrate', 'silent'], true) ? $mode : $defaults[$key];
        } else {
            $merged[$key] = (bool)$v;
        }
    }
    $payload = json_encode($merged, JSON_UNESCAPED_UNICODE);
    $pdo->prepare(
        "INSERT INTO notification_preferences (user_type, user_id, prefs_json, created_at, updated_at)
         VALUES ('customer', ?, ?, NOW(), NOW())
         ON DUPLICATE KEY UPDATE prefs_json = VALUES(prefs_json), updated_at = NOW()"
    )->execute([$userId, $payload]);

    wb_ok(['prefs' => $merged, 'persisted' => true]);
} catch (Throwable $e) {
    error_log('[mobile/customer/notification-preferences.php] ' . $e->getMessage());
    wb_err('Bildirim tercihleri işlenemedi', 500, 'internal_error');
}
