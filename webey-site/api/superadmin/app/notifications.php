<?php
declare(strict_types=1);
/**
 * api/superadmin/app/notifications.php
 * GET — Bildirim gözlem listesi (işletme + müşteri bildirimleri birleşik). READ-ONLY.
 * Device token / push token / token_hash hiçbir şekilde SELECT edilmez.
 *
 * Filtreler: target=business|customer, type, unread=1, page, limit
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/_helpers.php';
wb_method('GET');

try {
    $pg     = sa_page_params(25);
    $target = trim((string)($_GET['target'] ?? ''));
    $type   = trim((string)($_GET['type'] ?? ''));
    $unread = (($_GET['unread'] ?? '') === '1');

    $items = [];
    $total = 0;

    if ($target === 'customer') {
        // ── Müşteri bildirimleri (user_notifications) ──
        $where  = [];
        $params = [];
        if ($type !== '' && preg_match('/^[a-z0-9_]{1,40}$/', $type)) {
            $where[] = 'n.type = ?';
            $params[] = $type;
        }
        if ($unread) $where[] = 'n.is_read = 0';
        $whereSql = $where ? ('WHERE ' . implode(' AND ', $where)) : '';

        $total = (int)sa_val($pdo, "SELECT COUNT(*) FROM user_notifications n $whereSql", $params);
        $rows  = sa_rows($pdo, "
            SELECT n.id, n.user_id, n.appointment_id, n.type, n.title, n.message,
                   n.business_name, n.is_read, n.read_at, n.created_at,
                   u.name AS user_name
            FROM user_notifications n
            LEFT JOIN users u ON u.id = n.user_id
            $whereSql
            ORDER BY n.created_at DESC
            LIMIT {$pg['limit']} OFFSET {$pg['offset']}
        ", $params);

        $items = array_map(static fn(array $r): array => [
            'id'             => (int)$r['id'],
            'target_type'    => 'customer',
            'user_id'        => (int)$r['user_id'],
            'user_name'      => $r['user_name'],
            'appointment_id' => $r['appointment_id'] !== null ? (int)$r['appointment_id'] : null,
            'type'           => $r['type'],
            'title'          => $r['title'],
            'body'           => mb_substr((string)($r['message'] ?? ''), 0, 160),
            'business_name'  => $r['business_name'],
            'is_read'        => (bool)$r['is_read'],
            'read_at'        => $r['read_at'],
            'created_at'     => $r['created_at'],
        ], $rows);

    } else {
        // ── İşletme bildirimleri (notifications) — varsayılan ──
        $where  = ['n.is_deleted = 0'];
        $params = [];
        if ($type !== '' && preg_match('/^[a-z0-9_]{1,40}$/', $type)) {
            $where[] = 'n.type = ?';
            $params[] = $type;
        }
        if ($unread) $where[] = 'n.is_read = 0';
        $whereSql = 'WHERE ' . implode(' AND ', $where);

        $total = (int)sa_val($pdo, "SELECT COUNT(*) FROM notifications n $whereSql", $params);
        $rows  = sa_rows($pdo, "
            SELECT n.id, n.business_id, n.appointment_id, n.type,
                   n.customer_name, n.customer_phone, n.service_name, n.staff_name,
                   n.appointment_start, n.result, n.is_read, n.read_at, n.created_at,
                   b.name AS business_name
            FROM notifications n
            LEFT JOIN businesses b ON b.id = n.business_id
            $whereSql
            ORDER BY n.created_at DESC
            LIMIT {$pg['limit']} OFFSET {$pg['offset']}
        ", $params);

        $items = array_map(static fn(array $r): array => [
            'id'                    => (int)$r['id'],
            'target_type'           => 'business',
            'business_id'           => (int)$r['business_id'],
            'business_name'         => $r['business_name'],
            'appointment_id'        => $r['appointment_id'] !== null ? (int)$r['appointment_id'] : null,
            'type'                  => $r['type'],
            'title'                 => $r['type'] . ' / ' . $r['result'],
            'customer_name'         => $r['customer_name'],
            'customer_phone_masked' => sa_mask_phone($r['customer_phone']),
            'service_name'          => $r['service_name'],
            'staff_name'            => $r['staff_name'],
            'appointment_start'     => $r['appointment_start'],
            'result'                => $r['result'],
            'is_read'               => (bool)$r['is_read'],
            'read_at'               => $r['read_at'],
            'created_at'            => $r['created_at'],
        ], $rows);
    }

    // Cihaz token istatistiği — token değerleri ASLA dönmez, sadece sayılar.
    $tokenStats = sa_row($pdo, "
        SELECT COUNT(*) AS total,
               COALESCE(SUM(is_active=1),0) AS active,
               COALESCE(SUM(platform='android'),0) AS android,
               COALESCE(SUM(platform='ios'),0) AS ios
        FROM mobile_device_tokens") ?? [];

    $payload = sa_list_payload($items, $total, $pg);
    $payload['device_token_stats'] = [
        'total'   => (int)($tokenStats['total'] ?? 0),
        'active'  => (int)($tokenStats['active'] ?? 0),
        'android' => (int)($tokenStats['android'] ?? 0),
        'ios'     => (int)($tokenStats['ios'] ?? 0),
    ];

    wb_ok($payload);

} catch (Throwable $e) {
    error_log('[superadmin/app/notifications] ' . $e->getMessage());
    wb_err('Bildirim listesi yüklenemedi', 500, 'internal_error');
}
