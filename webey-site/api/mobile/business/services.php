<?php
declare(strict_types=1);
/**
 * api/mobile/business/services.php
 * GET - Token sahibi isletmenin hizmetleri.
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';
require_once __DIR__ . '/_helpers.php';
require_once __DIR__ . '/../_category_helpers.php';

wb_method('GET');

$auth = mobile_auth($pdo, ['business', 'admin']);
$ctx = mobile_business_context($pdo, $auth);
$businessId = (int)$ctx['business_id'];
$includeInactive = mobile_bool_param('include_inactive', false);

try {
    $hasDescription = mobile_business_has_column($pdo, 'services', 'description');
    $hasCategory = mobile_business_has_column($pdo, 'services', 'category');
    $hasActive = mobile_business_has_column($pdo, 'services', 'is_active');
    $hasSort = mobile_business_has_column($pdo, 'services', 'sort_order');
    $hasCategoryId = mobile_business_has_column($pdo, 'services', 'category_id')
        && mobile_category_table_exists($pdo);

    $categoryJoin = $hasCategoryId
        ? 'LEFT JOIN service_categories sc ON sc.id = s.category_id'
        : '';
    $categorySelect = $hasCategoryId
        ? 's.category_id, sc.name AS category_resolved_name, sc.slug AS category_slug, sc.icon_key AS category_icon_key, sc.business_id AS category_owner'
        : 'NULL AS category_id, NULL AS category_resolved_name, NULL AS category_slug, NULL AS category_icon_key, NULL AS category_owner';

    $sql = "
        SELECT
            s.id,
            s.name,
            s.price,
            s.duration_min,
            " . ($hasDescription ? 's.description' : 'NULL') . " AS description,
            " . ($hasCategory ? 's.category' : 'NULL') . " AS category,
            " . ($hasActive ? 's.is_active' : '1') . " AS is_active,
            " . ($hasSort ? 's.sort_order' : '0') . " AS sort_order,
            $categorySelect
        FROM services s
        $categoryJoin
        WHERE s.business_id = ?
    ";
    $params = [$businessId];
    if ($hasActive && !$includeInactive) {
        $sql .= ' AND s.is_active = 1';
    }
    $sql .= $hasSort ? ' ORDER BY s.sort_order ASC, s.name ASC' : ' ORDER BY s.name ASC';

    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);
    $items = array_map('mobile_business_service_item', $stmt->fetchAll());

    wb_ok(['items' => $items]);
} catch (Throwable $e) {
    error_log('[mobile/business/services.php] ' . $e->getMessage());
    wb_err('Hizmetler alinamadi', 500, 'internal_error');
}
