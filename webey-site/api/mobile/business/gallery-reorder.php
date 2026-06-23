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

$category = mobile_gallery_validate_category((string)($body['category'] ?? ''));
$order = $body['order'] ?? [];
if (!is_array($order)) {
    wb_err('order id listesi olmalı', 400, 'bad_request');
}
$ids = array_values(array_filter(array_map('intval', $order), static fn(int $id): bool => $id > 0));

try {
    $pdo->beginTransaction();
    if ($ids !== []) {
        $in = implode(',', array_fill(0, count($ids), '?'));
        $stmt = $pdo->prepare("
            SELECT id
            FROM business_photos
            WHERE business_id = ?
              AND category = ?
              AND status <> 'deleted'
              AND id IN ($in)
            FOR UPDATE
        ");
        $stmt->execute(array_merge([$businessId, $category], $ids));
        $owned = array_map('intval', array_column($stmt->fetchAll(), 'id'));
        sort($owned);
        $expected = $ids;
        sort($expected);
        if ($owned !== $expected) {
            $pdo->rollBack();
            wb_err('Sıralama listesinde yetkisiz fotoğraf var', 403, 'forbidden');
        }
        $update = $pdo->prepare('UPDATE business_photos SET sort_order = ?, updated_at = NOW() WHERE id = ? AND business_id = ?');
        foreach ($ids as $index => $id) {
            $update->execute([($index + 1) * 10, $id, $businessId]);
        }
    }
    $pdo->commit();
    wb_ok(['reordered' => true]);
} catch (Throwable $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    error_log('[mobile/business/gallery-reorder.php] ' . $e->getMessage());
    wb_err('Sıralama güncellenemedi', 500, 'server_error');
}
