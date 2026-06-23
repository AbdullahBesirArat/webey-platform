<?php
declare(strict_types=1);
/**
 * api/mobile/business/profile.php
 * GET — Token sahibi işletmenin profil bilgilerini döner.
 *
 * Yanıt:
 *   business : object  — profil alanları
 *
 * Faz 8B — Bearer token zorunlu, business/admin tipi.
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';
require_once __DIR__ . '/_helpers.php';
require_once __DIR__ . '/../_category_helpers.php';

wb_method('GET');

$auth       = mobile_auth($pdo, ['business', 'admin']);
$ctx        = mobile_business_context($pdo, $auth);
$businessId = (int)$ctx['business_id'];

try {
    $colCheck = $pdo->prepare(
        "SELECT COUNT(*) AS c FROM information_schema.COLUMNS
         WHERE TABLE_SCHEMA = DATABASE()
           AND TABLE_NAME = 'businesses'
           AND COLUMN_NAME = 'street_name'"
    );
    $colCheck->execute();
    $hasStreet = (int)($colCheck->fetch()['c'] ?? 0) > 0;
    $streetSelect = $hasStreet ? 'street_name' : 'NULL AS street_name';

    $atelierSelect = mobile_table_has_column($pdo, 'businesses', 'atelier_note')
        ? 'atelier_note'
        : 'NULL AS atelier_note';

    $stmt = $pdo->prepare("
        SELECT id, name, slug, owner_name, phone, type, status,
               city, district, address_line, about, $atelierSelect,
               map_url, latitude, longitude, building_no, $streetSelect, neighborhood,
               images_json, onboarding_step, onboarding_completed
        FROM businesses
        WHERE id = ?
        LIMIT 1
    ");
    $stmt->execute([$businessId]);
    $row = $stmt->fetch();

    if (!$row) {
        wb_err('İşletme bulunamadı.', 404, 'business_not_found');
    }

    $images = mobile_images($row['images_json'] ?? null);

    // Onboarding'de secilen ana hizmet kategorileri (migration oncesi bos liste).
    $categorySlugs = [];
    if (mobile_category_table_exists($pdo)
        && mobile_business_categories_table_exists($pdo)) {
        $catStmt = $pdo->prepare(
            'SELECT sc.slug FROM business_categories bc
             JOIN service_categories sc ON sc.id = bc.category_id
             WHERE bc.business_id = ?
             ORDER BY sc.sort_order ASC'
        );
        $catStmt->execute([$businessId]);
        $categorySlugs = array_map(
            static fn(array $r): string => (string)$r['slug'],
            $catStmt->fetchAll()
        );
    }

    wb_ok([
        'category_slugs' => $categorySlugs,
        'business' => [
        'id'                   => (string)$row['id'],
        'name'                 => (string)($row['name'] ?? ''),
        'slug'                 => $row['slug']         ?? null,
        'owner_name'           => $row['owner_name']   ?? null,
        'phone'                => $row['phone']         ?? null,
        'type'                 => $row['type']          ?? null,
        'status'               => $row['status']        ?? null,
        'city'                 => $row['city']          ?? null,
        'district'             => $row['district']      ?? null,
        'address_line'         => $row['address_line']  ?? null,
        'about'                => $row['about']         ?? null,
        'atelier_note'         => $row['atelier_note']  ?? null,
        'map_url'              => $row['map_url']       ?? null,
        'latitude'             => $row['latitude']  !== null ? (float)$row['latitude']  : null,
        'longitude'            => $row['longitude'] !== null ? (float)$row['longitude'] : null,
        'building_no'          => $row['building_no']   ?? null,
        'street_name'          => $row['street_name']   ?? null,
        'neighborhood'         => $row['neighborhood']  ?? null,
        'cover_image_url'      => $images['cover_image_url'],
        'logo_url'             => $images['logo_url'],
        'onboarding_step'      => (int)($row['onboarding_step']      ?? 1),
        'onboarding_completed' => (bool)($row['onboarding_completed'] ?? false),
    ]]);

} catch (Throwable $e) {
    error_log('[mobile/business/profile.php] ' . $e->getMessage());
    wb_err('Profil bilgisi alınamadı.', 500, 'internal_error');
}
