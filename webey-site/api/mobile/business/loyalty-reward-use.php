<?php
declare(strict_types=1);
/**
 * api/mobile/business/loyalty-reward-use.php
 * POST — Üyenin kazanılmış (henüz kullanılmamış) ödülünü "kullanıldı" işaretler.
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';
require_once __DIR__ . '/_helpers.php';
require_once __DIR__ . '/../_loyalty.php';

wb_method('POST');

$auth = mobile_auth($pdo, ['business', 'admin']);
$ctx = mobile_business_context($pdo, $auth);
$businessId = (int)$ctx['business_id'];

if (!wb_loyalty_tables_ready($pdo)) {
    wb_err('Sadakat servisi şu an kullanılamıyor', 503, 'loyalty_unavailable');
}

$in = wb_body();
$progressId = (int)($in['progress_id'] ?? 0);
if ($progressId <= 0) {
    wb_err('progress_id zorunlu', 400, 'missing_param');
}

try {
    $stmt = $pdo->prepare(
        'SELECT id, rewards_earned, rewards_used, customer_user_id, customer_phone
           FROM business_loyalty_progress
          WHERE id = ? AND business_id = ? LIMIT 1'
    );
    $stmt->execute([$progressId, $businessId]);
    $row = $stmt->fetch();
    if (!$row) {
        wb_err('Üye bulunamadı', 404, 'progress_not_found');
    }
    $available = (int)$row['rewards_earned'] - (int)$row['rewards_used'];
    if ($available <= 0) {
        wb_err('Kullanılabilir ödül yok', 422, 'no_reward_available');
    }

    $pdo->prepare(
        'UPDATE business_loyalty_progress
            SET rewards_used = rewards_used + 1, updated_at = NOW()
          WHERE id = ?'
    )->execute([$progressId]);

    $pdo->prepare(
        "INSERT INTO business_loyalty_events
            (business_id, progress_id, customer_user_id, customer_phone,
             event_type, visits_delta, rewards_delta, created_at)
         VALUES (?, ?, ?, ?, 'reward_used', 0, -1, NOW())"
    )->execute([
        $businessId, $progressId,
        $row['customer_user_id'], $row['customer_phone'],
    ]);
} catch (Throwable $e) {
    error_log('[mobile/business/loyalty-reward-use.php] ' . $e->getMessage());
    wb_err('Ödül kullanılamadı.', 500, 'internal_error');
}

wb_ok([
    'progress_id' => $progressId,
    'message' => 'Ödül kullanıldı olarak işaretlendi.',
]);
