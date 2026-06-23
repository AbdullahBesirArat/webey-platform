<?php
declare(strict_types=1);
/**
 * api/staff/delete.php
 * POST — Personel sil
 */

require_once __DIR__ . '/../admin/_bootstrap.php';
wb_method('POST');

$bid = $user['business_id'];
if (!$bid) wb_err('İşletme bulunamadı', 404, 'business_not_found');

$in = wb_body();
$id = isset($in['id']) ? (int)$in['id'] : 0;
if (!$id) wb_err('id zorunlu', 400, 'missing_id');

try {
    $stmt = $pdo->prepare('DELETE FROM staff WHERE id = ? AND business_id = ?');
    $stmt->execute([$id, $bid]);

    if ($stmt->rowCount() === 0) wb_err('Personel bulunamadı', 404, 'not_found');

    wb_ok(['deleted' => true]);

} catch (Throwable $e) {
    error_log('[staff/delete] ' . $e->getMessage());
    wb_err('Personel silinemedi', 500, 'internal_error');
}