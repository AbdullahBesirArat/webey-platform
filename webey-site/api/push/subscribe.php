<?php
// api/push/subscribe.php — Web Push Subscription kaydet / sil
// POST { action: 'subscribe'|'unsubscribe', endpoint, p256dh, auth }
declare(strict_types=1);
// FIX: '/../../api/_bootstrap.php' kafa karıştırıcı ama aslında doğru hedefe gidiyordu.
// Daha okunabilir: api/push/ → ../ → api/ → _bootstrap.php
// Admin ve user her ikisi de bu endpoint'i kullanır; genel _bootstrap.php her ikisini kabul eder.
require_once __DIR__ . '/../_bootstrap.php';

wb_method('POST');

$userId = $user['user_id'];
$body   = wb_body();
$action = trim($body['action'] ?? 'subscribe');

if ($action === 'unsubscribe') {
    $endpoint = trim($body['endpoint'] ?? '');
    if (!$endpoint) wb_err('endpoint zorunlu', 400);
    $pdo->prepare("DELETE FROM push_subscriptions WHERE user_id = ? AND endpoint = ?")
        ->execute([(int)$userId, $endpoint]);
    wb_ok(['message' => 'Bildirimler kapatıldı']);
}

// Subscribe
wb_validate($body, [
    'endpoint' => ['required', 'max:2000'],
    'p256dh'   => ['required', 'max:255'],
    'auth'     => ['required', 'max:255'],
]);

$endpoint = trim($body['endpoint']);
$p256dh   = trim($body['p256dh']);
$auth     = trim($body['auth']);
$ua       = substr($_SERVER['HTTP_USER_AGENT'] ?? '', 0, 300);

try {
    $pdo->prepare("
        INSERT INTO push_subscriptions (user_id, endpoint, p256dh, auth, user_agent, created_at, last_used_at)
        VALUES (?, ?, ?, ?, ?, NOW(), NOW())
        ON DUPLICATE KEY UPDATE
            p256dh       = VALUES(p256dh),
            auth         = VALUES(auth),
            last_used_at = NOW()
    ")->execute([(int)$userId, $endpoint, $p256dh, $auth, $ua]);

    wb_ok(['message' => 'Bildirimler etkinleştirildi', 'subscribed' => true]);

} catch (Throwable $e) {
    error_log('[push/subscribe] ' . $e->getMessage());
    wb_err('Subscription kaydedilemedi', 500);
}