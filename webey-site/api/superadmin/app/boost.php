<?php
declare(strict_types=1);
/**
 * api/superadmin/app/boost.php
 * GET — Boost paketleri, talepleri ve abonelikleri. READ-ONLY.
 *
 * Filtreler: view=requests|subscriptions (liste modu), status, page, limit
 * Parametresiz: özet (paketler + bekleyen talepler + aktif/süresi dolmuş özetleri)
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/_helpers.php';
require_once __DIR__ . '/../../mobile/_business_visibility.php';
wb_method('GET');

try {
    $view = trim((string)($_GET['view'] ?? ''));
    $visibilityJoin = wb_business_visibility_join_sql($pdo);
    $visibilitySelect = wb_business_visibility_select_sql($pdo);

    if ($view === 'requests' || $view === 'subscriptions') {
        $pg     = sa_page_params(25);
        $where  = [];
        $params = [];

        $status = trim((string)($_GET['status'] ?? ''));
        if ($status !== '' && preg_match('/^[a-z_]{1,20}$/', $status)) {
            $where[] = 'x.status = ?';
            $params[] = $status;
        }
        $whereSql = $where ? ('WHERE ' . implode(' AND ', $where)) : '';

        if ($view === 'requests') {
            $total = (int)sa_val($pdo, "SELECT COUNT(*) FROM business_boost_requests x $whereSql", $params);
            $rows  = sa_rows($pdo, "
                SELECT x.id, x.business_id, b.name AS business_name,
                       bp.name AS package_name, bp.price AS package_price,
                       x.status, x.note, x.created_at, x.updated_at
                       $visibilitySelect
                FROM business_boost_requests x
                JOIN businesses b ON b.id = x.business_id
                JOIN boost_packages bp ON bp.id = x.package_id
                $visibilityJoin
                $whereSql
                ORDER BY x.created_at DESC
                LIMIT {$pg['limit']} OFFSET {$pg['offset']}
            ", $params);
        } else {
            $total = (int)sa_val($pdo, "SELECT COUNT(*) FROM business_boost_subscriptions x $whereSql", $params);
            $rows  = sa_rows($pdo, "
                SELECT x.id, x.business_id, b.name AS business_name,
                       bp.name AS package_name, x.status, x.payment_status,
                       x.starts_at, x.ends_at, x.paid_amount, x.created_at,
                       (x.status='active' AND (x.ends_at IS NULL OR x.ends_at >= NOW())) AS is_live
                       $visibilitySelect
                FROM business_boost_subscriptions x
                JOIN businesses b ON b.id = x.business_id
                JOIN boost_packages bp ON bp.id = x.package_id
                $visibilityJoin
                $whereSql
                ORDER BY x.created_at DESC
                LIMIT {$pg['limit']} OFFSET {$pg['offset']}
            ", $params);
            foreach ($rows as &$r) {
                $r['is_live'] = (bool)$r['is_live'];
                $visibility = wb_business_visibility_from_row($r);
                $r['subscription_status'] = $visibility['subscription_status'];
                $r['visibility_status'] = $visibility['visibility_status'];
                $r['customer_visible'] = $visibility['visibility_status'] !== 'hidden';
                $r['is_boosted'] = $visibility['is_boosted'];
                $r['boost_ends_at'] = $visibility['boost_ends_at'];
            }
            unset($r);
        }

        if ($view === 'requests') {
            foreach ($rows as &$r) {
                $visibility = wb_business_visibility_from_row($r);
                $r['subscription_status'] = $visibility['subscription_status'];
                $r['visibility_status'] = $visibility['visibility_status'];
                $r['customer_visible'] = $visibility['visibility_status'] !== 'hidden';
                $r['is_boosted'] = $visibility['is_boosted'];
                $r['boost_ends_at'] = $visibility['boost_ends_at'];
            }
            unset($r);
        }

        wb_ok(sa_list_payload($rows, $total, $pg));
    }

    // ── Özet modu ──
    $packages = sa_rows($pdo, "
        SELECT id, name, description, price, duration_days, priority_weight,
               is_active, sort_order,
               (SELECT COUNT(*) FROM business_boost_subscriptions s
                 WHERE s.package_id = boost_packages.id AND s.status='active'
                   AND (s.ends_at IS NULL OR s.ends_at >= NOW()))                AS active_subscription_count,
               (SELECT COUNT(*) FROM business_boost_requests r
                 WHERE r.package_id = boost_packages.id AND r.status='pending')  AS pending_request_count
        FROM boost_packages
        ORDER BY sort_order, id");

    $pendingRequests = sa_rows($pdo, "
        SELECT x.id, b.name AS business_name, bp.name AS package_name,
               x.status, x.note, x.created_at
               $visibilitySelect
        FROM business_boost_requests x
        JOIN businesses b ON b.id = x.business_id
        JOIN boost_packages bp ON bp.id = x.package_id
        $visibilityJoin
        WHERE x.status = 'pending'
        ORDER BY x.created_at DESC
        LIMIT 50");

    $activeSubs = sa_rows($pdo, "
        SELECT x.id, b.name AS business_name, bp.name AS package_name,
               x.status, x.payment_status, x.starts_at, x.ends_at,
               x.paid_amount, x.created_at
               $visibilitySelect
        FROM business_boost_subscriptions x
        JOIN businesses b ON b.id = x.business_id
        JOIN boost_packages bp ON bp.id = x.package_id
        $visibilityJoin
        WHERE x.status = 'active' AND (x.ends_at IS NULL OR x.ends_at >= NOW())
        ORDER BY x.ends_at ASC
        LIMIT 50");

    $expiredSubs = sa_rows($pdo, "
        SELECT x.id, b.name AS business_name, bp.name AS package_name,
               x.status, x.payment_status, x.starts_at, x.ends_at,
               x.paid_amount, x.created_at
               $visibilitySelect
        FROM business_boost_subscriptions x
        JOIN businesses b ON b.id = x.business_id
        JOIN boost_packages bp ON bp.id = x.package_id
        $visibilityJoin
        WHERE x.status <> 'active' OR (x.ends_at IS NOT NULL AND x.ends_at < NOW())
        ORDER BY x.ends_at DESC
        LIMIT 50");

    $attachVisibility = static function (array $rows): array {
        foreach ($rows as &$r) {
            $visibility = wb_business_visibility_from_row($r);
            $r['subscription_status'] = $visibility['subscription_status'];
            $r['visibility_status'] = $visibility['visibility_status'];
            $r['customer_visible'] = $visibility['visibility_status'] !== 'hidden';
            $r['is_boosted'] = $visibility['is_boosted'];
            $r['boost_ends_at'] = $visibility['boost_ends_at'];
        }
        unset($r);
        return $rows;
    };
    $pendingRequests = $attachVisibility($pendingRequests);
    $activeSubs = $attachVisibility($activeSubs);
    $expiredSubs = $attachVisibility($expiredSubs);

    wb_ok([
        'packages'             => $packages,
        'pending_requests'     => $pendingRequests,
        'active_subscriptions' => $activeSubs,
        'expired_subscriptions'=> $expiredSubs,
    ]);

} catch (Throwable $e) {
    error_log('[superadmin/app/boost] ' . $e->getMessage());
    wb_err('Boost verileri yüklenemedi', 500, 'internal_error');
}
