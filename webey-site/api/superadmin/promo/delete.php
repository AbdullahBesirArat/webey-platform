<?php
declare(strict_types=1);
/**
 * api/superadmin/promo/delete.php
 * POST { id } - Yalnizca hic kullanilmamis kodlar silinir.
 */

require_once __DIR__ . '/../_bootstrap.php';

wb_method('POST');

$body = wb_body();
$id = (int)($body['id'] ?? 0);

if (!$id) { wb_err('id zorunlu', 400, 'missing_param'); }

try {
    $check = $pdo->prepare("
        SELECT p.id, p.code,
               (SELECT COUNT(*) FROM promo_code_uses WHERE promo_id = p.id) AS actual_uses
        FROM promo_codes p
        WHERE p.id = ?
        LIMIT 1
    ");
    $check->execute([$id]);
    $promo = $check->fetch(PDO::FETCH_ASSOC);

    if (!$promo) {
        wb_err('Promosyon kodu bulunamadi', 404, 'not_found');
    }

    if ((int)$promo['actual_uses'] > 0) {
        wb_err(
            'Bu kod daha once kullanildi. Gecmis kayitlari korumak icin silinemez; pasife alin.',
            409,
            'promo_in_use',
            ['used_count' => (int)$promo['actual_uses']]
        );
    }

    $pdo->prepare("DELETE FROM promo_codes WHERE id = ?")->execute([$id]);

    wb_ok([
        'message' => 'Promosyon kodu silindi',
        'cancelled_subs' => 0,
        'affected_users' => [],
    ]);
} catch (Throwable $e) {
    error_log('[promo/delete] ' . $e->getMessage());
    wb_err('Islem basarisiz', 500, 'internal_error');
}
