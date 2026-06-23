<?php
declare(strict_types=1);
/**
 * api/mobile/business/notifications.php
 * GET — Token sahibi işletmenin bildirimlerini döner (sayfalı).
 *
 * Query params:
 *   page        : int >= 1  (default: 1)
 *   limit       : int 1-50  (default: 20)
 *   unread_only : bool      (default: false)
 *
 * Bildirimler `notifications` tablosundan okunur (booking / cancellation / sub*).
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';
require_once __DIR__ . '/_helpers.php';

wb_method('GET');

$auth = mobile_auth($pdo, ['business', 'admin']);
$ctx = mobile_business_context($pdo, $auth);
$businessId = (int)$ctx['business_id'];

$page = max(1, mobile_int_param('page', 1) ?? 1);
$limit = mobile_limit(mobile_param('limit', 20), 20, 50);
$offset = ($page - 1) * $limit;
$unreadOnly = mobile_bool_param('unread_only', false);

try {
    $where = 'business_id = ? AND is_deleted = 0';
    $params = [$businessId];
    if ($unreadOnly) {
        $where .= ' AND is_read = 0';
    }

    $countStmt = $pdo->prepare("SELECT COUNT(*) FROM notifications WHERE $where");
    $countStmt->execute($params);
    $total = (int)$countStmt->fetchColumn();

    $mainStmt = $pdo->prepare("
        SELECT id, appointment_id, type, customer_name, customer_phone,
               service_name, staff_name, appointment_start, result,
               is_read, created_at
        FROM notifications
        WHERE $where
        ORDER BY id DESC
        LIMIT ? OFFSET ?
    ");
    $bindIdx = 1;
    foreach ($params as $param) {
        $mainStmt->bindValue($bindIdx++, $param, PDO::PARAM_INT);
    }
    $mainStmt->bindValue($bindIdx++, $limit, PDO::PARAM_INT);
    $mainStmt->bindValue($bindIdx++, $offset, PDO::PARAM_INT);
    $mainStmt->execute();

    $items = array_map(static function (array $r): array {
        $type = (string)($r['type'] ?? 'booking');
        $custName = (string)($r['customer_name'] ?? '');
        $svc = (string)($r['service_name'] ?? '');
        $start = (string)($r['appointment_start'] ?? '');
        $title = match ($type) {
            'cancellation' => 'İptal talebi',
            'review' => 'Yeni yorum',
            'deposit_sent' => 'IBAN ödeme bildirimi',
            'subscription_expiry_3d',
            'subscription_expiry_1d',
            'subscription_expired' => 'Abonelik uyarısı',
            default => 'Yeni randevu',
        };
        $body = '';
        if ($custName !== '') {
            $body .= $custName;
        }
        if ($svc !== '') {
            $body .= ($body !== '' ? ' · ' : '') . $svc;
        }
        if ($start !== '') {
            try {
                $dt = new DateTimeImmutable($start, new DateTimeZone('Europe/Istanbul'));
                $body .= ($body !== '' ? ' · ' : '') . $dt->format('d.m.Y H:i');
            } catch (Throwable) {
                $body .= ($body !== '' ? ' · ' : '') . $start;
            }
        }
        return [
            'id'         => (string)$r['id'],
            'type'       => $type,
            'title'      => $title,
            'body'       => $body,
            'read'       => (bool)($r['is_read'] ?? false),
            'created_at' => (string)($r['created_at'] ?? ''),
            'data'       => [
                'appointment_id' => $r['appointment_id'] !== null ? (string)$r['appointment_id'] : null,
                'result'         => (string)($r['result'] ?? ''),
                'customer_name'  => $custName ?: null,
                'customer_phone' => $r['customer_phone'] ?? null,
                'service_name'   => $svc ?: null,
                'staff_name'     => $r['staff_name'] ?? null,
                'appointment_start' => $start ?: null,
            ],
        ];
    }, $mainStmt->fetchAll() ?: []);

    $unreadStmt = $pdo->prepare("SELECT COUNT(*) FROM notifications WHERE business_id = ? AND is_deleted = 0 AND is_read = 0");
    $unreadStmt->execute([$businessId]);
    $unreadCount = (int)$unreadStmt->fetchColumn();

    wb_ok([
        'items' => $items,
        'pagination' => [
            'page' => $page,
            'limit' => $limit,
            'total' => $total,
            'has_more' => ($offset + count($items)) < $total,
        ],
        'unread_count' => $unreadCount,
    ]);
} catch (Throwable $e) {
    error_log('[mobile/business/notifications.php] ' . $e->getMessage());
    wb_err('Bildirimler alınamadı', 500, 'internal_error');
}
