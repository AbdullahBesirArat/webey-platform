<?php
declare(strict_types=1);

require_once __DIR__ . '/../_bootstrap.php';
wb_method('POST');

$userId = (int)($user['user_id'] ?? 0);
if (!$userId) {
    wb_err('Oturum bulunamadi', 401, 'unauthenticated');
}

$in = wb_body();
$id = (int)($in['id'] ?? 0);
if ($id <= 0) {
    wb_err('id zorunlu', 400, 'missing_id');
}

try {
    $stmt = $pdo->prepare('UPDATE user_notifications SET is_read = 1, read_at = NOW() WHERE id = ? AND user_id = ?');
    $stmt->execute([$id, $userId]);
    wb_ok(['updated' => (int)$stmt->rowCount()]);
} catch (Throwable $e) {
    error_log('[user/notifications/mark-read] ' . $e->getMessage());
    wb_err('Bildirim guncellenemedi', 500, 'internal_error');
}

