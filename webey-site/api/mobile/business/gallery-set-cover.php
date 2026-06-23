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
    $pdo->beginTransaction();
    mobile_gallery_fetch_photo($pdo, $businessId, $id, true);
    $pdo->prepare('UPDATE business_photos SET is_cover = 0 WHERE business_id = ?')
        ->execute([$businessId]);
    $pdo->prepare("
        UPDATE business_photos
        SET is_cover = 1, is_visible = 1, status = 'active', updated_at = NOW()
        WHERE id = ? AND business_id = ?
    ")->execute([$id, $businessId]);
    $row = mobile_gallery_fetch_photo($pdo, $businessId, $id);
    $pdo->commit();
    wb_ok(['item' => mobile_gallery_item($row)]);
} catch (Throwable $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    error_log('[mobile/business/gallery-set-cover.php] ' . $e->getMessage());
    wb_err('Kapak güncellenemedi', 500, 'server_error');
}
