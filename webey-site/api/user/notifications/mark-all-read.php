<?php
declare(strict_types=1);

require_once __DIR__ . '/../_bootstrap.php';
wb_method('POST');

$userId = (int)($user['user_id'] ?? 0);
if (!$userId) {
    wb_err('Oturum bulunamadi', 401, 'unauthenticated');
}

try {
    $stmt = $pdo->prepare('UPDATE user_notifications SET is_read = 1, read_at = NOW() WHERE user_id = ? AND is_read = 0');
    $stmt->execute([$userId]);
    wb_ok(['updated' => (int)$stmt->rowCount()]);
} catch (Throwable $e) {
    error_log('[user/notifications/mark-all-read] ' . $e->getMessage());
    wb_err('Bildirimler guncellenemedi', 500, 'internal_error');
}

