<?php
declare(strict_types=1);
/**
 * api/mobile/business/onboarding-complete.php
 * POST — Token sahibi işletme için onboarding tamamlandı bayrağını set eder.
 *
 * Body (JSON — opsiyonel):
 *   step : int (1..7) — varsayılan 7
 *
 * Davranış:
 *   - businesses.onboarding_completed = 1
 *   - businesses.onboarding_step = step
 *   - admin_users.onboarding_completed = 1 (current owner)
 *   - status alanına dokunulmaz (draft → active geçişi ayrı karar)
 *
 * Yanıt:
 *   business : { id, onboarding_completed, onboarding_step }
 *
 * Faz B14C-1 — Bearer token zorunlu, business/admin tipi.
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';
require_once __DIR__ . '/_helpers.php';

wb_method('POST');

$auth       = mobile_auth($pdo, ['business', 'admin']);
$ctx        = mobile_business_context($pdo, $auth);
$businessId = (int)$ctx['business_id'];
$userId     = (int)$ctx['user_id'];

$in = wb_body();

// ── Input doğrulama ───────────────────────────────────────────────────────────
$step = isset($in['step']) ? (int)$in['step'] : 7;
if ($step < 1 || $step > 7) {
    wb_err('step 1 ile 7 arasında olmalı.', 422, 'invalid_step');
}

try {
    $pdo->beginTransaction();

    // Temel alanlar dolu mu? Eksikse status 'draft' kalsın.
    $check = $pdo->prepare(
        "SELECT name, city, district, status FROM businesses WHERE id = ? LIMIT 1"
    );
    $check->execute([$businessId]);
    $bizRow = $check->fetch() ?: [];
    $hasBasics = !empty($bizRow['name']) && !empty($bizRow['city']) && !empty($bizRow['district']);
    $shouldActivate = $hasBasics && $step >= 7 && ($bizRow['status'] ?? '') !== 'rejected'
                      && ($bizRow['status'] ?? '') !== 'suspended';

    if ($shouldActivate) {
        $pdo->prepare("
            UPDATE businesses
            SET onboarding_completed = 1,
                onboarding_step      = ?,
                status               = 'active',
                updated_at           = NOW()
            WHERE id = ?
        ")->execute([$step, $businessId]);
    } else {
        $pdo->prepare("
            UPDATE businesses
            SET onboarding_completed = 1,
                onboarding_step      = ?,
                updated_at           = NOW()
            WHERE id = ?
        ")->execute([$step, $businessId]);
    }

    $pdo->prepare("
        UPDATE admin_users
        SET onboarding_completed = 1
        WHERE user_id = ?
    ")->execute([$userId]);

    $pdo->commit();

    wb_ok(['business' => [
        'id'                   => (string)$businessId,
        'onboarding_completed' => true,
        'onboarding_step'      => $step,
        'status'               => $shouldActivate ? 'active' : ($bizRow['status'] ?? 'draft'),
    ]]);

} catch (Throwable $e) {
    if (isset($pdo) && $pdo->inTransaction()) {
        $pdo->rollBack();
    }
    error_log('[mobile/business/onboarding-complete.php] ' . $e->getMessage());
    wb_err('Onboarding bayrağı kaydedilemedi.', 500, 'internal_error');
}
