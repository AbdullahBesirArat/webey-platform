<?php
declare(strict_types=1);
/**
 * api/services/delete.php
 * POST — Hizmet sil
 */

require_once __DIR__ . '/../admin/_bootstrap.php';
wb_method('POST');

$bid = $user['business_id'];
if (!$bid) wb_err('İşletme bulunamadı', 404, 'business_not_found');

$in = wb_body();
$id = isset($in['id']) ? (int)$in['id'] : 0;
if (!$id) wb_err('id zorunlu', 400, 'missing_id');

try {
    $stmt = $pdo->prepare('DELETE FROM services WHERE id = ? AND business_id = ?');
    $stmt->execute([$id, $bid]);

    wb_ok(['deleted' => true, 'id' => (string)$id]);

} catch (Throwable $e) {
    error_log('[services/delete] ' . $e->getMessage());
    wb_err('Hizmet silinemedi', 500, 'internal_error');
}