<?php
declare(strict_types=1);
/**
 * api/mobile/business/service-delete.php
 * POST - Token sahibi isletmenin hizmetini siler veya pasiflestirir.
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';
require_once __DIR__ . '/_helpers.php';

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
    $pdo->beginTransaction();

    $check = $pdo->prepare('SELECT id FROM services WHERE id = ? AND business_id = ? LIMIT 1 FOR UPDATE');
    $check->execute([$id, $businessId]);
    if (!$check->fetch()) {
        $pdo->rollBack();
        wb_err('Hizmet bulunamadi', 404, 'service_not_found');
    }

    if (mobile_business_has_column($pdo, 'services', 'is_active')) {
        $stmt = $pdo->prepare('UPDATE services SET is_active = 0 WHERE id = ? AND business_id = ?');
        $stmt->execute([$id, $businessId]);
    } else {
        $ref = $pdo->prepare('SELECT COUNT(*) FROM appointments WHERE business_id = ? AND service_id = ?');
        $ref->execute([$businessId, $id]);
        if ((int)$ref->fetchColumn() > 0) {
            $pdo->rollBack();
            wb_err('Bu hizmet randevularda kullanildigi icin silinemez', 409, 'service_in_use');
        }

        $pdo->prepare('DELETE FROM staff_services WHERE service_id = ?')->execute([$id]);
        $stmt = $pdo->prepare('DELETE FROM services WHERE id = ? AND business_id = ?');
        $stmt->execute([$id, $businessId]);
    }

    $pdo->commit();
    wb_ok(['deleted' => true, 'id' => $id]);
} catch (Throwable $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    error_log('[mobile/business/service-delete.php] ' . $e->getMessage());
    wb_err('Hizmet silinemedi', 500, 'internal_error');
}
