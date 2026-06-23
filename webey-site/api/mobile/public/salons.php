<?php
declare(strict_types=1);

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../business/_gallery_helpers.php';
require_once __DIR__ . '/../_category_helpers.php';
require_once __DIR__ . '/../_business_visibility.php';
require_once __DIR__ . '/../_campaigns.php';

wb_method('GET');

$q = (string)mobile_param('q', '');
$city = (string)mobile_param('city', '');
$district = (string)mobile_param('district', '');
$category = (string)mobile_param('category', '');
$lat = mobile_param('lat', null);
$lng = mobile_param('lng', null);
$availableToday = mobile_bool_param('available_today', false);
$depositFilter = (string)mobile_param('deposit', 'any');
$isMapView = (string)mobile_param('view', '') === 'map';
$page = max(1, mobile_int_param('page', 1) ?? 1);
// Harita görünümü viewport'taki tüm pinleri tek istekte ister; liste 20/50 ile sınırlı kalır.
$limit = $isMapView
    ? mobile_limit(mobile_param('limit', 200), 200, 300)
    : mobile_limit(mobile_param('limit', 20), 20, 50);
$offset = ($page - 1) * $limit;

$where = ["b.status = 'active'", 'b.onboarding_completed = 1'];
$params = [];

if ($q !== '') {
    $like = '%' . $q . '%';
    $where[] = '(b.name LIKE ? OR b.about LIKE ? OR b.city LIKE ? OR b.district LIKE ? OR b.neighborhood LIKE ? OR b.address_line LIKE ?)';
    array_push($params, $like, $like, $like, $like, $like, $like);
}

if ($city !== '') {
    $where[] = 'b.city = ?';
    $params[] = $city;
}

if ($district !== '') {
    $where[] = 'b.district = ?';
    $params[] = $district;
}

// Kategori filtresi: eski `type` eslesmesi + (migration sonrasi) gercek hizmet
// kategorileri ve isletmenin onboarding'de sectigi ana kategoriler.
if ($category !== '') {
    $categoryLike = '%' . $category . '%';
    $catClauses = ['b.type = ?', 'b.type LIKE ?'];
    $catParams = [$category, $categoryLike];

    if (mobile_category_table_exists($pdo)
        && mobile_table_has_column($pdo, 'services', 'category_id')) {
        $svcActive = mobile_table_has_column($pdo, 'services', 'is_active')
            ? ' AND s2.is_active = 1'
            : '';
        $catClauses[] = 'EXISTS (
            SELECT 1 FROM services s2
            JOIN service_categories sc2 ON sc2.id = s2.category_id
            WHERE s2.business_id = b.id AND sc2.slug = ?' . $svcActive . '
        )';
        $catParams[] = $category;

        if (mobile_business_categories_table_exists($pdo)) {
            $catClauses[] = 'EXISTS (
                SELECT 1 FROM business_categories bc2
                JOIN service_categories sc3 ON sc3.id = bc2.category_id
                WHERE bc2.business_id = b.id AND sc3.slug = ?
            )';
            $catParams[] = $category;
        }
    }

    $where[] = '(' . implode(' OR ', $catClauses) . ')';
    foreach ($catParams as $catParam) {
        $params[] = $catParam;
    }
}

$latValue = is_numeric($lat) ? (float)$lat : null;
$lngValue = is_numeric($lng) ? (float)$lng : null;
$hasDistance = $latValue !== null && $lngValue !== null;

if ($isMapView) {
    // Koordinatı olmayan (veya 0,0 "Null Island") salonlar harita yanıtına girmez.
    $where[] = 'b.latitude IS NOT NULL AND b.longitude IS NOT NULL AND NOT (ABS(b.latitude) < 0.0001 AND ABS(b.longitude) < 0.0001)';

    // Viewport bounds filtresi (north/south/east/west) — dört değer de sayısal olmalı.
    $bNorth = mobile_param('north', null);
    $bSouth = mobile_param('south', null);
    $bEast  = mobile_param('east', null);
    $bWest  = mobile_param('west', null);
    if (is_numeric($bNorth) && is_numeric($bSouth) && is_numeric($bEast) && is_numeric($bWest)) {
        $where[] = 'b.latitude BETWEEN ? AND ? AND b.longitude BETWEEN ? AND ?';
        array_push(
            $params,
            min((float)$bSouth, (float)$bNorth),
            max((float)$bSouth, (float)$bNorth),
            min((float)$bWest, (float)$bEast),
            max((float)$bWest, (float)$bEast)
        );
    }

    // radius_km: merkez lat/lng verilmişse yaklaşık bounding box (index dostu).
    $radiusKm = mobile_param('radius_km', null);
    if ($hasDistance && is_numeric($radiusKm) && (float)$radiusKm > 0) {
        $r = min(500.0, (float)$radiusKm);
        $latDelta = $r / 111.0;
        $lngDelta = $r / (111.0 * max(0.1, cos(deg2rad($latValue))));
        $where[] = 'b.latitude BETWEEN ? AND ? AND b.longitude BETWEEN ? AND ?';
        array_push(
            $params,
            $latValue - $latDelta,
            $latValue + $latDelta,
            $lngValue - $lngDelta,
            $lngValue + $lngDelta
        );
    }
}

