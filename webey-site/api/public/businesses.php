<?php
declare(strict_types=1);
/**
 * api/public/businesses.php
 * GET ?status=active&city=...&district=...&neighborhood=...&q=...&limit=100&page=1&mode=full|list|directory
 */

require_once __DIR__ . '/../_public_bootstrap.php';
header('Cache-Control: public, max-age=30');
wb_method('GET');

$mode = trim((string)($_GET['mode'] ?? 'full'));
if (!in_array($mode, ['full', 'list', 'directory'], true)) {
    $mode = 'full';
}

$page         = max((int)($_GET['page'] ?? 1), 1);
$limitCap     = $mode === 'full' ? 200 : 100;
$limitDefault = $mode === 'directory' ? 100 : 60;
$limit        = min(max((int)($_GET['limit'] ?? $limitDefault), 1), $limitCap);
$offset       = ($page - 1) * $limit;
$status       = trim((string)($_GET['status'] ?? ''));
$city         = trim((string)($_GET['city'] ?? ''));
$district     = trim((string)($_GET['district'] ?? ''));
$neighborhood = trim((string)($_GET['neighborhood'] ?? ''));
$q            = trim((string)($_GET['q'] ?? ''));

$where  = ['b.onboarding_completed = 1'];
$params = [];

if ($status !== '') {
    $where[]  = 'b.status = ?';
    $params[] = $status;
}
if ($city !== '') {
    $where[]  = 'b.city = ?';
    $params[] = $city;
}
if ($district !== '') {
    $where[]  = 'b.district = ?';
    $params[] = $district;
}
if ($neighborhood !== '') {
    $where[]  = 'b.neighborhood = ?';
    $params[] = $neighborhood;
}
if ($q !== '') {
    $like = '%' . $q . '%';
    $where[] = '(
        b.name LIKE ?
        OR b.type LIKE ?
        OR b.city LIKE ?
        OR b.district LIKE ?
        OR b.neighborhood LIKE ?
        OR EXISTS (
            SELECT 1
            FROM services svc
            WHERE svc.business_id = b.id AND svc.name LIKE ?
        )
    )';
    array_push($params, $like, $like, $like, $like, $like, $like);
}

$whereSql = implode(' AND ', $where);

$select = [
    'b.id',
    'b.name',
    'b.slug',
    'b.type',
    'b.status',
    'b.city',
    'b.district',
    'b.neighborhood',
    'b.address_line',
    'b.min_price',
    'b.images_json',
    'b.updated_at',
];

if ($mode === 'full') {
    $select[] = 'b.phone';
}

$dayToIdx = ['sun' => 0, 'mon' => 1, 'tue' => 2, 'wed' => 3, 'thu' => 4, 'fri' => 5, 'sat' => 6];

$extractMedia = static function (?string $json, bool $includeImages, bool $includeGallery): array {
    $media = [
        'coverUrl' => null,
        'images' => $includeImages ? ['cover' => [], 'salon' => [], 'model' => []] : [],
        'gallery' => $includeGallery ? [] : [],
    ];
    if (!$json) {
        return $media;
    }

    $raw = json_decode($json, true);
    if (!is_array($raw)) {
        return $media;
    }

    foreach (['cover', 'salon', 'model'] as $bucket) {
        $optKey = $bucket . '_opt';
        $optItems = $raw[$optKey] ?? [];
        if (is_string($optItems) && $optItems !== '') {
            $optItems = [$optItems];
        }
        if (!is_array($optItems)) {
            $optItems = [];
        }

        $items = $raw[$bucket] ?? [];
        if (is_string($items) && $items !== '') {
            $items = [$items];
        }
        if (!is_array($items)) {
            $items = [];
        }

        $normalized = [];
        foreach ($items as $item) {
            if (is_string($item) && $item !== '') {
                $normalized[] = $item;
                continue;
            }
            if (is_array($item)) {
                $url = $item['url'] ?? $item['src'] ?? null;
                if (is_string($url) && $url !== '') {
                    $normalized[] = $url;
                }
            }
        }

        $preferred = [];
        foreach ($optItems as $item) {
            if (is_string($item) && $item !== '') {
                $preferred[] = $item;
            }
        }
        if ($preferred === []) {
            $preferred = $normalized;
        }

        if ($bucket === 'cover') {
            $media['coverUrl'] = $preferred[0] ?? $normalized[0] ?? $media['coverUrl'];
        }

        if ($includeImages) {
            $media['images'][$bucket] = $normalized;
        }

        if ($includeGallery) {
            foreach ($preferred as $url) {
                if (!in_array($url, $media['gallery'], true)) {
                    $media['gallery'][] = $url;
                }
            }
        }
    }

    if ($includeGallery && $media['coverUrl'] && !in_array($media['coverUrl'], $media['gallery'], true)) {
        array_unshift($media['gallery'], $media['coverUrl']);
    }

    return $media;
};

