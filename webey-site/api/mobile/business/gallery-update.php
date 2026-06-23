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
if ($id <= 0) {
    wb_err('id zorunlu', 400, 'bad_request');
}

try {
    $pdo->beginTransaction();
    $current = mobile_gallery_fetch_photo($pdo, $businessId, $id, true);
    $category = array_key_exists('category', $body)
        ? mobile_gallery_validate_category((string)$body['category'])
        : (string)$current['category'];

    if ($category !== (string)$current['category']) {
        mobile_gallery_assert_quota($pdo, $businessId, $category, $id);
    }

    $serviceId = array_key_exists('service_id', $body)
        ? mobile_gallery_nullable_int($body['service_id'])
        : ($current['service_id'] !== null ? (int)$current['service_id'] : null);
    $staffId = array_key_exists('staff_id', $body)
        ? mobile_gallery_nullable_int($body['staff_id'])
        : ($current['staff_id'] !== null ? (int)$current['staff_id'] : null);
    mobile_gallery_assert_service($pdo, $businessId, $serviceId);
    mobile_gallery_assert_staff($pdo, $businessId, $staffId);

    $isVisible = array_key_exists('is_visible', $body)
        ? (bool)$body['is_visible']
        : (bool)$current['is_visible'];
    $status = array_key_exists('status', $body)
        ? mobile_gallery_normalize_status($body['status'], $isVisible)
        : ($isVisible ? 'active' : 'hidden');
    if ($status === 'hidden') {
        $isVisible = false;
    }
    if ($status === 'active') {
        $isVisible = true;
    }

    $title = array_key_exists('title', $body)
        ? mb_substr(trim((string)$body['title']), 0, 160)
        : ($current['title'] ?? null);
    $description = array_key_exists('description', $body)
        ? mb_substr(trim((string)$body['description']), 0, 2000)
        : ($current['description'] ?? null);
    $isCover = array_key_exists('is_cover', $body) ? (bool)$body['is_cover'] : (bool)$current['is_cover'];
    if ($isCover) {
        $pdo->prepare('UPDATE business_photos SET is_cover = 0 WHERE business_id = ?')
            ->execute([$businessId]);
    }

    $stmt = $pdo->prepare("
        UPDATE business_photos
        SET category = ?,
            title = ?,
            description = ?,
            service_id = ?,
            staff_id = ?,
            is_visible = ?,
            status = ?,
            is_cover = ?,
            updated_at = NOW()
        WHERE id = ? AND business_id = ?
    ");
    $stmt->execute([
        $category,
        is_string($title) && trim($title) !== '' ? trim($title) : null,
        is_string($description) && trim($description) !== '' ? trim($description) : null,
        $serviceId,
        $staffId,
        $isVisible ? 1 : 0,
        $status,
        $isCover ? 1 : 0,
        $id,
        $businessId,
    ]);

    $row = mobile_gallery_fetch_photo($pdo, $businessId, $id);
    $pdo->commit();
    wb_ok(['item' => mobile_gallery_item($row)]);
} catch (Throwable $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    error_log('[mobile/business/gallery-update.php] ' . $e->getMessage());
    wb_err('Fotoğraf güncellenemedi', 500, 'server_error');
}