if ($availableToday) {
    // TODO(mobile): Uygunluk randevu ve personel takvimiyle hesaplanmalı; Faz 1'de sadece açık işletme filtresi uygulanıyor.
    $today = mobile_day_key();
    $nowTime = date('H:i:s');
    $where[] = 'EXISTS (
        SELECT 1
        FROM business_hours bh
        WHERE bh.business_id = b.id
          AND bh.day = ?
          AND bh.is_open = 1
          AND bh.open_time <= ?
          AND bh.close_time >= ?
    )';
    array_push($params, $today, $nowTime, $nowTime);
}

$distanceSelect = $hasDistance
    ? ', (6371 * ACOS(LEAST(1, COS(RADIANS(?)) * COS(RADIANS(b.latitude)) * COS(RADIANS(b.longitude) - RADIANS(?)) + SIN(RADIANS(?)) * SIN(RADIANS(b.latitude))))) AS distance_km'
    : ', NULL AS distance_km';
$distanceParams = $hasDistance ? [$latValue, $lngValue, $latValue] : [];
$orderTail = $hasDistance ? 'distance_km ASC, b.updated_at DESC' : 'b.updated_at DESC, b.id DESC';
$orderBy = wb_business_visibility_order_prefix_sql($pdo) . $orderTail;

$hasDepositRequired = mobile_table_has_column($pdo, 'businesses', 'deposit_required');
$hasDepositAmount   = mobile_table_has_column($pdo, 'businesses', 'deposit_amount');
$hasDepositPolicies = mobile_table_has_column($pdo, 'deposit_policies', 'business_id');
// Gerçek puan/yorum sayısı reviews tablosundan (varsa) hesaplanır.
$hasReviews         = mobile_table_has_column($pdo, 'reviews', 'id');
$hasReviewStaffCol  = $hasReviews && mobile_table_has_column($pdo, 'reviews', 'staff_id');
$hasReviewStatusCol = $hasReviews && mobile_table_has_column($pdo, 'reviews', 'status');
$reviewStatusSql    = $hasReviewStatusCol ? " AND r.status = 'active'" : '';
$businessReviewSql  = $hasReviewStaffCol ? ' AND (r.staff_id IS NULL OR r.staff_id = 0)' : '';
$reviewSelectSql    = $hasReviews
    ? ", (SELECT ROUND(AVG(r.rating), 1) FROM reviews r WHERE r.business_id = b.id{$reviewStatusSql}{$businessReviewSql}) AS avg_rating"
    . ", (SELECT COUNT(*) FROM reviews r WHERE r.business_id = b.id{$reviewStatusSql}{$businessReviewSql}) AS review_count"
    : ', NULL AS avg_rating, 0 AS review_count';
$depositSelectSql   = ($hasDepositRequired ? ', b.deposit_required' : '')
                    . ($hasDepositAmount   ? ', b.deposit_amount'   : '')
                    . ($hasDepositPolicies ? ', dp.rate_pct AS deposit_rate_pct, dp.per_service AS deposit_per_service, dp.cancel_policy AS deposit_cancel_policy' : '');
$depositJoinSql = $hasDepositPolicies ? 'LEFT JOIN deposit_policies dp ON dp.business_id = b.id' : '';
$visibilityJoinSql = wb_business_visibility_join_sql($pdo);

if ($hasDepositPolicies && $depositFilter === 'required') {
    $where[] = 'COALESCE(dp.rate_pct, 0) > 0';
} elseif ($hasDepositPolicies && $depositFilter === 'none') {
    $where[] = '(dp.business_id IS NULL OR COALESCE(dp.rate_pct, 0) <= 0)';
}

