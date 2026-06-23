<?php
declare(strict_types=1);

/**
 * api/billing/cancel.php
 * POST { at_period_end?: true } -> active/trialing plan cancel at period end
 * POST { subscription_id: N, queued: true } -> cancel queued plan immediately
 */

require_once __DIR__ . '/../admin/_bootstrap.php';

wb_method('POST');

$body = wb_body();
$userId = (int)$user['user_id'];

if (!empty($body['queued']) && !empty($body['subscription_id'])) {
    $subId = (int)$body['subscription_id'];

    try {
        $stmt = $pdo->prepare("
            UPDATE subscriptions
            SET status = 'cancelled', cancelled_at = NOW(), updated_at = NOW()
            WHERE id = ? AND user_id = ? AND status = 'queued'
        ");
        $stmt->execute([$subId, $userId]);

        if ($stmt->rowCount() === 0) {
            wb_err('Bekleyen plan bulunamadı veya size ait değil', 404, 'not_found');
        }

        wb_ok(['message' => 'Bekleyen plan iptal edildi']);
    } catch (Throwable $e) {
        error_log('[billing/cancel.php queued] ' . $e->getMessage());
        wb_err('İptal işlemi gerçekleştirilemedi', 500, 'internal_error');
    }
}

try {
    $stmt = $pdo->prepare("
        UPDATE subscriptions
        SET cancel_at_period_end = 1, updated_at = NOW()
        WHERE user_id = ? AND status IN ('active', 'trialing')
    ");
    $stmt->execute([$userId]);

    if ($stmt->rowCount() === 0) {
        wb_err('Aktif üyeliğiniz yok.', 400, 'no_active_subscription');
    }

    wb_ok(['message' => 'Abonelik dönem sonunda iptal edilecek']);
} catch (Throwable $e) {
    error_log('[billing/cancel.php] ' . $e->getMessage());
    wb_err('İptal işlemi gerçekleştirilemedi', 500, 'internal_error');
}
