<?php
declare(strict_types=1);

require_once __DIR__ . '/../_bootstrap.php';
wb_method('GET');

$userId = (int)($user['user_id'] ?? 0);
if (!$userId) {
    wb_err('Oturum bulunamadi', 401, 'unauthenticated');
}

$limit  = max(1, min(100, (int)($_GET['limit'] ?? 30)));
$offset = max(0, (int)($_GET['offset'] ?? 0));

try {
    $stmt = $pdo->prepare(
        'SELECT id, appointment_id, type, title, message, business_name, is_read, read_at, created_at
         FROM user_notifications
         WHERE user_id = ?
         ORDER BY id DESC
         LIMIT ? OFFSET ?'
    );
    $stmt->bindValue(1, $userId, PDO::PARAM_INT);
    $stmt->bindValue(2, $limit, PDO::PARAM_INT);
    $stmt->bindValue(3, $offset, PDO::PARAM_INT);
    $stmt->execute();

    $items = array_map(static function (array $r): array {
        return [
            'id'            => (string)$r['id'],
            'appointmentId' => $r['appointment_id'] !== null ? (string)$r['appointment_id'] : null,
            'type'          => (string)($r['type'] ?? 'info'),
            'title'         => (string)($r['title'] ?? ''),
            'message'       => (string)($r['message'] ?? ''),
            'businessName'  => (string)($r['business_name'] ?? ''),
            'isRead'        => (bool)($r['is_read'] ?? false),
            'readAt'        => $r['read_at'] ?? null,
            'createdAt'     => $r['created_at'] ?? null,
        ];
    }, $stmt->fetchAll() ?: []);

    $uStmt = $pdo->prepare('SELECT COUNT(*) FROM user_notifications WHERE user_id = ? AND is_read = 0');
    $uStmt->execute([$userId]);
    $unread = (int)$uStmt->fetchColumn();

    wb_ok([
        'items' => $items,
        'notifications' => $items,
        'unread' => $unread,
        'unreadCount' => $unread,
    ]);
} catch (Throwable $e) {
    error_log('[user/notifications/list] ' . $e->getMessage());
    wb_err('Bildirimler alinamadi', 500, 'internal_error');
}

