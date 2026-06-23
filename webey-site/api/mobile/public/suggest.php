<?php
declare(strict_types=1);

require_once __DIR__ . '/../_bootstrap.php';

wb_method('GET');

$q = (string)mobile_param('q', '');
if (mb_strlen($q) < 1) {
    wb_ok(['items' => []]);
}

$like = '%' . $q . '%';
$items = [];

try {
    $salonStmt = $pdo->prepare("
        SELECT id, slug, name, city, district
        FROM businesses
        WHERE status = 'active'
          AND onboarding_completed = 1
          AND name LIKE ?
        ORDER BY updated_at DESC, id DESC
        LIMIT 6
    ");
    $salonStmt->execute([$like]);
    foreach ($salonStmt->fetchAll() as $row) {
        $items[] = [
            'type' => 'salon',
            'title' => (string)$row['name'],
            'subtitle' => trim((string)($row['district'] ?? '') . ' / ' . (string)($row['city'] ?? ''), ' /'),
            'id' => (string)$row['id'],
            'slug' => (string)($row['slug'] ?? ''),
        ];
    }

    $districtStmt = $pdo->prepare("
        SELECT DISTINCT city, district
        FROM businesses
        WHERE status = 'active'
          AND onboarding_completed = 1
          AND (city LIKE ? OR district LIKE ?)
          AND district IS NOT NULL
          AND district <> ''
        ORDER BY city ASC, district ASC
        LIMIT 5
    ");
    $districtStmt->execute([$like, $like]);
    foreach ($districtStmt->fetchAll() as $row) {
        $items[] = [
            'type' => 'district',
            'title' => (string)$row['district'],
            'subtitle' => (string)($row['city'] ?? ''),
            'id' => null,
            'slug' => null,
        ];
    }

    $serviceStmt = $pdo->prepare("
        SELECT DISTINCT s.name
        FROM services s
        INNER JOIN businesses b ON b.id = s.business_id
        WHERE b.status = 'active'
          AND b.onboarding_completed = 1
          AND s.name LIKE ?
        ORDER BY s.name ASC
        LIMIT 6
    ");
    $serviceStmt->execute([$like]);
    foreach ($serviceStmt->fetchAll() as $row) {
        $items[] = [
            'type' => 'service',
            'title' => (string)$row['name'],
            'subtitle' => 'Hizmet',
            'id' => null,
            'slug' => null,
        ];
    }

    foreach (mobile_categories() as $category) {
        $haystack = mb_strtolower($category['slug'] . ' ' . $category['title'] . ' ' . $category['subtitle']);
        if (str_contains($haystack, mb_strtolower($q))) {
            $items[] = [
                'type' => 'category',
                'title' => $category['title'],
                'subtitle' => $category['subtitle'],
                'id' => $category['id'],
                'slug' => $category['slug'],
            ];
        }
    }

    wb_ok(['items' => array_slice($items, 0, 20)]);
} catch (Throwable $e) {
    error_log('[mobile/public/suggest.php] ' . $e->getMessage());
    wb_err('Öneriler alınamadı', 500, 'internal_error');
}
