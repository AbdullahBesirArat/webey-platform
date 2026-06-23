<?php
declare(strict_types=1);
/**
 * api/mobile/business/service-save.php
 * POST - Token sahibi isletmenin hizmetini ekler/gunceller.
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';
require_once __DIR__ . '/_helpers.php';
require_once __DIR__ . '/../_category_helpers.php';

wb_method('POST');

$auth = mobile_auth($pdo, ['business', 'admin']);
$ctx = mobile_business_context($pdo, $auth);
$businessId = (int)$ctx['business_id'];
$body = wb_body();

$id = (int)($body['id'] ?? 0);
$name = mb_substr(trim((string)($body['name'] ?? '')), 0, 100);
$description = mb_substr(trim((string)($body['description'] ?? '')), 0, 2000);
$category = mb_substr(trim((string)($body['category'] ?? '')), 0, 80);
$durationMinutes = (int)($body['duration_minutes'] ?? $body['durationMin'] ?? 30);
$priceRaw = $body['price'] ?? null;
$price = ($priceRaw === null || $priceRaw === '') ? null : (float)$priceRaw;
$isActive = array_key_exists('is_active', $body) ? (bool)$body['is_active'] : true;
$sortOrder = (int)($body['sort_order'] ?? 0);
$categoryIdRaw = $body['category_id'] ?? null;
$categoryId = (is_numeric($categoryIdRaw) && (int)$categoryIdRaw > 0) ? (int)$categoryIdRaw : null;

if ($name === '') {
    wb_err('name zorunlu', 400, 'missing_name');
}
if ($priceRaw !== null && $priceRaw !== '' && !is_numeric($priceRaw)) {
    wb_err('price sayisal olmali', 422, 'invalid_price');
}
if ($price !== null && $price < 0) {
    wb_err('price 0 veya daha buyuk olmali', 422, 'invalid_price');
}
if (!in_array($durationMinutes, [15, 30, 45, 60], true)) {
    wb_err('duration_minutes 15, 30, 45 veya 60 olmali', 422, 'invalid_duration');
}

try {
    $columns = mobile_business_table_columns($pdo, 'services');
    $hasCategoryId = isset($columns['category_id']) && mobile_category_table_exists($pdo);

    // Kategori dogrulama: sistem (business_id=0) veya isletmenin kendi kategorisi olmali.
    if ($categoryId !== null && $hasCategoryId) {
        $catStmt = $pdo->prepare(
            'SELECT id, name FROM service_categories
             WHERE id = ? AND is_active = 1 AND business_id IN (0, ?)
             LIMIT 1'
        );
        $catStmt->execute([$categoryId, $businessId]);
        $catRow = $catStmt->fetch();
        if (!$catRow) {
            wb_err('Geçersiz kategori seçimi.', 422, 'invalid_category');
        }
        // Eski text alani fallback olarak senkron tutulur.
        if ($category === '') {
            $category = (string)$catRow['name'];
        }
    } elseif ($categoryId !== null) {
        // Migration calismadiysa id'yi sessizce yok say, text fallback yeterli.
        $categoryId = null;
    }

    $pdo->beginTransaction();

    if ($id > 0) {
        $check = $pdo->prepare('SELECT id FROM services WHERE id = ? AND business_id = ? LIMIT 1 FOR UPDATE');
        $check->execute([$id, $businessId]);
        if (!$check->fetch()) {
            $pdo->rollBack();
            wb_err('Hizmet bulunamadi', 404, 'service_not_found');
        }

        $fields = ['name = ?', 'price = ?', 'duration_min = ?'];
        $params = [$name, $price, $durationMinutes];

        if (isset($columns['description'])) {
            $fields[] = 'description = ?';
            $params[] = $description !== '' ? $description : null;
        }
        if (isset($columns['category'])) {
            $fields[] = 'category = ?';
            $params[] = $category !== '' ? $category : null;
        }
        if (isset($columns['category_id'])) {
            $fields[] = 'category_id = ?';
            $params[] = $categoryId;
        }
        if (isset($columns['is_active'])) {
            $fields[] = 'is_active = ?';
            $params[] = $isActive ? 1 : 0;
        }
        if (isset($columns['sort_order'])) {
            $fields[] = 'sort_order = ?';
            $params[] = $sortOrder;
        }

        $params[] = $id;
        $params[] = $businessId;
        $sql = 'UPDATE services SET ' . implode(', ', $fields) . ' WHERE id = ? AND business_id = ?';
        $pdo->prepare($sql)->execute($params);
    } else {
        $insertColumns = ['business_id', 'name', 'price', 'duration_min'];
        $placeholders = ['?', '?', '?', '?'];
        $params = [$businessId, $name, $price, $durationMinutes];

        if (isset($columns['description'])) {
            $insertColumns[] = 'description';
            $placeholders[] = '?';
            $params[] = $description !== '' ? $description : null;
        }
        if (isset($columns['category'])) {
            $insertColumns[] = 'category';
            $placeholders[] = '?';
            $params[] = $category !== '' ? $category : null;
        }
        if (isset($columns['category_id'])) {
            $insertColumns[] = 'category_id';
            $placeholders[] = '?';
            $params[] = $categoryId;
        }
        if (isset($columns['is_active'])) {
            $insertColumns[] = 'is_active';
            $placeholders[] = '?';
            $params[] = $isActive ? 1 : 0;
        }
        if (isset($columns['sort_order'])) {
            $insertColumns[] = 'sort_order';
            $placeholders[] = '?';
            $params[] = $sortOrder;
        }

        $sql = 'INSERT INTO services (`' . implode('`, `', $insertColumns) . '`) VALUES (' . implode(', ', $placeholders) . ')';
        $pdo->prepare($sql)->execute($params);
        $id = (int)$pdo->lastInsertId();
    }

    $hasDescription = isset($columns['description']);
    $hasCategory = isset($columns['category']);
    $hasActive = isset($columns['is_active']);
    $hasSort = isset($columns['sort_order']);
    $categoryJoin = $hasCategoryId ? 'LEFT JOIN service_categories sc ON sc.id = s.category_id' : '';
    $categorySelect = $hasCategoryId
        ? 's.category_id, sc.name AS category_resolved_name, sc.slug AS category_slug, sc.icon_key AS category_icon_key, sc.business_id AS category_owner'
        : 'NULL AS category_id, NULL AS category_resolved_name, NULL AS category_slug, NULL AS category_icon_key, NULL AS category_owner';
    $stmt = $pdo->prepare("
        SELECT
            s.id,
            s.name,
            s.price,
            s.duration_min,
            " . ($hasDescription ? 's.description' : 'NULL') . " AS description,
            " . ($hasCategory ? 's.category' : 'NULL') . " AS category,
            " . ($hasActive ? 's.is_active' : '1') . " AS is_active,
            " . ($hasSort ? 's.sort_order' : '0') . " AS sort_order,
            $categorySelect
        FROM services s
        $categoryJoin
        WHERE s.id = ? AND s.business_id = ?
        LIMIT 1
    ");
    $stmt->execute([$id, $businessId]);
    $service = $stmt->fetch();

    $pdo->commit();

    wb_ok([
        'saved' => true,
        'service' => mobile_business_service_item($service ?: [
            'id' => $id,
            'name' => $name,
            'price' => $price,
            'duration_min' => $durationMinutes,
        ]),
    ]);
} catch (Throwable $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    error_log('[mobile/business/service-save.php] ' . $e->getMessage());
    wb_err('Hizmet kaydedilemedi', 500, 'internal_error');
}
