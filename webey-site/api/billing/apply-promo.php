<?php
declare(strict_types=1);
/**
 * api/billing/apply-promo.php
 * POST { code, plan } - Kodu dogrular, kayit subscribe.php'de yapilir.
 */

require_once __DIR__ . '/../admin/_bootstrap.php';
require_once __DIR__ . '/_plans.php';

wb_method('POST');

$body = wb_body();
$code = strtoupper(trim((string)($body['code'] ?? '')));
$plan = trim((string)($body['plan'] ?? ''));
$userId = $user['user_id'];
$businessId = $user['business_id'] ?? null;

$planPrices = array_map(
    static fn(array $planRow): array => [
        'price' => (float)$planRow['price'],
        'label' => (string)$planRow['label'],
    ],
    WB_PLANS
);

if ($code === '') { wb_err('Kod girin', 400, 'missing_code'); }
if (!isset($planPrices[$plan])) { wb_err('Gecersiz plan', 400, 'invalid_plan'); }

try {
    $queuedStmt = $pdo->prepare("SELECT id FROM subscriptions WHERE user_id=? AND status='queued' LIMIT 1");
    $queuedStmt->execute([$userId]);
    if ($queuedStmt->fetch()) {
        wb_err('Zaten kuyrukta bekleyen bir planiniz var. Once onu iptal edin.', 409, 'queued_exists');
    }

    $promo = $pdo->prepare("
        SELECT id, code, plan, discount_type, discount_value, expires_at, max_uses, used_count
        FROM promo_codes
        WHERE code=? AND is_active=1
        LIMIT 1
    ");
    $promo->execute([$code]);
    $promo = $promo->fetch(PDO::FETCH_ASSOC);

    if (!$promo) {
        wb_err('Gecersiz veya aktif olmayan promosyon kodu', 400, 'invalid_code');
    }

    if ($promo['expires_at'] && strtotime((string)$promo['expires_at']) < time()) {
        wb_err('Bu promosyon kodunun suresi dolmus', 400, 'expired_code');
    }

    if ($promo['max_uses'] !== null && (int)$promo['used_count'] >= (int)$promo['max_uses']) {
        $message = ((int)$promo['max_uses'] === 1)
            ? 'Bu kod baska bir isletme tarafindan kullanilmis'
            : 'Bu promosyon kodu kullanim limitine ulasti';
        wb_err($message, 400, 'limit_reached');
    }

    if ($promo['plan'] !== null && $promo['plan'] !== $plan) {
        $planLabel = $planPrices[$promo['plan']]['label'] ?? $promo['plan'];
        wb_err("Bu kod sadece '{$planLabel}' icin gecerli", 400, 'plan_mismatch');
    }

    if ($businessId) {
        $usedBiz = $pdo->prepare("SELECT id FROM promo_code_uses WHERE promo_id=? AND business_id=? LIMIT 1");
        $usedBiz->execute([$promo['id'], $businessId]);
        if ($usedBiz->fetch()) {
            wb_err('Isletmeniz bu kodu daha once kullandi', 409, 'already_used');
        }
    }

    $usedUser = $pdo->prepare("SELECT id FROM promo_code_uses WHERE promo_id=? AND user_id=? LIMIT 1");
    $usedUser->execute([$promo['id'], $userId]);
    if ($usedUser->fetch()) {
        wb_err('Bu kodu daha once kullandiniz', 409, 'already_used');
    }

    $originalPrice = (float)$planPrices[$plan]['price'];
    $finalPrice = match($promo['discount_type']) {
        'free' => 0,
        'percent' => max(0, round($originalPrice * (1 - ((float)$promo['discount_value'] / 100)))),
        'fixed' => max(0, $originalPrice - (float)$promo['discount_value']),
        default => $originalPrice,
    };

    $discountLabel = match($promo['discount_type']) {
        'free' => 'Ucretsiz',
        'percent' => '%' . (int)$promo['discount_value'] . ' indirim',
        'fixed' => 'TL ' . number_format((float)$promo['discount_value'], 0, ',', '.') . ' indirim',
        default => 'Indirim',
    };

    $activeSub = $pdo->prepare("
        SELECT plan, end_date
        FROM subscriptions
        WHERE user_id=? AND status='active' AND end_date > NOW()
        ORDER BY end_date DESC
        LIMIT 1
    ");
    $activeSub->execute([$userId]);
    $activeSub = $activeSub->fetch(PDO::FETCH_ASSOC);

    wb_ok([
        'promo_id' => (int)$promo['id'],
        'code' => $promo['code'],
        'discount_type' => $promo['discount_type'],
        'discount_value' => (float)$promo['discount_value'],
        'discount_label' => $discountLabel,
        'original_price' => $originalPrice,
        'final_price' => (float)$finalPrice,
        'is_free' => $finalPrice == 0,
        'active_sub_end' => $activeSub['end_date'] ?? null,
        'active_sub_plan' => $activeSub['plan'] ?? null,
        'has_queued' => false,
    ]);
} catch (Throwable $e) {
    error_log('[billing/apply-promo.php] ' . $e->getMessage());
    wb_err('Kod dogrulanamadi', 500, 'internal_error');
}
