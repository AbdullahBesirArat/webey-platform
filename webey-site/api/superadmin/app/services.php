<?php
declare(strict_types=1);
/**
 * api/superadmin/app/services.php
 * GET — Hizmet / kategori dağılımı. READ-ONLY.
 *
 * Filtreler: uncategorized=1 (kategorisiz hizmet listesi), business_id, page, limit
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/_helpers.php';
wb_method('GET');

try {
    // ── Kategorisiz hizmet listesi modu ──
    if (($_GET['uncategorized'] ?? '') === '1') {
        $pg     = sa_page_params(25);
        $where  = ['s.category_id IS NULL'];
        $params = [];

        $businessId = (int)($_GET['business_id'] ?? 0);
        if ($businessId > 0) { $where[] = 's.business_id = ?'; $params[] = $businessId; }

        $whereSql = 'WHERE ' . implode(' AND ', $where);
        $total = (int)sa_val($pdo, "SELECT COUNT(*) FROM services s $whereSql", $params);
        $rows  = sa_rows($pdo, "
            SELECT s.id, s.name, s.price, s.duration_min, s.is_active,
                   s.category AS category_text,
                   s.business_id, b.name AS business_name
            FROM services s
            JOIN businesses b ON b.id = s.business_id
            $whereSql
            ORDER BY s.business_id, s.name
            LIMIT {$pg['limit']} OFFSET {$pg['offset']}
        ", $params);

        wb_ok(sa_list_payload($rows, $total, $pg));
    }

    // ── Özet modu ──
    $systemCategories = sa_rows($pdo, "
        SELECT sc.id, sc.name, sc.slug, sc.is_active, sc.sort_order,
               (SELECT COUNT(*) FROM services s WHERE s.category_id = sc.id)             AS service_count,
               (SELECT COUNT(*) FROM business_categories bc WHERE bc.category_id = sc.id) AS business_count
        FROM service_categories sc
        WHERE sc.business_id = 0
        ORDER BY sc.sort_order");

    $customCategories = sa_rows($pdo, "
        SELECT sc.id, sc.name, sc.slug, sc.business_id, b.name AS business_name,
               (SELECT COUNT(*) FROM services s WHERE s.category_id = sc.id) AS service_count
        FROM service_categories sc
        JOIN businesses b ON b.id = sc.business_id
        WHERE sc.business_id > 0
        ORDER BY b.name, sc.sort_order
        LIMIT 200");

    $uncategorizedCount = (int)sa_val($pdo,
        "SELECT COUNT(*) FROM services WHERE category_id IS NULL");

    $businessesWithoutServices = sa_rows($pdo, "
        SELECT b.id, b.name, b.status, b.onboarding_completed
        FROM businesses b
        WHERE NOT EXISTS (SELECT 1 FROM services s WHERE s.business_id = b.id)
        ORDER BY b.created_at DESC
        LIMIT 100");
    foreach ($businessesWithoutServices as &$bw) {
        $bw['onboarding_completed'] = (bool)$bw['onboarding_completed'];
    }
    unset($bw);

    $topServices = sa_rows($pdo, "
        SELECT s.name, COUNT(*) AS business_count, AVG(s.price) AS avg_price
        FROM services s
        GROUP BY s.name
        ORDER BY business_count DESC, s.name
        LIMIT 20");

    wb_ok([
        'system_categories'           => $systemCategories,
        'business_custom_categories'  => $customCategories,
        'uncategorized_services_count'=> $uncategorizedCount,
        'businesses_without_services' => $businessesWithoutServices,
        'top_services'                => $topServices,
    ]);

} catch (Throwable $e) {
    error_log('[superadmin/app/services] ' . $e->getMessage());
    wb_err('Hizmet/kategori raporu yüklenemedi', 500, 'internal_error');
}