// Kampanya filtresi: yalnız "şu an geçerli" (tarih+gün+saat) aktif kampanyası
// olan salonlar. campaign_type=weekday|hourly, discount_kind=percent|fixed alt
// filtreleri opsiyonel. Tablo yoksa filtre sessizce yok sayılır.
$campaignFilter = mobile_bool_param('campaign', false);
$campaignType   = (string)mobile_param('campaign_type', '');
$campaignKind   = (string)mobile_param('discount_kind', '');
$campaignsReady = wb_campaign_tables_ready($pdo);
if ($campaignFilter && $campaignsReady) {
    $isoDow = (int)(new DateTimeImmutable('now', new DateTimeZone('Europe/Istanbul')))->format('N');
    $cSql = "EXISTS (SELECT 1 FROM business_campaigns c
                WHERE c.business_id = b.id AND c.status = 'active'
                  AND (c.start_date IS NULL OR c.start_date <= CURDATE())
                  AND (c.end_date IS NULL OR c.end_date >= CURDATE())
                  AND (c.days_of_week IS NULL OR c.days_of_week = '' OR FIND_IN_SET(?, c.days_of_week))
                  AND (c.start_time IS NULL OR c.end_time IS NULL OR CURTIME() BETWEEN c.start_time AND c.end_time)";
    $cParams = [$isoDow];
    if (in_array($campaignType, ['weekday', 'hourly', 'general'], true)) {
        $cSql .= ' AND c.condition_type = ?';
        $cParams[] = $campaignType;
    }
    if (in_array($campaignKind, ['percent', 'fixed'], true)) {
        $cSql .= ' AND c.discount_kind = ?';
        $cParams[] = $campaignKind;
    }
    $cSql .= ')';
    $where[] = $cSql;
    foreach ($cParams as $cp) {
        $params[] = $cp;
    }
}

$whereSql = implode(' AND ', $where);
$visibilityWhereSql = wb_business_visibility_where_sql($pdo);

