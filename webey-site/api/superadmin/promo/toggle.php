<?php
declare(strict_types=1);
/**
 * api/superadmin/promo/toggle.php
 * POST { id, action: 'activate'|'deactivate'|'delete' }
 */

require_once __DIR__ . '/../_bootstrap.php';

wb_method('POST');

$body = wb_body();
$id = (int)($body['id'] ?? 0);
$action = (string)($body['action'] ?? '');

if (!$id || !in_array($action, ['activate', 'deactivate', 'delete'], true)) {
    wb_err('id ve action zorunlu (activate|deactivate|delete)', 400, 'missing_param');
}

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
        wb_err('Kod bulunamadi', 404, 'not_found');
    }

    if ($action === 'delete') {
        if ((int)$promo['actual_uses'] > 0) {
            wb_err(
                'Bu kod daha once kullanildi. Gecmis kayitlari korumak icin silinemez; pasife alin.',
                409,
                'promo_in_use',
                ['used_count' => (int)$promo['actual_uses']]
            );
        }

        $pdo->prepare("DELETE FROM promo_codes WHERE id=?")->execute([$id]);
        wb_ok(['message' => 'Kod silindi', 'cancelled_subs' => 0]);
    }

    $active = $action === 'activate' ? 1 : 0;
    $pdo->prepare("UPDATE promo_codes SET is_active=? WHERE id=?")->execute([$active, $id]);

    wb_ok([
        'message' => $active ? 'Kod aktiflestirildi' : 'Kod devre disi birakildi',
        'is_active' => (bool)$active,
    ]);
} catch (Throwable $e) {
    error_log('[promo/toggle] ' . $e->getMessage());
    wb_err('Islem basarisiz', 500, 'internal_error');
}
