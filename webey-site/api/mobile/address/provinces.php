<?php
declare(strict_types=1);
/**
 * GET /api/mobile/address/provinces.php
 * Türkiye il listesi (81 il).
 * Auth gerektirmez; mobile onboarding & customer keşfet kullanır.
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/_helpers.php';

wb_method('GET');

if (!wb_address_table_ready($pdo, 'address_provinces')) {
    wb_ok(['items' => [], 'ready' => false]);
}

try {
    $stmt = $pdo->query(
        'SELECT id, name, slug, plate_code FROM address_provinces ORDER BY name ASC'
    );
    $items = array_map(static fn(array $r): array => [
        'id' => (int)$r['id'],
        'name' => (string)$r['name'],
        'slug' => (string)$r['slug'],
        'plate_code' => (int)$r['plate_code'],
    ], $stmt->fetchAll() ?: []);
    wb_ok(['items' => $items, 'ready' => true]);
} catch (Throwable $e) {
    error_log('[mobile/address/provinces.php] ' . $e->getMessage());
    wb_ok(['items' => [], 'ready' => false]);
}
