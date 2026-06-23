<?php
declare(strict_types=1);
/**
 * GET /api/mobile/address/neighborhoods.php?district_id=123&q=...
 * Mahalle listesi. q opsiyonel substring search. limit max 100.
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/_helpers.php';

wb_method('GET');

$districtId = mobile_int_param('district_id');
if ($districtId === null || $districtId <= 0) {
    wb_err('district_id zorunlu', 400, 'missing_param');
}
$q = trim((string)mobile_param('q', ''));
$limit = mobile_limit(mobile_param('limit', 50), 50, 100);

if (!wb_address_table_ready($pdo, 'address_neighborhoods')) {
    wb_ok(['items' => [], 'ready' => false]);
}

try {
    if ($q !== '') {
        $stmt = $pdo->prepare(
            'SELECT id, district_id, province_id, name, slug
               FROM address_neighborhoods
              WHERE district_id = ? AND name LIKE ?
              ORDER BY name ASC
              LIMIT ?'
        );
        $stmt->bindValue(1, $districtId, PDO::PARAM_INT);
        $stmt->bindValue(2, '%' . $q . '%', PDO::PARAM_STR);
        $stmt->bindValue(3, $limit, PDO::PARAM_INT);
        $stmt->execute();
    } else {
        $stmt = $pdo->prepare(
            'SELECT id, district_id, province_id, name, slug
               FROM address_neighborhoods
              WHERE district_id = ?
              ORDER BY name ASC
              LIMIT ?'
        );
        $stmt->bindValue(1, $districtId, PDO::PARAM_INT);
        $stmt->bindValue(2, $limit, PDO::PARAM_INT);
        $stmt->execute();
    }
    $items = array_map(static fn(array $r): array => [
        'id' => (int)$r['id'],
        'district_id' => (int)$r['district_id'],
        'province_id' => (int)$r['province_id'],
        'name' => (string)$r['name'],
        'slug' => (string)$r['slug'],
    ], $stmt->fetchAll() ?: []);
    wb_ok(['items' => $items, 'ready' => true]);
} catch (Throwable $e) {
    error_log('[mobile/address/neighborhoods.php] ' . $e->getMessage());
    wb_ok(['items' => [], 'ready' => false]);
}
