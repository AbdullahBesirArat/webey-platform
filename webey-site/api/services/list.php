<?php
declare(strict_types=1);
/**
 * api/services/list.php
 * GET — Hizmet listesi
 */

require_once __DIR__ . '/../admin/_bootstrap.php';
wb_method('GET');

$bid = $user['business_id'];
if (!$bid) wb_err('İşletme bulunamadı', 404, 'business_not_found');

try {
    $stmt = $pdo->prepare('
        SELECT id, name, price, duration_min
        FROM services
        WHERE business_id = ?
        ORDER BY name
    ');
    $stmt->execute([$bid]);

    $services = array_map(fn($r) => [
        'id'          => (string)$r['id'],
        'name'        => $r['name'],
        'price'       => $r['price'] !== null ? (float)$r['price'] : null,
        'durationMin' => (int)$r['duration_min'],
    ], $stmt->fetchAll());

    wb_ok(['services' => $services]);

} catch (Throwable $e) {
    error_log('[services/list] ' . $e->getMessage());
    wb_err('Hizmetler yüklenemedi', 500, 'internal_error');
}