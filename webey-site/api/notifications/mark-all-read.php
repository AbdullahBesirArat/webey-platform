<?php
declare(strict_types=1);
/**
 * api/notifications/mark-all-read.php
 * POST — Tüm bildirimleri okundu işaretle
 */

require_once __DIR__ . '/../admin/_bootstrap.php';
wb_method('POST');

$bid = $user['business_id'];
if (!$bid) wb_err('İşletme bulunamadı', 404, 'business_not_found');

try {
    $stmt = $pdo->prepare('UPDATE notifications SET is_read = 1 WHERE business_id = ? AND is_read = 0');
    $stmt->execute([$bid]);
    wb_ok(['marked' => true, 'count' => $stmt->rowCount()]);
} catch (Throwable $e) {
    error_log('[notifications/mark-all-read] ' . $e->getMessage());
    wb_err('İşlem tamamlanamadı', 500, 'internal_error');
}