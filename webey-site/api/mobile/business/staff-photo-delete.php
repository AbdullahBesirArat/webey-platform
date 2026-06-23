<?php
declare(strict_types=1);
/**
 * api/mobile/business/staff-photo-delete.php
 * POST — Personelin profil fotoğrafı referansını kaldırır. Body: { staff_id }
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';
require_once __DIR__ . '/_helpers.php';

wb_method('POST');

$auth = mobile_auth($pdo, ['business', 'admin']);
$ctx = mobile_business_context($pdo, $auth);
$businessId = (int)$ctx['business_id'];

if (!mobile_table_has_column($pdo, 'staff', 'profile_photo_url')) {
    wb_err('Personel fotoğrafı servisi şu an kullanılamıyor', 503, 'staff_photo_unavailable');
}

$body = wb_body();
$staffId = (int)($body['staff_id'] ?? $body['id'] ?? 0);
if ($staffId < 1) {
    wb_err('staff_id zorunlu', 400, 'missing_staff_id');
}

try {
    $chk = $pdo->prepare('SELECT id FROM staff WHERE id = ? AND business_id = ? LIMIT 1');
    $chk->execute([$staffId, $businessId]);
    if (!$chk->fetch()) {
        wb_err('Personel bulunamadı', 404, 'staff_not_found');
    }
    $pdo->prepare(
        'UPDATE staff SET profile_photo_url = NULL, profile_photo_updated_at = NOW()
         WHERE id = ? AND business_id = ?'
    )->execute([$staffId, $businessId]);

    wb_ok(['deleted' => true, 'staff_id' => (string)$staffId]);
} catch (Throwable $e) {
    error_log('[mobile/business/staff-photo-delete.php] ' . $e->getMessage());
    wb_err('Personel fotoğrafı kaldırılamadı', 500, 'server_error');
}
