<?php
declare(strict_types=1);
/**
 * api/superadmin/app/customers.php
 * GET — Müşteri listesi (maskeli). READ-ONLY.
 * birthday, token vb. hassas alanlar SELECT edilmez.
 *
 * Filtreler: q, city, district, has_location=1, page, limit
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/_helpers.php';
wb_method('GET');

try {
    $pg     = sa_page_params(25);
    $where  = ["u.role = 'user'"];
    $params = [];

    $q = trim((string)($_GET['q'] ?? ''));
    if ($q !== '') {
        $where[] = '(u.name LIKE ? OR c.first_name LIKE ? OR c.last_name LIKE ? OR c.city LIKE ?)';
        $like    = sa_like($q);
        array_push($params, $like, $like, $like, $like);
    }

    $city = trim((string)($_GET['city'] ?? ''));
    if ($city !== '') { $where[] = 'c.city LIKE ?'; $params[] = sa_like($city); }

    $district = trim((string)($_GET['district'] ?? ''));
    if ($district !== '') { $where[] = 'c.district LIKE ?'; $params[] = sa_like($district); }

    if (($_GET['has_location'] ?? '') === '1') {
        $where[] = "(c.city IS NOT NULL AND c.city <> '')";
    }

    $whereSql = 'WHERE ' . implode(' AND ', $where);
    $joinSql  = 'FROM users u LEFT JOIN customers c ON c.user_id = u.id';

    $total = (int)sa_val($pdo, "SELECT COUNT(*) $joinSql $whereSql", $params);

    $rows = sa_rows($pdo, "
        SELECT
            u.id AS user_id, c.id AS customer_id,
            u.name AS user_name, c.first_name, c.last_name,
            c.phone, u.email, c.city, c.district, c.neighborhood,
            u.created_at, u.last_login_at, c.updated_at,
            (SELECT COUNT(*) FROM appointments a WHERE a.customer_user_id = u.id)   AS appointment_count,
            (SELECT COUNT(*) FROM customer_favorites f WHERE f.customer_user_id = u.id) AS favorite_count,
            (SELECT COUNT(*) FROM user_notifications n WHERE n.user_id = u.id)      AS notification_count
        $joinSql
        $whereSql
        ORDER BY u.created_at DESC
        LIMIT {$pg['limit']} OFFSET {$pg['offset']}
    ", $params);

    $items = array_map(static function (array $r): array {
        $name = trim((string)($r['first_name'] ?? '') . ' ' . (string)($r['last_name'] ?? ''));
        if ($name === '') $name = (string)($r['user_name'] ?? '');
        return [
            'id'                 => $r['customer_id'] !== null ? (int)$r['customer_id'] : null,
            'user_id'            => (int)$r['user_id'],
            'name'               => $name,
            'phone_masked'       => sa_mask_phone($r['phone']),
            'email_masked'       => sa_mask_email($r['email']),
            'city'               => $r['city'],
            'district'           => $r['district'],
            'neighborhood'       => $r['neighborhood'],
            'appointment_count'  => (int)$r['appointment_count'],
            'favorite_count'     => (int)$r['favorite_count'],
            'notification_count' => (int)$r['notification_count'],
            'created_at'         => $r['created_at'],
            'last_login_at'      => $r['last_login_at'],
            'updated_at'         => $r['updated_at'],
        ];
    }, $rows);

    wb_ok(sa_list_payload($items, $total, $pg));

} catch (Throwable $e) {
    error_log('[superadmin/app/customers] ' . $e->getMessage());
    wb_err('Müşteri listesi yüklenemedi', 500, 'internal_error');
}
