<?php
declare(strict_types=1);
/**
 * api/superadmin/app/subscriptions.php
 * GET — İşletme abonelikleri listesi. READ-ONLY (Faz 1).
 *
 * Tüm işletmeler LEFT JOIN ile gelir; abonelik kaydı olmayan işletme
 * status='unknown' (Tanımlanmadı) döner.
 * Eski web/iyzico `subscriptions` tablosuna BAKMAZ.
 *
 * Filtreler: q, status, due=overdue, trial_ending=1, page, limit
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/_helpers.php';
require_once __DIR__ . '/../../mobile/_business_visibility.php';
wb_method('GET');

try {
    $pg = sa_page_params(25);

    $hasSubs  = (bool)sa_val($pdo,
        "SELECT COUNT(*) FROM information_schema.tables
         WHERE table_schema = DATABASE() AND table_name = 'business_subscriptions'");
    $hasPlans = (bool)sa_val($pdo,
        "SELECT COUNT(*) FROM information_schema.tables
         WHERE table_schema = DATABASE() AND table_name = 'business_subscription_plans'");

    $where  = [];
    $params = [];

    $q = trim((string)($_GET['q'] ?? ''));
    if ($q !== '') {
        $where[] = '(b.name LIKE ? OR b.owner_name LIKE ?)';
        $like = sa_like($q);
        array_push($params, $like, $like);
    }

    if ($hasSubs) {
        $status = trim((string)($_GET['status'] ?? ''));
        if (in_array($status, ['trial', 'active', 'overdue', 'suspended', 'cancelled'], true)) {
            $where[]  = 's.status = ?';
            $params[] = $status;
        }
        if (($_GET['due'] ?? '') === 'overdue') {
            $where[] = '(s.next_payment_due_at IS NOT NULL AND s.next_payment_due_at < NOW())';
        }
        if (($_GET['trial_ending'] ?? '') === '1') {
            $where[] = "(s.status = 'trial' AND s.trial_ends_at IS NOT NULL
                         AND s.trial_ends_at >= NOW()
                         AND s.trial_ends_at < DATE_ADD(NOW(), INTERVAL 7 DAY))";
        }
    }

    $whereSql = $where ? ('WHERE ' . implode(' AND ', $where)) : '';

    if ($hasSubs) {
        // Her işletme için en güncel abonelik satırı (id DESC).
        $joinLatest = "LEFT JOIN business_subscriptions s
            ON s.id = (SELECT s2.id FROM business_subscriptions s2
                       WHERE s2.business_id = b.id ORDER BY s2.id DESC LIMIT 1)";
        $joinPlan    = $hasPlans ? 'LEFT JOIN business_subscription_plans p ON p.id = s.plan_id' : '';
        $planNameSel = $hasPlans ? 'p.name AS plan_name,' : 'NULL AS plan_name,';
        $visibilityJoin = wb_business_visibility_join_sql($pdo);
        $visibilitySelect = wb_business_visibility_select_sql($pdo);

        $total = (int)sa_val($pdo,
            "SELECT COUNT(*) FROM businesses b $joinLatest $joinPlan $visibilityJoin $whereSql", $params);

        $rows = sa_rows($pdo, "
            SELECT b.id AS business_id, b.name AS business_name, b.owner_name,
                   b.phone AS owner_phone,
                   $planNameSel
                   s.status, s.monthly_price, s.trial_ends_at, s.current_period_end,
                   s.next_payment_due_at, s.last_payment_at, s.payment_method,
                   s.notes, COALESCE(s.updated_at, b.updated_at) AS row_updated_at,
                   b.created_at
                   $visibilitySelect
            FROM businesses b
            $joinLatest
            $joinPlan
            $visibilityJoin
            $whereSql
            ORDER BY (s.status IS NULL), s.updated_at DESC, b.id DESC
            LIMIT {$pg['limit']} OFFSET {$pg['offset']}
        ", $params);
    } else {
        // Tablolar henüz migrate edilmemiş → işletmeler "Tanımlanmadı".
        $total = (int)sa_val($pdo, "SELECT COUNT(*) FROM businesses b $whereSql", $params);
        $rows = sa_rows($pdo, "
            SELECT b.id AS business_id, b.name AS business_name, b.owner_name,
                   b.phone AS owner_phone,
                   NULL AS plan_name, NULL AS status, NULL AS monthly_price,
                   NULL AS trial_ends_at, NULL AS current_period_end,
                   NULL AS next_payment_due_at, NULL AS last_payment_at,
                   NULL AS payment_method, NULL AS notes, b.updated_at AS row_updated_at,
                   b.created_at,
                   'unknown' AS subscription_status,
                   'temporary_visible' AS visibility_status,
                   0 AS is_boosted,
                   NULL AS boost_badge,
                   NULL AS boost_ends_at,
                   0 AS profile_quality_score
            FROM businesses b
            $whereSql
            ORDER BY b.id DESC
            LIMIT {$pg['limit']} OFFSET {$pg['offset']}
        ", $params);
    }

    $items = array_map(static function (array $r): array {
        $status = $r['status'] !== null ? (string)$r['status'] : 'unknown';
        $notes  = $r['notes'] !== null ? (string)$r['notes'] : null;
        $visibility = wb_business_visibility_from_row($r);
        return [
            'business_id'         => (int)$r['business_id'],
            'business_name'       => $r['business_name'],
            'owner_name'          => $r['owner_name'],
            'owner_phone_masked'  => sa_mask_phone($r['owner_phone']),
            'plan_name'           => $r['plan_name'] ?? null,
            'status'              => $status,
            'monthly_price'       => $r['monthly_price'] !== null ? (float)$r['monthly_price'] : null,
            'trial_ends_at'       => $r['trial_ends_at'],
            'current_period_end'  => $r['current_period_end'],
            'next_payment_due_at' => $r['next_payment_due_at'],
            'last_payment_at'     => $r['last_payment_at'],
            'payment_method'      => $r['payment_method'],
            'visibility_status'   => $visibility['visibility_status'],
            'customer_visible'     => $visibility['visibility_status'] !== 'hidden',
            'is_boosted'           => $visibility['is_boosted'],
            'boost_badge'          => $visibility['boost_badge'],
            'boost_ends_at'        => $visibility['boost_ends_at'],
            'profile_quality_score'=> $visibility['profile_quality_score'],
            'notes_short'         => $notes !== null ? mb_substr($notes, 0, 80) : null,
            'updated_at'          => $r['row_updated_at'],
            'created_at'          => $r['created_at'],
        ];
    }, $rows);

    wb_ok(sa_list_payload($items, $total, $pg));
} catch (Throwable $e) {
    error_log('[superadmin/app/subscriptions] ' . $e->getMessage());
    wb_err('Abonelik listesi yüklenemedi', 500, 'internal_error');
}