try {
    $countStmt = $pdo->prepare("SELECT COUNT(*) FROM businesses b $depositJoinSql $visibilityJoinSql WHERE $whereSql $visibilityWhereSql");
    $countStmt->execute($params);
    $total = (int)$countStmt->fetchColumn();

    $stmt = $pdo->prepare("
        SELECT b.id, b.slug, b.name, b.about, b.city, b.district, b.address_line,
               b.images_json, b.min_price, b.max_price, b.type, b.latitude, b.longitude,
               (SELECT MIN(s.price) FROM services s WHERE s.business_id = b.id AND s.price IS NOT NULL AND s.price > 0) AS service_min_price
               $reviewSelectSql
               $depositSelectSql
               " . wb_business_visibility_select_sql($pdo) . "
               $distanceSelect
        FROM businesses b
        $depositJoinSql
        $visibilityJoinSql
        WHERE $whereSql $visibilityWhereSql
        ORDER BY $orderBy
        LIMIT ? OFFSET ?
    ");
    $stmt->execute(array_merge($distanceParams, $params, [$limit, $offset]));
    $rows = $stmt->fetchAll();

    $ids = array_map(static fn(array $row): int => (int)$row['id'], $rows);
    $openNowByBusiness = [];
    if ($ids !== []) {
        $placeholders = implode(',', array_fill(0, count($ids), '?'));
        $today = mobile_day_key();
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

    // Kampanya vitrin verisi (tüm listelenen salonlar için, tek sorguda)
    $campaignByBusiness = $campaignsReady
        ? wb_campaign_display_for_businesses($pdo, $ids)
        : [];

    $items = [];
    foreach ($rows as $row) {
        $images = mobile_images($row['images_json'] ?? null);
        $coverItem = $coverByBusiness[(int)$row['id']] ?? null;
        $coverUrl = $coverItem['medium_url'] ?? $coverItem['large_url'] ?? $coverItem['url'] ?? $images['cover_image_url'];
        $minPrice = $row['min_price'] !== null && (int)$row['min_price'] > 0
            ? (int)$row['min_price']
            : ($row['service_min_price'] !== null ? (int)$row['service_min_price'] : null);
        $maxPrice = $row['max_price'] !== null ? (int)$row['max_price'] : null;
        $badges = [];
        if (!empty($openNowByBusiness[(int)$row['id']])) {
            $badges[] = 'Açık';
        }
        $visibility = wb_business_visibility_from_row($row);
        if ($visibility['is_boosted'] && $visibility['boost_badge'] !== null) {
            $badges[] = (string)$visibility['boost_badge'];
        }

        $policyRate = $hasDepositPolicies && ($row['deposit_rate_pct'] ?? null) !== null ? (int)$row['deposit_rate_pct'] : null;
        $policyRequired = $policyRate !== null ? $policyRate > 0 : ($hasDepositRequired ? (bool)$row['deposit_required'] : false);
        $depositLabel = $policyRequired
            ? ($policyRate !== null && $policyRate > 0 ? '%' . $policyRate . ' kapora' : 'Kapora var')
            : 'Kapora yok';

        $item = [
            'id' => (string)$row['id'],
            'slug' => (string)($row['slug'] ?? ''),
            'name' => (string)($row['name'] ?? ''),
            'description' => $row['about'] ?? null,
            'city' => $row['city'] ?? null,
            'district' => $row['district'] ?? null,
            'address' => $row['address_line'] ?? null,
            'latitude' => _wbSalonValidLat($row['latitude']),
            'longitude' => _wbSalonValidLng($row['longitude']),
            'has_location' => _wbSalonHasLocation($row['latitude'] ?? null, $row['longitude'] ?? null),
            'cover_image_url' => $coverUrl,
            'logo_url' => $images['logo_url'],
            'rating' => ($row['avg_rating'] ?? null) !== null ? (float)$row['avg_rating'] : null,
            'review_count' => (int)($row['review_count'] ?? 0),
            'price_level' => $minPrice !== null ? ['min' => $minPrice, 'max' => $maxPrice] : null,
            'deposit_required' => $policyRequired,
            'deposit_amount'   => ($hasDepositAmount && $row['deposit_amount'] !== null)
                ? (float)$row['deposit_amount']
                : null,
            'deposit_rate_pct' => $policyRate,
            'deposit_per_service' => $hasDepositPolicies ? (bool)($row['deposit_per_service'] ?? false) : false,
            'cancel_policy' => $hasDepositPolicies ? ($row['deposit_cancel_policy'] ?? null) : null,
            'deposit_label' => $depositLabel,
            'is_open_now' => !empty($openNowByBusiness[(int)$row['id']]),
            'next_available_text' => null,
            'badges' => $badges,
            'category_slugs' => mobile_category_slugs_from_type($row['type'] ?? null),
            'is_boosted' => $visibility['is_boosted'],
            'boost_badge' => $visibility['boost_badge'],
            'boost_ends_at' => $visibility['boost_ends_at'],
            'subscription_status' => $visibility['subscription_status'],
            'visibility_status' => $visibility['visibility_status'],
            'profile_quality_score' => $visibility['profile_quality_score'],
            'campaign' => $campaignByBusiness[(int)$row['id']] ?? null,
            'has_campaign' => isset($campaignByBusiness[(int)$row['id']]),
        ];

        if ($hasDistance && $row['distance_km'] !== null) {
            $item['distance_km'] = round((float)$row['distance_km'], 2);
        }

        $items[] = $item;
    }

    $payload = [
        'items' => $items,
        'pagination' => [
            'page' => $page,
            'limit' => $limit,
            'total' => $total,
            'has_more' => ($offset + count($items)) < $total,
        ],
    ];

    if ($isMapView) {
        $bounds = null;
        foreach ($items as $item) {
            $iLat = $item['latitude'];
            $iLng = $item['longitude'];
            if ($iLat === null || $iLng === null) continue;
            if ($bounds === null) {
                $bounds = ['north' => $iLat, 'south' => $iLat, 'east' => $iLng, 'west' => $iLng];
            } else {
                $bounds['north'] = max($bounds['north'], $iLat);
                $bounds['south'] = min($bounds['south'], $iLat);
                $bounds['east']  = max($bounds['east'], $iLng);
                $bounds['west']  = min($bounds['west'], $iLng);
            }
        }
        $payload['bounds'] = $bounds;
    }

    wb_ok($payload);
} catch (Throwable $e) {
    error_log('[mobile/public/salons.php] ' . $e->getMessage());
    wb_err('Salonlar alınamadı', 500, 'internal_error');
}

/** 0,0 ya da null lat -> null. */
function _wbSalonValidLat($v): ?float {
    if ($v === null || $v === '') return null;
    $f = (float)$v;
    if (abs($f) < 0.0001) return null;
    return $f;
}
function _wbSalonValidLng($v): ?float {
    if ($v === null || $v === '') return null;
    $f = (float)$v;
    if (abs($f) < 0.0001) return null;
    return $f;
}
function _wbSalonHasLocation($lat, $lng): bool {
    return _wbSalonValidLat($lat) !== null && _wbSalonValidLng($lng) !== null;
}
