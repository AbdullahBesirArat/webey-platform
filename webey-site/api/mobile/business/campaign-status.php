<?php
declare(strict_types=1);
/**
 * api/mobile/business/campaign-status.php
 * POST - Kampanyayı aktif/pasif yapar. Body: { id, status: active|paused }
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
$status = (string)($body['status'] ?? '');

if ($id < 1) {
    wb_err('id zorunlu', 422, 'missing_id');
}
if (!in_array($status, ['active', 'paused'], true)) {
    wb_err('status active veya paused olmalı', 422, 'invalid_status');
}

try {
    $check = $pdo->prepare("SELECT id FROM business_campaigns WHERE id = ? AND business_id = ? AND status <> 'archived' LIMIT 1");
    $check->execute([$id, $businessId]);
    if (!$check->fetch()) {
        wb_err('Kampanya bulunamadı', 404, 'campaign_not_found');
    }
    $pdo->prepare('UPDATE business_campaigns SET status = ? WHERE id = ? AND business_id = ?')
        ->execute([$status, $id, $businessId]);

    wb_ok(['updated' => true, 'id' => (string)$id, 'status' => $status, 'is_active' => $status === 'active']);
} catch (Throwable $e) {
    error_log('[mobile/business/campaign-status.php] ' . $e->getMessage());
    wb_err('Durum güncellenemedi', 500, 'internal_error');
}
