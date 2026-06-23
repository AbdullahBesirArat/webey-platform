<?php
declare(strict_types=1);
/**
 * api/mobile/business/service-categories.php
 * GET - Token sahibi isletmenin secebilecegi hizmet kategorileri.
 *
 * Yanit:
 *   system_categories   : sistem (varsayilan) kategoriler
 *   business_categories : isletmeye ozel kategoriler
 *   categories          : birlesik liste (once sistem, sonra ozel)
 *   her kategoride: id, name, slug, icon_key, sort_order, is_system, service_count
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';
require_once __DIR__ . '/_helpers.php';
require_once __DIR__ . '/../_category_helpers.php';

wb_method('GET');

$auth = mobile_auth($pdo, ['business', 'admin']);
$ctx = mobile_business_context($pdo, $auth);
$businessId = (int)$ctx['business_id'];

try {
    if (!mobile_category_table_exists($pdo)) {
        // Migration henuz calismadi: bos liste don, app fallback davranir.
        wb_ok(['system_categories' => [], 'business_categories' => [], 'categories' => []]);
    }

    $all = mobile_fetch_categories_for_business($pdo, $businessId);
    $system = array_values(array_filter($all, static fn(array $c): bool => $c['is_system']));
    $custom = array_values(array_filter($all, static fn(array $c): bool => !$c['is_system']));

    wb_ok([
        'system_categories' => $system,
        'business_categories' => $custom,
        'categories' => array_merge($system, $custom),
    ]);
} catch (Throwable $e) {
    error_log('[mobile/business/service-categories.php] ' . $e->getMessage());
    wb_err('Kategoriler alinamadi', 500, 'internal_error');
}
