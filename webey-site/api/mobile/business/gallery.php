<?php
declare(strict_types=1);

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';
require_once __DIR__ . '/_helpers.php';
require_once __DIR__ . '/_gallery_helpers.php';

wb_method('GET');

$auth = mobile_auth($pdo, ['business', 'admin']);
$ctx = mobile_business_context($pdo, $auth);
$businessId = (int)$ctx['business_id'];
$category = trim((string)mobile_param('category', ''));
$includeHidden = mobile_bool_param('include_hidden', false);

if ($category !== '') {
    $category = mobile_gallery_validate_category($category);
}

if (!mobile_gallery_table_exists($pdo)) {
    wb_ok([
        'items' => [],
        'categories' => mobile_gallery_limits_payload($pdo, $businessId),
        'quota' => ['used' => 0, 'limit' => WB_GALLERY_QUOTA_LIMIT],
        'cover_item' => null,
        'has_cover' => false,
        'limits' => mobile_gallery_categories(),
        'migration_required' => true,
    ]);
}

try {
    $sql = "SELECT *
            FROM business_photos
            WHERE business_id = ?
              AND status <> 'deleted'";
    $params = [$businessId];
    if (!$includeHidden) {
        $sql .= " AND status = 'active' AND is_visible = 1";
    }
    if ($category !== '') {
        $sql .= ' AND category = ?';
        $params[] = $category;
    }
    $sql .= ' ORDER BY is_cover DESC, category ASC, sort_order ASC, id DESC';

    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);
    $items = array_map('mobile_gallery_item', $stmt->fetchAll());

    // Kapak: müşteri tarafında GERÇEKTEN görünen kapakla aynı sorgu
    // (active + visible). Gizli/pasif kapak "Aktif kapak" sayılmaz.
    $coverItem = mobile_gallery_cover_from_table($pdo, $businessId);

    wb_ok([
        'items' => $items,
        'categories' => mobile_gallery_limits_payload($pdo, $businessId),
        'quota' => [
            'used' => mobile_gallery_count($pdo, $businessId),
            'limit' => WB_GALLERY_QUOTA_LIMIT,
        ],
        'cover_item' => $coverItem,
        'has_cover' => $coverItem !== null,
        'limits' => mobile_gallery_categories(),
    ]);
} catch (Throwable $e) {
    error_log('[mobile/business/gallery.php] ' . $e->getMessage());
    wb_err('Galeri alınamadı', 500, 'server_error');
}
