<?php
declare(strict_types=1);

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';
require_once __DIR__ . '/_helpers.php';
require_once __DIR__ . '/_gallery_helpers.php';

wb_method('POST');

$auth = mobile_auth($pdo, ['business', 'admin']);
$ctx = mobile_business_context($pdo, $auth);
$businessId = (int)$ctx['business_id'];
mobile_gallery_require_table($pdo);
$body = wb_body();
$id = (int)($body['id'] ?? 0);

try {
    mobile_gallery_fetch_photo($pdo, $businessId, $id);
    $stmt = $pdo->prepare("
        UPDATE business_photos
        SET status = 'deleted', is_visible = 0, is_cover = 0, updated_at = NOW()
        WHERE id = ? AND business_id = ?
    ");
    $stmt->execute([$id, $businessId]);
    wb_ok(['deleted' => true]);
} catch (Throwable $e) {
    error_log('[mobile/business/gallery-delete.php] ' . $e->getMessage());
    wb_err('Fotoğraf silinemedi', 500, 'server_error');
}
