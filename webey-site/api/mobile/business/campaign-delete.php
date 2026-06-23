<?php
declare(strict_types=1);
/**
 * api/mobile/business/campaign-delete.php
 * POST - Kampanyayı güvenli biçimde arşivler (HARD DELETE YOK). Body: { id }
 * Geçmiş randevu snapshot kayıtları bozulmaz; appointments.campaign_id korunur.
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';
require_once __DIR__ . '/_helpers.php';
require_once __DIR__ . '/../_campaigns.php';

wb_method('POST');

$auth = mobile_auth($pdo, ['business', 'admin']);
$ctx = mobile_business_context($pdo, $auth);
$businessId = (int)$ctx['business_id'];

if (!wb_campaign_tables_ready($pdo)) {
    wb_err('Kampanya altyapısı henüz hazır değil', 503, 'campaigns_unavailable');
}

$body = wb_body();
$id = (int)($body['id'] ?? 0);
if ($id < 1) {
    wb_err('id zorunlu', 422, 'missing_id');
}

try {
    $check = $pdo->prepare("SELECT id FROM business_campaigns WHERE id = ? AND business_id = ? LIMIT 1");
    $check->execute([$id, $businessId]);
    if (!$check->fetch()) {
        wb_err('Kampanya bulunamadı', 404, 'campaign_not_found');
    }
    // Soft delete: status = archived. campaign_services bağları korunur (snapshot için zarar yok).
    $pdo->prepare("UPDATE business_campaigns SET status = 'archived' WHERE id = ? AND business_id = ?")
        ->execute([$id, $businessId]);

    wb_ok(['deleted' => true, 'id' => (string)$id]);
} catch (Throwable $e) {
    error_log('[mobile/business/campaign-delete.php] ' . $e->getMessage());
    wb_err('Kampanya silinemedi', 500, 'internal_error');
}