try {
    $stmt = $pdo->prepare('
        SELECT ' . implode(', ', $select) . '
        FROM businesses b
        WHERE ' . $whereSql . '
        ORDER BY b.updated_at DESC, b.id DESC
        LIMIT ? OFFSET ?
    ');
    $stmt->execute(array_merge($params, [$limit, $offset]));
    $rows = $stmt->fetchAll();
} catch (Throwable $e) {
    error_log('[businesses.php] ' . $e->getMessage());
    wb_err('Veriler alinamadi', 500, 'internal_error');
}

if (!$rows) {
    wb_ok([]);
}

$ids = array_map(static fn(array $row): int => (int)$row['id'], $rows);
$placeholders = implode(',', array_fill(0, count($ids), '?'));

$servicesByBiz = [];
$hoursByBiz = [];

if ($mode !== 'directory') {
    try {
        $serviceStmt = $pdo->prepare("
            SELECT business_id, name, price
            FROM services
            WHERE business_id IN ($placeholders) AND price > 0
            ORDER BY business_id ASC, price ASC, id ASC
        ");
        $serviceStmt->execute($ids);
        foreach ($serviceStmt->fetchAll() as $row) {
            $bid = (string)$row['business_id'];
            $servicesByBiz[$bid][] = [
                'name' => (string)$row['name'],
                'price' => (float)$row['price'],
            ];
        }
    } catch (Throwable $ignored) {
    }

    try {
        $hoursStmt = $pdo->prepare("
            SELECT business_id, day, is_open, open_time, close_time
            FROM business_hours
            WHERE business_id IN ($placeholders)
        ");
        $hoursStmt->execute($ids);
        foreach ($hoursStmt->fetchAll() as $row) {
            $idx = $dayToIdx[$row['day']] ?? null;
            if ($idx === null) {
                continue;
            }
            $bid = (string)$row['business_id'];
            $isOpen = (bool)$row['is_open'];
            $from = ($isOpen && !empty($row['open_time'])) ? substr((string)$row['open_time'], 0, 5) : null;
            $to = ($isOpen && !empty($row['close_time'])) ? substr((string)$row['close_time'], 0, 5) : null;
            $hoursByBiz[$bid][$idx] = $isOpen && $from
                ? ['open' => true, 'slots' => [['from' => $from, 'to' => ($to ?: '00:00')]]]
                : ['open' => false, 'slots' => []];
        }
    } catch (Throwable $ignored) {
    }
}

if ($mode === 'directory') {
    try {
        $serviceStmt = $pdo->prepare("
            SELECT business_id, name
            FROM services
            WHERE business_id IN ($placeholders)
            ORDER BY business_id ASC, name ASC
        ");
        $serviceStmt->execute($ids);
        foreach ($serviceStmt->fetchAll() as $row) {
            $bid = (string)$row['business_id'];
            $servicesByBiz[$bid][] = ['name' => (string)$row['name']];
        }
    } catch (Throwable $ignored) {
    }
}

$out = [];
foreach ($rows as $row) {
    $bid = (string)$row['id'];
    $services = $servicesByBiz[$bid] ?? [];
    $media = $extractMedia(
        $row['images_json'] ?? null,
        $mode !== 'directory',
        $mode === 'list'
    );

    if ($mode === 'directory') {
        $out[] = [
            'id' => $bid,
            'uid' => $bid,
            'businessId' => $bid,
            'name' => (string)($row['name'] ?? ''),
            'slug' => (string)($row['slug'] ?? ''),
            'coverUrl' => $media['coverUrl'],
            'logoUrl' => $media['coverUrl'],
            'services' => $services,
            'minPrice' => $row['min_price'] !== null ? (int)$row['min_price'] : null,
            'businessLocation' => [
                'city' => $row['city'] ?? '',
                'district' => $row['district'] ?? '',
                'neighborhood' => $row['neighborhood'] ?? '',
                'province' => $row['city'] ?? '',
                'addressLine' => $row['address_line'] ?? '',
            ],
            'updatedAt' => $row['updated_at'] ?? null,
        ];
        continue;
    }

    $hours = $hoursByBiz[$bid] ?? (object)[];
    $minPrice = $row['min_price'] !== null ? (int)$row['min_price'] : null;
    if ($minPrice === null && $services !== []) {
        $minPrice = (int)min(array_column($services, 'price'));
    }

    $item = [
        'id' => $bid,
        'uid' => $bid,
        'businessId' => $bid,
        'name' => (string)($row['name'] ?? ''),
        'slug' => (string)($row['slug'] ?? ''),
        'category' => (string)($row['type'] ?? ''),
        'status' => (string)($row['status'] ?? ''),
        'coverUrl' => $media['coverUrl'],
        'logoUrl' => $media['coverUrl'],
        'images' => $media['images'],
        'gallery' => $media['gallery'],
        'services' => $services,
        'minPrice' => $minPrice,
        'min_price' => $minPrice,
        'city' => (string)($row['city'] ?? ''),
        'district' => (string)($row['district'] ?? ''),
        'neighborhood' => (string)($row['neighborhood'] ?? ''),
        'address' => (string)($row['address_line'] ?? ''),
        'businessLocation' => [
            'city' => $row['city'] ?? '',
            'district' => $row['district'] ?? '',
            'neighborhood' => $row['neighborhood'] ?? '',
            'province' => $row['city'] ?? '',
            'addressLine' => $row['address_line'] ?? '',
        ],
        'workingHours' => $hours ?: (object)[],
        'hours' => $hours ?: (object)[],
        'updatedAt' => $row['updated_at'] ?? null,
        'updated_at' => $row['updated_at'] ?? null,
    ];

    if ($mode === 'full') {
        $item['phone'] = (string)($row['phone'] ?? '');
    }

    $out[] = $item;
}

wb_ok($out);
