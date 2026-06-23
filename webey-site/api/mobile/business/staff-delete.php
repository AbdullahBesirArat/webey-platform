<?php
declare(strict_types=1);
/**
 * api/mobile/business/staff-delete.php
 * POST - Token sahibi isletmenin personelini siler veya pasiflestirir.
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

    $check = $pdo->prepare('SELECT id FROM staff WHERE id = ? AND business_id = ? LIMIT 1 FOR UPDATE');
    $check->execute([$id, $businessId]);
    if (!$check->fetch()) {
        $pdo->rollBack();
        wb_err('Personel bulunamadi', 404, 'staff_not_found');
    }

    if (mobile_business_has_column($pdo, 'staff', 'is_active')) {
        $stmt = $pdo->prepare('UPDATE staff SET is_active = 0 WHERE id = ? AND business_id = ?');
        $stmt->execute([$id, $businessId]);
    } else {
        $ref = $pdo->prepare('SELECT COUNT(*) FROM appointments WHERE business_id = ? AND staff_id = ?');
        $ref->execute([$businessId, $id]);
        if ((int)$ref->fetchColumn() > 0) {
            $pdo->rollBack();
            wb_err('Bu personel randevularda kullanildigi icin silinemez', 409, 'staff_in_use');
        }

        $pdo->prepare('DELETE FROM staff_services WHERE staff_id = ?')->execute([$id]);
        $pdo->prepare('DELETE FROM staff_hours WHERE staff_id = ? AND business_id = ?')->execute([$id, $businessId]);
        $stmt = $pdo->prepare('DELETE FROM staff WHERE id = ? AND business_id = ?');
        $stmt->execute([$id, $businessId]);
    }

    $pdo->commit();
    wb_ok(['deleted' => true, 'id' => $id]);
} catch (Throwable $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    error_log('[mobile/business/staff-delete.php] ' . $e->getMessage());
    wb_err('Personel silinemedi', 500, 'internal_error');
}
