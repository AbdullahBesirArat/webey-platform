<?php
declare(strict_types=1);
/**
 * api/mobile/business/profile-save.php
 * POST — Token sahibi işletmenin profil bilgilerini günceller.
 *
 * Body (JSON):
 *   name         : string  (zorunlu, maks 40)
 *   owner_name   : string  (opsiyonel, maks 100)
 *   phone        : string  (opsiyonel, maks 20) — işletme/salon telefonu (businesses.phone)
 *   city         : string  (opsiyonel, maks 80)
 *   district     : string  (opsiyonel, maks 80)
 *   address_line : string  (opsiyonel, maks 300)
 *   about        : string  (opsiyonel, maks 500)
 *   map_url      : string  (opsiyonel, maks 500)
 *   latitude     : float   (opsiyonel, -90..90)
 *   longitude    : float   (opsiyonel, -180..180)
 *   building_no  : string  (opsiyonel, maks 20)
 *   neighborhood : string  (opsiyonel, maks 100)
 *
 * Yanıt:
 *   business : object
 *
 * Faz 8B — Bearer token zorunlu, business/admin tipi.
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';
require_once __DIR__ . '/_helpers.php';
require_once __DIR__ . '/../_geocoding.php';
require_once __DIR__ . '/../_category_helpers.php';

wb_method('POST');

$auth       = mobile_auth($pdo, ['business', 'admin']);
$ctx        = mobile_business_context($pdo, $auth);
$businessId = (int)$ctx['business_id'];

$in = wb_body();

// ── Input sanitize ────────────────────────────────────────────────────────────
$name         = mb_substr(trim((string)($in['name']         ?? '')), 0, 40);
$ownerName    = mb_substr(trim((string)($in['owner_name']   ?? '')), 0, 100);
$phone        = mb_substr(trim((string)($in['phone']        ?? '')), 0, 20);
$city         = mb_substr(trim((string)($in['city']         ?? '')), 0, 80);
$district     = mb_substr(trim((string)($in['district']     ?? '')), 0, 80);
$addressLine  = mb_substr(trim((string)($in['address_line'] ?? '')), 0, 300);
$about        = mb_substr(trim((string)($in['about']        ?? '')), 0, 500);
$atelierNote  = mb_substr(trim((string)($in['atelier_note'] ?? '')), 0, 280);
$atelierProvided = array_key_exists('atelier_note', $in);
$mapUrl       = mb_substr(trim((string)($in['map_url']      ?? '')), 0, 500);
$buildingNo   = mb_substr(trim((string)($in['building_no']  ?? '')), 0, 20);
$streetName   = mb_substr(trim((string)($in['street_name']  ?? '')), 0, 120);
$neighborhood = mb_substr(trim((string)($in['neighborhood'] ?? '')), 0, 100);

// Onboarding ana hizmet kategorileri (opsiyonel; yalnizca gonderildiyse islenir).
$categorySlugsProvided = array_key_exists('category_slugs', $in);
$categorySlugs = [];
if ($categorySlugsProvided && is_array($in['category_slugs'])) {
    foreach ($in['category_slugs'] as $slugItem) {
        $slugItem = strtolower(trim((string)$slugItem));
        if ($slugItem !== '' && !in_array($slugItem, $categorySlugs, true)) {
            $categorySlugs[] = mb_substr($slugItem, 0, 100);
        }
    }
}

$latRaw  = $in['latitude']  ?? null;
$lngRaw  = $in['longitude'] ?? null;
$latitude  = ($latRaw  !== null && $latRaw  !== '') ? (float)$latRaw  : null;
$longitude = ($lngRaw !== null && $lngRaw !== '') ? (float)$lngRaw : null;

// 0,0 ("Null Island") geçerli salon konumu değildir → konum yok say.
if ($latitude !== null && $longitude !== null
    && abs($latitude) < 0.0001 && abs($longitude) < 0.0001) {
    $latitude = null;
    $longitude = null;
}

// ── Doğrulama ─────────────────────────────────────────────────────────────────
if ($name === '') {
    wb_err('name zorunludur.', 422, 'missing_name');
}
if ($phone !== '' && !preg_match('/^\+?[0-9()\s\-]{7,20}$/', $phone)) {
    wb_err('Geçerli bir telefon numarası girin.', 422, 'invalid_phone');
}
if ($latitude !== null && ($latitude < -90.0 || $latitude > 90.0)) {
    wb_err('latitude -90 ile 90 arasında olmalı.', 422, 'invalid_latitude');
}
if ($longitude !== null && ($longitude < -180.0 || $longitude > 180.0)) {
    wb_err('longitude -180 ile 180 arasında olmalı.', 422, 'invalid_longitude');
}

// ── Best-effort geocoding: lat/lng yok ama adres bilgisi varsa dene ──────────
$geocodingStatus = 'skipped';
$geocodingSource = null;
if ($latitude === null && $longitude === null && ($city !== '' || $district !== '')) {
    $fullAddress = wb_build_full_address([
        'street_name' => $streetName,
        'building_no' => $buildingNo,
        'neighborhood' => $neighborhood,
        'district' => $district,
        'city' => $city,
    ]);
    try {
        $geo = wb_geocode_address($fullAddress);
        if ($geo !== null) {
            $latitude = $geo['lat'];
            $longitude = $geo['lng'];
            $geocodingStatus = 'success';
            $geocodingSource = $geo['source'];
        } else {
            $geocodingStatus = 'failed';
        }
    } catch (Throwable $e) {
        error_log('[profile-save geocode] ' . $e->getMessage());
        $geocodingStatus = 'failed';
    }
}

try {
    // street_name kolonu canlı tabloda olmayabilir; kontrol et.
    $colCheck = $pdo->prepare(
        "SELECT COUNT(*) AS c FROM information_schema.COLUMNS
         WHERE TABLE_SCHEMA = DATABASE()
           AND TABLE_NAME = 'businesses'
           AND COLUMN_NAME = 'street_name'"
    );
    $colCheck->execute();
    $hasStreet = (int)($colCheck->fetch()['c'] ?? 0) > 0;
    $hasAtelier = mobile_table_has_column($pdo, 'businesses', 'atelier_note');

    $sets = [
        "name = ?",
        "owner_name = NULLIF(?, '')",
        "phone = NULLIF(?, '')",
        "city = NULLIF(?, '')",
        "district = NULLIF(?, '')",
        "address_line = NULLIF(?, '')",
        "about = NULLIF(?, '')",
        "map_url = NULLIF(?, '')",
        "latitude = ?",
        "longitude = ?",
        "building_no = NULLIF(?, '')",
        "neighborhood = NULLIF(?, '')",
    ];
    $params = [
        $name, $ownerName, $phone, $city, $district,
        $addressLine, $about, $mapUrl,
        $latitude, $longitude,
        $buildingNo, $neighborhood,
    ];
    if ($hasStreet) {
        $sets[] = "street_name = NULLIF(?, '')";
        $params[] = $streetName;
    }
    // atelier_note: yalnızca body'de gönderildiyse güncelle (kısmi kayıt korunur).
    if ($hasAtelier && $atelierProvided) {
        $sets[] = "atelier_note = NULLIF(?, '')";
        $params[] = $atelierNote;
    }
    $params[] = $businessId;
    $pdo->prepare(
        "UPDATE businesses SET " . implode(', ', $sets) . " WHERE id = ?"
    )->execute($params);

    // ── Ana hizmet kategorileri (onboarding cok seçimli) ─────────────────────
    $savedCategorySlugs = null;
    if ($categorySlugsProvided
        && mobile_category_table_exists($pdo)
        && mobile_business_categories_table_exists($pdo)) {
        if ($categorySlugs === []) {
            wb_err('En az bir hizmet kategorisi seçin.', 422, 'missing_categories');
        }
        // Yalnizca aktif SISTEM kategorileri secilebilir.
        $slugPlaceholders = implode(',', array_fill(0, count($categorySlugs), '?'));
        $catStmt = $pdo->prepare(
            "SELECT id, slug FROM service_categories
             WHERE business_id = 0 AND is_active = 1 AND slug IN ($slugPlaceholders)"
        );
        $catStmt->execute($categorySlugs);
        $catRows = $catStmt->fetchAll();
        if (count($catRows) !== count($categorySlugs)) {
            wb_err('Geçersiz kategori seçimi.', 422, 'invalid_categories');
        }

        $pdo->prepare('DELETE FROM business_categories WHERE business_id = ?')
            ->execute([$businessId]);
        $insStmt = $pdo->prepare(
            'INSERT IGNORE INTO business_categories (business_id, category_id) VALUES (?, ?)'
        );
        foreach ($catRows as $catRow) {
            $insStmt->execute([$businessId, (int)$catRow['id']]);
        }
        // Geriye uyumluluk: businesses.type = ilk secilen slug.
        $pdo->prepare('UPDATE businesses SET type = ? WHERE id = ?')
            ->execute([$categorySlugs[0], $businessId]);
        $savedCategorySlugs = $categorySlugs;
    }

    // ── Güncel satırı döndür ──────────────────────────────────────────────────
    $streetSelect = $hasStreet ? 'street_name' : 'NULL AS street_name';
    $atelierSelect = $hasAtelier ? 'atelier_note' : 'NULL AS atelier_note';
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
    $row    = $stmt->fetch() ?: [];
    $images = mobile_images($row['images_json'] ?? null);

    // Kayitli kategori slug'larini her zaman dondur (gonderilmediyse mevcutlar).
    if ($savedCategorySlugs === null
        && mobile_category_table_exists($pdo)
        && mobile_business_categories_table_exists($pdo)) {
        $curStmt = $pdo->prepare(
            'SELECT sc.slug FROM business_categories bc
             JOIN service_categories sc ON sc.id = bc.category_id
             WHERE bc.business_id = ?
             ORDER BY sc.sort_order ASC'
        );
        $curStmt->execute([$businessId]);
        $savedCategorySlugs = array_map(
            static fn(array $r): string => (string)$r['slug'],
            $curStmt->fetchAll()
        );
    }

    wb_ok([
        'geocoding_status' => $geocodingStatus,
        'geocoding_source' => $geocodingSource,
        'category_slugs' => $savedCategorySlugs ?? [],
        'business' => [
        'id'                   => (string)($row['id'] ?? $businessId),
        'name'                 => (string)($row['name'] ?? $name),
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
        'latitude'             => ($row['latitude']  ?? null) !== null ? (float)$row['latitude']  : null,
        'longitude'            => ($row['longitude'] ?? null) !== null ? (float)$row['longitude'] : null,
        'building_no'          => $row['building_no']   ?? null,
        'street_name'          => $row['street_name']   ?? null,
        'neighborhood'         => $row['neighborhood']  ?? null,
        'cover_image_url'      => $images['cover_image_url'],
        'logo_url'             => $images['logo_url'],
        'onboarding_step'      => (int)($row['onboarding_step']      ?? 1),
        'onboarding_completed' => (bool)($row['onboarding_completed'] ?? false),
    ],
    ]);

} catch (Throwable $e) {
    error_log('[mobile/business/profile-save.php] ' . $e->getMessage());
    wb_err('Profil kaydedilemedi.', 500, 'internal_error');
}
