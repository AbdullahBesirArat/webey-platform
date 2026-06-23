<?php
declare(strict_types=1);
/**
 * api/mobile/customer/favorites.php
 * GET — Token sahibi müşterinin favori salonlarını listeler.
 *
 * Tablo: customer_favorites (canlı şema)
 *   id bigint, customer_user_id int unsigned, business_id int, created_at datetime
 *   UNIQUE KEY uq_customer_business (customer_user_id, business_id)
 *
 * Yanıt: SalonSummary.fromJson() uyumlu items dizisi.
 *
 * Faz 8A — Bearer token zorunlu, customer tipi.
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';
require_once __DIR__ . '/../business/_gallery_helpers.php';

wb_method('GET');

$session = mobile_auth($pdo, 'customer');
$userId  = $session['user_id'];
$lat = mobile_param('lat', null);
$lng = mobile_param('lng', null);
$latValue = is_numeric($lat) ? (float)$lat : null;
$lngValue = is_numeric($lng) ? (float)$lng : null;
$hasDistance = $latValue !== null && $lngValue !== null;

// ── customer_favorites tablosunun var olup olmadığını kontrol et ──────────────
// Tablo yoksa boş liste döndür; hata vermez.
try {
    $pdo->query("SELECT 1 FROM customer_favorites LIMIT 1");
} catch (Throwable) {
    wb_ok(['items' => []]);
}


try {
    // Gerçek puan/yorum sayısı reviews tablosundan (varsa) hesaplanır;
    // salons.php ile aynı mantık (status='active').
    $hasReviews = mobile_table_has_column($pdo, 'reviews', 'id');
    $hasReviewStaffCol = $hasReviews && mobile_table_has_column($pdo, 'reviews', 'staff_id');
    $hasReviewStatusCol = $hasReviews && mobile_table_has_column($pdo, 'reviews', 'status');
    $reviewStatusSql = $hasReviewStatusCol ? " AND r.status = 'active'" : '';
    $businessReviewSql = $hasReviewStaffCol ? ' AND (r.staff_id IS NULL OR r.staff_id = 0)' : '';
    $ratingSelect = $hasReviews
        ? ", (SELECT ROUND(AVG(r.rating), 1) FROM reviews r WHERE r.business_id = b.id{$reviewStatusSql}{$businessReviewSql}) AS avg_rating"
        . ", (SELECT COUNT(*) FROM reviews r WHERE r.business_id = b.id{$reviewStatusSql}{$businessReviewSql}) AS review_count"
        : ', NULL AS avg_rating, 0 AS review_count';

    // Başlangıç fiyatı: businesses.min_price yoksa aktif hizmetlerin MIN(price)'ı
    // (salons.php ile aynı mantık). Hizmet fiyatı da yoksa null kalır.
    $hasServices = mobile_table_has_column($pdo, 'services', 'price');
    $serviceMinSelect = $hasServices
        ? ", (SELECT MIN(s.price) FROM services s WHERE s.business_id = b.id AND s.price > 0) AS service_min_price"
        : ', NULL AS service_min_price';
    $distanceSelect = $hasDistance
        ? ', (6371 * ACOS(LEAST(1, COS(RADIANS(?)) * COS(RADIANS(b.latitude)) * COS(RADIANS(b.longitude) - RADIANS(?)) + SIN(RADIANS(?)) * SIN(RADIANS(b.latitude))))) AS distance_km'
        : ', NULL AS distance_km';
    $distanceParams = $hasDistance ? [$latValue, $lngValue, $latValue] : [];

    // ── Favori salonları çek, sadece aktif işletmeler ─────────────────────────
    $stmt = $pdo->prepare("
        SELECT b.id, b.slug, b.name, b.about, b.city, b.district,
               b.address_line, b.images_json, b.min_price, b.max_price, b.type,
               b.latitude, b.longitude
               $ratingSelect
               $serviceMinSelect
               $distanceSelect
        FROM customer_favorites cf
        INNER JOIN businesses b
            ON b.id = cf.business_id
           AND b.status = 'active'
        WHERE cf.customer_user_id = ?
        ORDER BY cf.created_at DESC
    ");
    $stmt->execute(array_merge($distanceParams, [$userId]));
    $rows = $stmt->fetchAll();

    // ── Açık mı? business_hours'dan toplu kontrol ─────────────────────────────
    $ids = array_map(static fn(array $row): int => (int)$row['id'], $rows);
    $openNowByBusiness = [];
    if ($ids !== []) {
        $placeholders = implode(',', array_fill(0, count($ids), '?'));
        $today   = mobile_day_key();
        $nowTime = date('H:i:s');
        $hoursStmt = $pdo->prepare("
            SELECT business_id
            FROM business_hours
            WHERE business_id IN ($placeholders)
              AND day = ?
              AND is_open = 1
              AND open_time <= ?
              AND close_time >= ?
        ");
        $hoursStmt->execute(array_merge($ids, [$today, $nowTime, $nowTime]));
        foreach ($hoursStmt->fetchAll() as $row) {
            $openNowByBusiness[(int)$row['business_id']] = true;
        }
    }

    $coverByBusiness = [];
    if ($ids !== [] && mobile_gallery_table_exists($pdo)) {
        $placeholders = implode(',', array_fill(0, count($ids), '?'));
        $coverStmt = $pdo->prepare("
            SELECT bp.*
            FROM business_photos bp
            INNER JOIN (
                SELECT business_id, MAX(id) AS id
                FROM business_photos
                WHERE business_id IN ($placeholders)
                  AND status = 'active'
                  AND is_visible = 1
                  AND is_cover = 1
                GROUP BY business_id
            ) picked ON picked.id = bp.id
        ");
        $coverStmt->execute($ids);
        foreach ($coverStmt->fetchAll() as $coverRow) {
            $coverByBusiness[(int)$coverRow['business_id']] = mobile_gallery_item($coverRow);
        }
    }

    // ── Satırları SalonSummary.fromJson() uyumlu formata dönüştür ─────────────
    $items = [];
    foreach ($rows as $row) {
        $images   = mobile_images($row['images_json'] ?? null);
        $coverItem = $coverByBusiness[(int)$row['id']] ?? null;
        $coverUrl = $coverItem['medium_url'] ?? $coverItem['large_url'] ?? $coverItem['url'] ?? $images['cover_image_url'];
        $minPrice = $row['min_price'] !== null && (int)$row['min_price'] > 0
            ? (int)$row['min_price']
            : (($row['service_min_price'] ?? null) !== null
                ? (int)$row['service_min_price']
                : null);
        $maxPrice = $row['max_price'] !== null ? (int)$row['max_price'] : null;
        $bizId    = (int)$row['id'];
        $isOpen   = !empty($openNowByBusiness[$bizId]);
        $badges   = $isOpen ? ['Açık'] : [];

        $items[] = [
            'id'                  => (string)$row['id'],
            'slug'                => (string)($row['slug'] ?? ''),
            'name'                => (string)($row['name'] ?? ''),
            'description'         => $row['about']        ?? null,
            'city'                => $row['city']          ?? null,
            'district'            => $row['district']      ?? null,
            'address'             => $row['address_line']  ?? null,
            'latitude'            => _wbFavoriteValidCoord($row['latitude'] ?? null),
            'longitude'           => _wbFavoriteValidCoord($row['longitude'] ?? null),
            'has_location'         => _wbFavoriteHasLocation($row['latitude'] ?? null, $row['longitude'] ?? null),
            'cover_image_url'     => $coverUrl,
            'image_url'           => $coverUrl,
            'logo_url'            => $images['logo_url'],
            'rating'              => ($row['avg_rating'] ?? null) !== null ? (float)$row['avg_rating'] : null,
            'review_count'        => (int)($row['review_count'] ?? 0),
            'price_level'         => $minPrice !== null
                ? ['min' => $minPrice, 'max' => $maxPrice]
                : null,
            'deposit_required'    => false,
            'deposit_amount'      => null,
            'is_open_now'         => $isOpen,
            'next_available_text' => null,
            'badges'              => $badges,
            'category_slugs'      => mobile_category_slugs_from_type($row['type'] ?? null),
        ];
        if ($hasDistance && $row['distance_km'] !== null && _wbFavoriteHasLocation($row['latitude'] ?? null, $row['longitude'] ?? null)) {
            $items[count($items) - 1]['distance_km'] = round((float)$row['distance_km'], 2);
        }
    }

    wb_ok(['items' => $items]);

} catch (Throwable $e) {
    error_log('[mobile/customer/favorites.php] ' . $e->getMessage());
    wb_err('Favoriler alınamadı', 500, 'internal_error');
}

function _wbFavoriteValidCoord($v): ?float {
    if ($v === null || $v === '') return null;
    $f = (float)$v;
    if (abs($f) < 0.0001) return null;
    return $f;
}

function _wbFavoriteHasLocation($lat, $lng): bool {
    return _wbFavoriteValidCoord($lat) !== null && _wbFavoriteValidCoord($lng) !== null;
}
