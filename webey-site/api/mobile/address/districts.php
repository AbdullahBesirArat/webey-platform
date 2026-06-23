<?php
declare(strict_types=1);
/**
 * GET /api/mobile/address/districts.php?province_id=34
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/_helpers.php';

wb_method('GET');

$provinceId = mobile_int_param('province_id');
if ($provinceId === null || $provinceId <= 0) {
    wb_err('province_id zorunlu', 400, 'missing_param');
}

if (!wb_address_table_ready($pdo, 'address_districts')) {
    wb_ok(['items' => [], 'ready' => false]);
}

try {
    $stmt = $pdo->prepare(
        'SELECT id, province_id, name, slug FROM address_districts
          WHERE province_id = ? ORDER BY name ASC'
    );
    $stmt->execute([$provinceId]);
    $items = array_map(static fn(array $r): array => [
        'id' => (int)$r['id'],
        'province_id' => (int)$r['province_id'],
        'name' => (string)$r['name'],
        'slug' => (string)$r['slug'],
    ], $stmt->fetchAll() ?: []);
    wb_ok(['items' => $items, 'ready' => true]);
} catch (Throwable $e) {
    error_log('[mobile/address/districts.php] ' . $e->getMessage());
    wb_ok(['items' => [], 'ready' => false]);
}
