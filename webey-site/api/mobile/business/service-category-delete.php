<?php
declare(strict_types=1);
/**
 * api/mobile/business/service-category-delete.php
 * POST - Isletmeye ozel hizmet kategorisini siler (soft delete: is_active = 0).
 *
 * Kurallar:
 *   - Sistem kategorileri (business_id = 0) silinemez.
 *   - Sadece isletmenin kendi kategorisi silinebilir.
 *   - Kategoriye bagli aktif hizmet varsa silme engellenir (faz 1 karari).
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

if ($id <= 0) {
    wb_err('id zorunlu', 400, 'missing_id');
}

try {
    if (!mobile_category_table_exists($pdo)) {
        wb_err('Kategori altyapısı henüz hazır değil.', 503, 'categories_unavailable');
    }

    $pdo->beginTransaction();

    $check = $pdo->prepare(
        'SELECT id, business_id FROM service_categories WHERE id = ? LIMIT 1 FOR UPDATE'
    );
    $check->execute([$id]);
    $row = $check->fetch();
    if (!$row) {
        $pdo->rollBack();
        wb_err('Kategori bulunamadı.', 404, 'category_not_found');
    }
    if ((int)$row['business_id'] === 0) {
        $pdo->rollBack();
        wb_err('Varsayılan kategoriler silinemez.', 403, 'system_category');
    }
    if ((int)$row['business_id'] !== $businessId) {
        $pdo->rollBack();
        wb_err('Kategori bulunamadı.', 404, 'category_not_found');
    }

    $hasSvcActive = mobile_table_has_column($pdo, 'services', 'is_active');
    $countSql = 'SELECT COUNT(*) FROM services WHERE business_id = ? AND category_id = ?'
        . ($hasSvcActive ? ' AND is_active = 1' : '');
    $countStmt = $pdo->prepare($countSql);
    $countStmt->execute([$businessId, $id]);
    $serviceCount = (int)$countStmt->fetchColumn();

    if ($serviceCount > 0) {
        $pdo->rollBack();
        wb_err(
            'Bu kategoriye bağlı ' . $serviceCount . ' hizmet var. Önce hizmetleri farklı bir kategoriye taşıyın.',
            409,
            'category_in_use'
        );
    }

    // Pasif hizmetlerde kalmis baglari da temizle (veri kaybi yok: yalnizca
    // kategori referansi null olur, hizmetin kendisi ve text fallback korunur).
    $pdo->prepare(
        'UPDATE services SET category_id = NULL WHERE business_id = ? AND category_id = ?'
    )->execute([$businessId, $id]);

    // Soft delete; slug'i serbest birak ki ayni isimle tekrar kategori
    // olusturulabilsin (uq_business_slug ihlali olmasin).
    $pdo->prepare(
        "UPDATE service_categories
         SET is_active = 0, slug = CONCAT(LEFT(slug, 70), '_del_', id)
         WHERE id = ? AND business_id = ?"
    )->execute([$id, $businessId]);

    $pdo->commit();
    wb_ok(['deleted' => true, 'id' => $id]);
} catch (Throwable $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    error_log('[mobile/business/service-category-delete.php] ' . $e->getMessage());
    wb_err('Kategori silinemedi', 500, 'internal_error');
}
