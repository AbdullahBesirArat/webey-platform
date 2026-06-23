<?php
// api/_push.php
// ─────────────────────────────────────────────────────────────────────
// Web Push Bildirim Yardımcısı
//
// Kullanım:
//   require_once __DIR__ . '/_push.php';
//
//   // Belirli bir kullanıcıya gönder
//   sendPushToUser($pdo, $userId, 'Yeni Randevu', 'Abdullah Arat randevu aldı', '/calendar.html');
//
//   // Bir işletme sahibine gönder
//   sendPushToBusiness($pdo, $businessId, 'Başlık', 'Mesaj', '/calendar.html');
//
// KURULUM (VAPID anahtarları üretmek için):
//   composer require web-push/web-push
//   vendor/bin/vapid-generate-keys
//   → Üretilen public/private key'leri _push_config.php'ye gir
// ─────────────────────────────────────────────────────────────────────
declare(strict_types=1);

// ── Config ───────────────────────────────────────────────────────────

function _pushConfig(): array {
    static $cfg = null;
    if ($cfg !== null) return $cfg;
    $cfg = [
        // VAPID anahtarları — composer ile üretilir, bir kez yapılır
        // https://web.dev/push-notifications-web-push-protocol/#vapid
        'vapid_subject'     => 'mailto:info@webey.com.tr',
        'vapid_public_key'  => 'BURAYA_PUBLIC_KEY',   // ← openssl ile üret
        'vapid_private_key' => 'BURAYA_PRIVATE_KEY',  // ← openssl ile üret

        // debug=true → push gönderme, sadece logla
        'debug' => true,
    ];
    return $cfg;
}

// ── Kullanıcıya Push Gönder ──────────────────────────────────────────

/**
 * Belirli bir kullanıcının tüm cihazlarına push bildirimi gönderir.
 */
function sendPushToUser(
    PDO    $pdo,
    int    $userId,
    string $title,
    string $body,
    string $url = '/',
    string $tag = 'webey'
): void {
    $subs = _getUserSubscriptions($pdo, $userId);
    foreach ($subs as $sub) {
        _sendPushToSubscription($sub, $title, $body, $url, $tag);
    }
}

/**
 * Bir işletme sahibinin tüm cihazlarına push bildirimi gönderir.
 */
function sendPushToBusiness(
    PDO    $pdo,
    int    $businessId,
    string $title,
    string $body,
    string $url = '/calendar.html',
    string $tag = 'webey-appt'
): void {
    try {
        $stmt = $pdo->prepare("SELECT owner_id FROM businesses WHERE id=? LIMIT 1");
        $stmt->execute([$businessId]);
        $ownerId = $stmt->fetchColumn();
        if ($ownerId) {
            sendPushToUser($pdo, (int)$ownerId, $title, $body, $url, $tag);
        }
    } catch (Throwable $e) {
        error_log('[sendPushToBusiness] ' . $e->getMessage());
    }
}

// ── İç Yardımcılar ───────────────────────────────────────────────────

function _getUserSubscriptions(PDO $pdo, int $userId): array {
    try {
        $stmt = $pdo->prepare("SELECT endpoint, p256dh, auth FROM push_subscriptions WHERE user_id=?");
        $stmt->execute([$userId]);
        return $stmt->fetchAll(PDO::FETCH_ASSOC);
    } catch (Throwable) {
        return [];
    }
}

function _sendPushToSubscription(array $sub, string $title, string $body, string $url, string $tag): bool {
    $cfg = _pushConfig();

    $payload = json_encode([
        'title' => $title,
        'body'  => $body,
        'url'   => $url,
        'tag'   => $tag,
        'icon'  => '/img/icon-192.png',
        'badge' => '/img/icon-192.png',
    ]);

    if ($cfg['debug']) {
        error_log('[Push DEBUG] To: ' . substr($sub['endpoint'], -30) . ' | ' . $title . ' | ' . $body);
        return true;
    }

    // ── VAPID ile Web Push ────────────────────────────────────────────
    // web-push/web-push kütüphanesi gerektirir (composer)
    $vendorPath = __DIR__ . '/../../vendor/autoload.php';
    if (!file_exists($vendorPath)) {
        error_log('[Push] vendor/autoload.php bulunamadı. "composer require web-push/web-push" çalıştırın.');
        return false;
    }

    require_once $vendorPath;

    try {
        $auth = [
            'VAPID' => [
                'subject'    => $cfg['vapid_subject'],
                'publicKey'  => $cfg['vapid_public_key'],
                'privateKey' => $cfg['vapid_private_key'],
            ],
        ];

        $webPush = new Minishlink\WebPush\WebPush($auth);

        $subscription = Minishlink\WebPush\Subscription::create([
            'endpoint' => $sub['endpoint'],
            'keys'     => [
                'p256dh' => $sub['p256dh'],
                'auth'   => $sub['auth'],
            ],
        ]);

        $notification = Minishlink\WebPush\Notification::create()
            ->withPayload($payload)
            ->withContentEncoding('aesgcm');

        $report = $webPush->sendOneNotification($subscription, $notification);

        if (!$report->isSuccess()) {
            error_log('[Push] Gönderim başarısız: ' . $report->getReason());
            return false;
        }
        return true;

    } catch (Throwable $e) {
        error_log('[Push] ' . $e->getMessage());
        return false;
    }
}

// ── VAPID Key Üretim Rehberi (bu dosyayı çalıştırma, sadece oku) ────
//
// Terminal'de çalıştır:
//
//   cd /var/www/html
//   composer require web-push/web-push
//
// Sonra PHP ile key üret:
//   php -r "
//     \$keys = \Minishlink\WebPush\VAPID::createVapidKeys();
//     echo 'Public:  ' . \$keys['publicKey'] . PHP_EOL;
//     echo 'Private: ' . \$keys['privateKey'] . PHP_EOL;
//   "
//
// Çıkan değerleri _push.php'deki vapid_public_key / vapid_private_key'e gir.
// Service Worker'daki applicationServerKey'i de public key ile güncelle.