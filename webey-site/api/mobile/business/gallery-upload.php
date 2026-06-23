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

$category = mobile_gallery_validate_category((string)($_POST['category'] ?? ''));
$title = mb_substr(trim((string)($_POST['title'] ?? '')), 0, 160);
$description = mb_substr(trim((string)($_POST['description'] ?? '')), 0, 2000);
$serviceId = mobile_gallery_nullable_int($_POST['service_id'] ?? null);
$staffId = mobile_gallery_nullable_int($_POST['staff_id'] ?? null);
$pairGroupId = mb_substr(trim((string)($_POST['pair_group_id'] ?? '')), 0, 80);
$pairRole = trim((string)($_POST['pair_role'] ?? ''));
$isCover = mobile_bool_param('is_cover', false) || $category === 'cover';

if ($pairRole !== '' && !in_array($pairRole, ['before', 'after'], true)) {
    wb_err('pair_role before/after olmalı', 422, 'validation_error');
}

$file = $_FILES['file'] ?? null;
if (!$file) {
    wb_err('file zorunlu', 400, 'bad_request');
}

try {
    mobile_gallery_assert_service($pdo, $businessId, $serviceId);
    mobile_gallery_assert_staff($pdo, $businessId, $staffId);

    $pdo->beginTransaction();
    mobile_gallery_assert_quota($pdo, $businessId, $category, null, true);
    $paths = mobile_gallery_process_upload($file, $businessId);

    $nextOrderStmt = $pdo->prepare("
        SELECT COALESCE(MAX(sort_order), 0) + 10
        FROM business_photos
        WHERE business_id = ? AND category = ?
        FOR UPDATE
    ");
    $nextOrderStmt->execute([$businessId, $category]);
    $sortOrder = (int)$nextOrderStmt->fetchColumn();

    if ($isCover) {
        $pdo->prepare('UPDATE business_photos SET is_cover = 0 WHERE business_id = ?')
            ->execute([$businessId]);
    }

    $stmt = $pdo->prepare("
        INSERT INTO business_photos
            (business_id, category, title, description, service_id, staff_id,
             pair_group_id, pair_role, original_path, thumb_path, medium_path,
             large_path, width, height, bytes, is_cover, is_visible, status,
             sort_order, created_at, updated_at)
        VALUES
            (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, 'active', ?, NOW(), NOW())
    ");
    $stmt->execute([
        $businessId,
        $category,
        $title !== '' ? $title : null,
        $description !== '' ? $description : null,
        $serviceId,
        $staffId,
        $pairGroupId !== '' ? $pairGroupId : null,
        $pairRole !== '' ? $pairRole : null,
        $paths['original_path'],
        $paths['thumb_path'],
        $paths['medium_path'],
        $paths['large_path'],
        $paths['width'],
        $paths['height'],
        $paths['bytes'],
        $isCover ? 1 : 0,
        $sortOrder,
    ]);
    $id = (int)$pdo->lastInsertId();

    $row = mobile_gallery_fetch_photo($pdo, $businessId, $id);
    $pdo->commit();

    wb_ok(['item' => mobile_gallery_item($row)], 201);
} catch (Throwable $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    error_log('[mobile/business/gallery-upload.php] ' . $e->getMessage());
    wb_err('Fotoğraf yüklenemedi', 500, 'server_error');
}
