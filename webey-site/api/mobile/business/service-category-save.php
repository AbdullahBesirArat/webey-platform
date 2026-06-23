<?php
declare(strict_types=1);
/**
 * api/mobile/business/service-category-save.php
 * POST - Isletmeye ozel hizmet kategorisi olusturur/gunceller.
 *
 * Body:
 *   id         : int|null (null/0 = yeni)
 *   name       : string (zorunlu, maks 80)
 *   icon_key   : string|null (maks 40)
 *   sort_order : int|null
 *
 * Kurallar:
 *   - Sistem kategorileri (business_id = 0) bu endpoint ile degistirilemez.
 *   - Ayni isletmede ayni isim/slug iki kez olamaz.
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
$name = mb_substr(trim((string)($body['name'] ?? '')), 0, 80);
$iconKeyRaw = trim((string)($body['icon_key'] ?? ''));
$iconKey = $iconKeyRaw !== '' ? mb_substr($iconKeyRaw, 0, 40) : null;
$sortOrder = (int)($body['sort_order'] ?? 0);

if ($name === '') {
    wb_err('Kategori adı boş olamaz.', 422, 'missing_name');
}

try {
    if (!mobile_category_table_exists($pdo)) {
        wb_err('Kategori altyapısı henüz hazır değil.', 503, 'categories_unavailable');
    }

    $slug = mobile_slugify_tr($name);

    $pdo->beginTransaction();

    if ($id > 0) {
        $check = $pdo->prepare(
            'SELECT id, business_id FROM service_categories WHERE id = ? LIMIT 1 FOR UPDATE'
        );
        $check->execute([$id]);
        $row = $check->fetch();
        if (!$row || (int)$row['business_id'] !== $businessId) {
            $pdo->rollBack();
            wb_err('Kategori bulunamadı.', 404, 'category_not_found');
        }
    }

    // Ayni isletmede ayni isim/slug tekrar etmesin (kendisi haric).
    $dupe = $pdo->prepare(
        'SELECT id FROM service_categories
         WHERE business_id = ? AND id <> ? AND is_active = 1
           AND (LOWER(name) = LOWER(?) OR slug = ?)
         LIMIT 1'
    );
    $dupe->execute([$businessId, $id, $name, $slug]);
    if ($dupe->fetch()) {
        $pdo->rollBack();
        wb_err('Bu isimde bir kategoriniz zaten var.', 409, 'duplicate_category');
    }

    // Slug, sistem slug'lariyla cakisirsa isletme oneki ekle (uq_business_slug
    // business_id ile ayristigi icin sart degil ama filtre karisikligini onler).
    $sysDupe = $pdo->prepare(
        'SELECT id FROM service_categories WHERE business_id = 0 AND slug = ? LIMIT 1'
    );
    $sysDupe->execute([$slug]);
    if ($sysDupe->fetch()) {
        $slug = mb_substr('b' . $businessId . '_' . $slug, 0, 90);
    }

    if ($id > 0) {
        $pdo->prepare(
            'UPDATE service_categories
             SET name = ?, slug = ?, icon_key = ?, sort_order = ?
             WHERE id = ? AND business_id = ?'
        )->execute([$name, $slug, $iconKey, $sortOrder, $id, $businessId]);
    } else {
        $pdo->prepare(
            'INSERT INTO service_categories (business_id, name, slug, icon_key, sort_order, is_active)
             VALUES (?, ?, ?, ?, ?, 1)'
        )->execute([$businessId, $name, $slug, $iconKey, $sortOrder]);
        $id = (int)$pdo->lastInsertId();
    }

    $stmt = $pdo->prepare(
        'SELECT id, business_id, name, slug, icon_key, sort_order,
                0 AS service_count
         FROM service_categories WHERE id = ? LIMIT 1'
    );
    $stmt->execute([$id]);
    $saved = $stmt->fetch();

    $pdo->commit();

    wb_ok([
        'saved' => true,
        'category' => mobile_category_item($saved ?: [
            'id' => $id,
            'business_id' => $businessId,
            'name' => $name,
            'slug' => $slug,
            'icon_key' => $iconKey,
            'sort_order' => $sortOrder,
        ]),
    ]);
} catch (Throwable $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    error_log('[mobile/business/service-category-save.php] ' . $e->getMessage());
    wb_err('Kategori kaydedilemedi', 500, 'internal_error');
}
