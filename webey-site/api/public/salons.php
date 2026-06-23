<?php
declare(strict_types=1);
/**
 * api/public/salons.php
 * GET ?city=&district=&sort=newest|rating|price_asc|price_desc|name&min_rating=4&page=1&limit=18&q=&open_now=1
 */

require_once __DIR__ . '/../_public_bootstrap.php';
header('Cache-Control: public, max-age=60');
wb_method('GET');

$page      = max(1, (int)($_GET['page'] ?? 1));
$limit     = min(max(1, (int)($_GET['limit'] ?? 18)), 100);
$offset    = ($page - 1) * $limit;
$city      = trim((string)($_GET['city'] ?? ''));
$district  = trim((string)($_GET['district'] ?? ''));
$q         = trim((string)($_GET['q'] ?? ''));
$sort      = trim((string)($_GET['sort'] ?? 'newest'));
$minRating = round(max(0.0, min(5.0, (float)($_GET['min_rating'] ?? 0))), 1);
$maxPrice  = isset($_GET['max_price']) ? (int)$_GET['max_price'] : null;
$minPrice  = isset($_GET['min_price']) ? (int)$_GET['min_price'] : null;
$openNow   = !empty($_GET['open_now']);

$sortMap = [
    'newest'     => 'b.updated_at DESC',
    'rating'     => 'b.updated_at DESC',
    'price_asc'  => 'b.min_price ASC, b.updated_at DESC',
    'price_desc' => 'b.min_price DESC, b.updated_at DESC',
    'name'       => 'b.name ASC',
];
$orderBy = $sortMap[$sort] ?? $sortMap['newest'];

$where  = ["b.status = 'active'", 'b.onboarding_completed = 1'];
$params = [];

if ($city !== '') {
    $where[]  = 'b.city = ?';
    $params[] = $city;
}
if ($district !== '') {
    $where[]  = 'b.district = ?';
    $params[] = $district;
}
if ($q !== '') {
    $like = '%' . $q . '%';
    $where[] = '(b.name LIKE ? OR b.about LIKE ? OR b.district LIKE ? OR b.neighborhood LIKE ?)';
    array_push($params, $like, $like, $like, $like);
}
if ($maxPrice !== null) {
    $where[]  = '(b.min_price IS NULL OR b.min_price <= ?)';
    $params[] = $maxPrice;
}
if ($minPrice !== null) {
    $where[]  = '(b.min_price >= ?)';
    $params[] = $minPrice;
}
if ($openNow) {
    $dayMap = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];
    $today = $dayMap[(int)date('w')] ?? 'sun';
    $nowTime = date('H:i:s');
    $where[] = '
        EXISTS (
            SELECT 1
            FROM business_hours bh
            WHERE bh.business_id = b.id
              AND bh.day = ?
              AND bh.is_open = 1
              AND bh.open_time <= ?
              AND bh.close_time >= ?
        )
    ';
    array_push($params, $today, $nowTime, $nowTime);
}

$whereSql = implode(' AND ', $where);

try {
    $countStmt = $pdo->prepare("SELECT COUNT(*) FROM businesses b WHERE $whereSql");
    $countStmt->execute($params);
    $total = (int)$countStmt->fetchColumn();

    $stmt = $pdo->prepare("
        SELECT b.id, b.name, b.slug, b.city, b.district, b.address_line,
               b.images_json, b.about, b.min_price, b.max_price,
               b.latitude, b.longitude, b.map_url
        FROM businesses b
        WHERE $whereSql
        ORDER BY $orderBy
        LIMIT ? OFFSET ?
    ");
    $stmt->execute(array_merge($params, [$limit, $offset]));
    $rows = $stmt->fetchAll();

    $items = [];
    foreach ($rows as $row) {
        $coverUrl = null;
        $images = [];
        $gallery = [];

        if (!empty($row['images_json'])) {
            $img = json_decode((string)$row['images_json'], true) ?? [];
            if (is_array($img)) {
                $coverOpt = is_array($img['cover_opt'] ?? null) ? ($img['cover_opt'][0] ?? null) : null;
                $coverOrig = is_array($img['cover'] ?? null) ? ($img['cover'][0] ?? null) : ($img['cover'] ?? null);
                $coverUrl = is_string($coverOpt) && $coverOpt !== '' ? $coverOpt : $coverOrig;
                if ($coverOrig) {
                    $images['cover'] = $coverOrig;
                }
                if ($coverUrl) {
                    $gallery[] = $coverUrl;
                }
                $salonItems = is_array($img['salon_opt'] ?? null) ? $img['salon_opt'] : (is_array($img['salon'] ?? null) ? $img['salon'] : []);
                $modelItems = is_array($img['model_opt'] ?? null) ? $img['model_opt'] : (is_array($img['model'] ?? null) ? $img['model'] : []);
                foreach ($salonItems as $url) {
                    if ($url && $url !== $coverUrl) {
                        $gallery[] = $url;
                    }
                }
                foreach ($modelItems as $url) {
                    if ($url && !in_array($url, $gallery, true)) {
                        $gallery[] = $url;
                    }
                }
            }
        }

        $items[] = [
            'id' => (string)$row['id'],
            'name' => (string)$row['name'],
            'slug' => (string)($row['slug'] ?? ''),
            'coverUrl' => $coverUrl,
            'images' => $images,
            'gallery' => $gallery,
            'avg_rating' => 0.0,
            'review_count' => 0,
            'min_price' => $row['min_price'] !== null ? (int)$row['min_price'] : null,
            'max_price' => $row['max_price'] !== null ? (int)$row['max_price'] : null,
            'loc' => [
                'city' => $row['city'],
                'district' => $row['district'],
                'address' => $row['address_line'],
                'latitude' => $row['latitude'] !== null ? (float)$row['latitude'] : null,
                'longitude' => $row['longitude'] !== null ? (float)$row['longitude'] : null,
            ],
            'map_url' => $row['map_url'] ?? null,
            'about' => $row['about'],
        ];
    }

    wb_ok(['data' => $items, 'items' => $items, 'meta' => wb_paginate($total, $page, $limit)]);
} catch (Throwable $e) {
    error_log('[salons.php] ' . $e->getMessage());
    wb_err('Veriler alinamadi', 500, 'internal_error');
}
