<?php
declare(strict_types=1);
/**
 * api/mobile/customer/notifications.php
 * GET — Token sahibi müşterinin bildirimlerini döner (sayfalı).
 *
 * Query params:
 *   page        : int >= 1  (default: 1)
 *   limit       : int 1-50  (default: 20)
 *   unread_only : bool      (default: false)
 *
 * Faz 4A — Bearer token zorunlu, customer tipi.
 * NOT: mark-read ve mark-all-read Faz 4B'de eklenecek.
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';

wb_method('GET');

$session = mobile_auth($pdo, 'customer');
$userId  = $session['user_id'];

// ── Query parametreleri ───────────────────────────────────────────────────────
$page       = max(1, (int)(mobile_int_param('page', 1) ?? 1));
$limit      = mobile_limit(mobile_param('limit', 20), 20, 50);
$offset     = ($page - 1) * $limit;
$unreadOnly = mobile_bool_param('unread_only', false);

try {
    // ── Toplam kayıt sayısı ───────────────────────────────────────────────────
    if ($unreadOnly) {
        $countSql = "SELECT COUNT(*) FROM user_notifications WHERE user_id = ? AND is_read = 0";
    } else {
        $countSql = "SELECT COUNT(*) FROM user_notifications WHERE user_id = ?";
    }
    $countStmt = $pdo->prepare($countSql);
    $countStmt->execute([$userId]);
    $total = (int)$countStmt->fetchColumn();

    // ── Bildirimler ───────────────────────────────────────────────────────────
    if ($unreadOnly) {
        $mainSql = "
            SELECT id, appointment_id, type, title, message, business_name, is_read, created_at
            FROM user_notifications
            WHERE user_id = ? AND is_read = 0
            ORDER BY id DESC
            LIMIT ? OFFSET ?
        ";
    } else {
        $mainSql = "
            SELECT id, appointment_id, type, title, message, business_name, is_read, created_at
            FROM user_notifications
            WHERE user_id = ?
            ORDER BY id DESC
            LIMIT ? OFFSET ?
        ";
    }
    $mainStmt = $pdo->prepare($mainSql);
    $mainStmt->bindValue(1, $userId, PDO::PARAM_INT);
    $mainStmt->bindValue(2, $limit,  PDO::PARAM_INT);
    $mainStmt->bindValue(3, $offset, PDO::PARAM_INT);
    $mainStmt->execute();

    $items = array_map(static function (array $r): array {
        return [
            'id'         => (string)$r['id'],
            'type'       => (string)($r['type']    ?? 'info'),
            'title'      => (string)($r['title']   ?? ''),
            'body'       => (string)($r['message'] ?? ''),
            'read'       => (bool)($r['is_read']   ?? false),
            'created_at' => (string)($r['created_at'] ?? ''),
            'data'       => [
                'appointment_id' => $r['appointment_id'] !== null ? (string)$r['appointment_id'] : null,
                'business_name'  => $r['business_name'] ?? null,
            ],
        ];
    }, $mainStmt->fetchAll() ?: []);

    // ── Okunmamış bildirim sayısı (her zaman toplam, filtresiz) ──────────────
    $unreadStmt = $pdo->prepare("SELECT COUNT(*) FROM user_notifications WHERE user_id = ? AND is_read = 0");
    $unreadStmt->execute([$userId]);
    $unreadCount = (int)$unreadStmt->fetchColumn();

    wb_ok([
        'items'        => $items,
        'pagination'   => [
            'page'     => $page,
            'limit'    => $limit,
            'total'    => $total,
            'has_more' => ($offset + count($items)) < $total,
        ],
        'unread_count' => $unreadCount,
    ]);

} catch (Throwable $e) {
    error_log('[mobile/customer/notifications.php] ' . $e->getMessage());
    wb_err('Bildirimler alınamadı', 500, 'internal_error');
}
