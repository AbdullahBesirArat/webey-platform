<?php
declare(strict_types=1);
/**
 * api/mobile/business/notification-preferences.php
 * GET — Token sahibi işletmenin bildirim tercihlerini döner.
 * POST — İşletmenin bildirim tercihlerini günceller.
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';
require_once __DIR__ . '/_helpers.php';

$auth = mobile_auth($pdo, ['business', 'admin']);
$ctx = mobile_business_context($pdo, $auth);
$businessId = (int)$ctx['business_id'];

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
if ($method !== 'GET' && $method !== 'POST') {
    wb_err('Yöntem desteklenmiyor', 405, 'method_not_allowed');
}

// Yalnızca gerçekten desteklenen olaylar + kanallar. SMS yok (backend SMS
// entegrasyonu yok); fake e-posta/mesaj kanalı yok. alert_style = sound_mode.
$defaults = [
    'appointment_enabled' => true, // yeni randevu + onay/iptal/iptal talebi
    'review_enabled' => true,      // yorum bildirimleri
    'payment_enabled' => true,     // kapora / ödeme bildirimleri
    'system_enabled' => true,      // sistem bildirimleri
    'daily_summary' => false,      // günlük özet (cron)
    'channel_push' => true,        // push ana anahtar
    'sound_mode' => 'sound',       // sound | vibrate | silent
];

// Yalnız bilinen anahtarlar kabul edilir (eski SMS/email/mesaj anahtarları elenir).
$knownKeys = array_keys($defaults);
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
             WHERE user_type = 'business' AND business_id = ? LIMIT 1"
        );
        $stmt->execute([$businessId]);
        $row = $stmt->fetch();
        $prefs = $defaults;
        if ($row && !empty($row['prefs_json'])) {
            $decoded = json_decode((string)$row['prefs_json'], true);
            if (is_array($decoded)) {
                foreach ($decoded as $k => $v) {
                    $key = (string)$k;
                    if (!in_array($key, $knownKeys, true)) {
                        continue; // bilinmeyen/eski anahtar (SMS vb.) elenir
                    }
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

    $body = wb_body();
    $input = $body['prefs'] ?? $body;
    if (!is_array($input)) {
        wb_err('prefs zorunlu', 422, 'missing_prefs');
    }
    $merged = $defaults;
    foreach ($input as $k => $v) {
        $key = (string)$k;
        if (!in_array($key, $knownKeys, true)) {
            continue; // SMS/email/mesaj gibi desteklenmeyen anahtarlar reddedilir
        }
        if (in_array($key, $stringKeys, true)) {
            $mode = (string)$v;
            $merged[$key] = in_array($mode, ['sound', 'vibrate', 'silent'], true) ? $mode : $defaults[$key];
        } else {
            $merged[$key] = (bool)$v;
        }
    }
    $payload = json_encode($merged, JSON_UNESCAPED_UNICODE);
    $pdo->prepare(
        "INSERT INTO notification_preferences (user_type, business_id, prefs_json, created_at, updated_at)
         VALUES ('business', ?, ?, NOW(), NOW())
         ON DUPLICATE KEY UPDATE prefs_json = VALUES(prefs_json), updated_at = NOW()"
    )->execute([$businessId, $payload]);

    wb_ok(['prefs' => $merged, 'persisted' => true]);
} catch (Throwable $e) {
    error_log('[mobile/business/notification-preferences.php] ' . $e->getMessage());
    wb_err('Bildirim tercihleri işlenemedi', 500, 'internal_error');
}
