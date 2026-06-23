<?php
declare(strict_types=1);

/**
 * api/billing/subscribe.php
 * POST { plan, promo_code? }
 */

require_once __DIR__ . '/../admin/_bootstrap.php';
require_once __DIR__ . '/../_iyzico.php';
require_once __DIR__ . '/_plans.php';
require_once __DIR__ . '/_subscription_mail.php';

wb_method('POST');

$body = wb_body();
$userId = (int)$user['user_id'];
$businessId = isset($user['business_id']) ? (int)$user['business_id'] : null;
$plan = (string)($body['plan'] ?? '');
$promoCode = strtoupper(trim((string)($body['promo_code'] ?? '')));

$PLANS = WB_PLANS;
if (!isset($PLANS[$plan])) {
    wb_err('Geçersiz plan', 400, 'invalid_plan');
}

$planInfo = $PLANS[$plan];
$finalPrice = (float)$planInfo['price'];
$promoId = null;
$isFree = false;

$activeSubStmt = $pdo->prepare("
    SELECT id, plan, end_date
    FROM subscriptions
    WHERE user_id = ? AND status = 'active' AND end_date > NOW()
    ORDER BY end_date DESC
    LIMIT 1
");
$activeSubStmt->execute([$userId]);
$existingActiveSub = $activeSubStmt->fetch(PDO::FETCH_ASSOC) ?: null;

$queuedSubStmt = $pdo->prepare("
    SELECT id
    FROM subscriptions
    WHERE user_id = ? AND status = 'queued'
    LIMIT 1
");
$queuedSubStmt->execute([$userId]);
if ($queuedSubStmt->fetch(PDO::FETCH_ASSOC)) {
    wb_err('Zaten kuyrukta bekleyen bir planınız var. Önce onu iptal edin.', 409, 'queued_exists');
}

if ($promoCode !== '') {
    $promoStmt = $pdo->prepare("
        SELECT id, code, plan, discount_type, discount_value, expires_at, max_uses, used_count
        FROM promo_codes
        WHERE code = ?
          AND is_active = 1
          AND (expires_at IS NULL OR expires_at > NOW())
          AND (max_uses IS NULL OR used_count < max_uses)
        LIMIT 1
    ");
    $promoStmt->execute([$promoCode]);
    $promo = $promoStmt->fetch(PDO::FETCH_ASSOC) ?: null;

    if (!$promo) {
        wb_err('Geçersiz veya süresi dolmuş promosyon kodu', 400, 'invalid_code');
    }

    if ($promo['plan'] !== null && (string)$promo['plan'] !== $plan) {
        $planLabel = $PLANS[(string)$promo['plan']]['label'] ?? (string)$promo['plan'];
        wb_err("Bu kod sadece '{$planLabel}' için geçerli", 400, 'plan_mismatch');
    }

    if ($businessId) {
        $usedBizStmt = $pdo->prepare('SELECT id FROM promo_code_uses WHERE promo_id = ? AND business_id = ? LIMIT 1');
        $usedBizStmt->execute([(int)$promo['id'], $businessId]);
        if ($usedBizStmt->fetch(PDO::FETCH_ASSOC)) {
            wb_err('İşletmeniz bu kodu daha önce kullandı', 409, 'already_used');
        }
    }

    $usedUserStmt = $pdo->prepare('SELECT id FROM promo_code_uses WHERE promo_id = ? AND user_id = ? LIMIT 1');
    $usedUserStmt->execute([(int)$promo['id'], $userId]);
    if ($usedUserStmt->fetch(PDO::FETCH_ASSOC)) {
        wb_err('Bu kodu daha önce kullandınız', 409, 'already_used');
    }

    $promoId = (int)$promo['id'];
    $finalPrice = match ((string)$promo['discount_type']) {
        'free' => 0.0,
        'percent' => max(0.0, round((float)$planInfo['price'] * (1 - ((float)$promo['discount_value'] / 100)))),
        'fixed' => max(0.0, (float)$planInfo['price'] - (float)$promo['discount_value']),
        default => (float)$planInfo['price'],
    };
    $isFree = ($finalPrice == 0.0);
}

$cfg = require __DIR__ . '/../_iyzico_config.php';
if (!empty($cfg['debug'])) {
    $host = strtolower((string)($_SERVER['HTTP_HOST'] ?? $_SERVER['SERVER_NAME'] ?? ''));
    $isLocal = in_array($host, ['localhost', '127.0.0.1', '::1'], true)
        || str_ends_with($host, '.local')
        || str_ends_with($host, '.test');

    if (!$isLocal) {
        error_log('[billing/subscribe.php] Critical: iyzico debug mode enabled in production.');
        wb_err('Ödeme sistemi şu an kullanılamıyor. Lütfen daha sonra tekrar deneyin.', 503, 'payment_unavailable');
    }
}

$userRowStmt = $pdo->prepare("
    SELECT u.name, u.email, c.phone
    FROM users u
    LEFT JOIN customers c ON c.user_id = u.id
    WHERE u.id = ?
    LIMIT 1
");
$userRowStmt->execute([$userId]);
$userInfo = $userRowStmt->fetch(PDO::FETCH_ASSOC) ?: [];

$bizRowStmt = $pdo->prepare("SELECT name FROM businesses WHERE owner_id = ? LIMIT 1");
$bizRowStmt->execute([$userId]);
$bizInfo = $bizRowStmt->fetch(PDO::FETCH_ASSOC) ?: [];

if ($isFree || !empty($cfg['debug'])) {
    if ($existingActiveSub) {
        $startDate = new DateTime((string)$existingActiveSub['end_date']);
        $isQueued = true;
    } else {
        $startDate = new DateTime();
        $isQueued = false;
    }

    $endDate = (clone $startDate)->modify('+' . (int)$planInfo['months'] . ' months');
    $newStatus = $isQueued ? 'queued' : 'active';

    try {
        $pdo->beginTransaction();

        if (!$existingActiveSub) {
            $pdo->prepare("
                UPDATE subscriptions
                SET status = 'cancelled', cancelled_at = NOW()
                WHERE user_id = ? AND status IN ('active','trialing')
            ")->execute([$userId]);
        }

        $pdo->prepare("
            INSERT INTO subscriptions (user_id, plan, status, price, start_date, end_date, created_at)
            VALUES (?, ?, ?, ?, ?, ?, NOW())
        ")->execute([
            $userId,
            $plan,
            $newStatus,
            $finalPrice,
            $startDate->format('Y-m-d H:i:s'),
            $endDate->format('Y-m-d H:i:s'),
        ]);
        $subId = (int)$pdo->lastInsertId();

        $pdo->prepare("
            INSERT INTO invoices (subscription_id, user_id, plan_label, amount, status, created_at)
            VALUES (?, ?, ?, ?, 'paid', NOW())
        ")->execute([$subId, $userId, $planInfo['label'], $finalPrice]);

        if (!$isQueued) {
            $pdo->prepare("
                UPDATE businesses
                SET status = 'active', updated_at = NOW()
                WHERE owner_id = ? AND status = 'suspended' AND onboarding_completed = 1
            ")->execute([$userId]);
        }

        if ($promoId) {
            $pdo->prepare("
                INSERT INTO promo_code_uses (promo_id, user_id, business_id, subscription_id, used_at)
                VALUES (?, ?, ?, ?, NOW())
            ")->execute([$promoId, $userId, $businessId, $subId]);
            $pdo->prepare("UPDATE promo_codes SET used_count = used_count + 1 WHERE id = ?")->execute([$promoId]);
        }

        wb_queue_subscription_purchase_email(
            $pdo,
            (string)($userInfo['email'] ?? ''),
            (string)($userInfo['name'] ?? 'İşletme Sahibi'),
            (string)($bizInfo['name'] ?? 'İşletmeniz'),
            (string)$planInfo['label'],
            $startDate,
            $endDate,
            '/admin-profile.html#billing',
            $isQueued
        );

        $pdo->commit();
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        error_log('[billing/subscribe.php free] ' . $e->getMessage());
        wb_err('Abonelik kaydedilemedi', 500, 'internal_error');
    }

    if ($isQueued) {
        $existingLabel = $PLANS[(string)$existingActiveSub['plan']]['label'] ?? (string)$existingActiveSub['plan'];
        $msg = "✅ {$planInfo['label']} plan kuyruğa eklendi. Mevcut {$existingLabel} planınız bittiğinde otomatik başlayacak.";
    } else {
        $msg = $isFree
            ? "🎉 Promosyon kodu uygulandı! {$planInfo['label']} ücretsiz aktifleştirildi."
            : 'Abonelik oluşturuldu (debug modu)';
    }

    wb_ok([
        'free' => $isFree,
        'debug' => !empty($cfg['debug']) && !$isFree,
        'queued' => $isQueued,
        'message' => $msg,
        'plan' => $plan,
        'startDate' => $startDate->format('Y-m-d'),
        'endDate' => $endDate->format('Y-m-d'),
        'activeSubEnd' => $existingActiveSub['end_date'] ?? null,
    ]);
}

$iyzico = iyzicoInitCheckout(
    $userId,
    $plan,
    $finalPrice,
    (string)($userInfo['name'] ?? 'Webey Kullanıcı'),
    (string)($userInfo['email'] ?? ''),
    (string)($userInfo['phone'] ?? '')
);

if (!($iyzico['ok'] ?? false)) {
    wb_err((string)($iyzico['error'] ?? 'Ödeme başlatılamadı'), 500, 'payment_error');
}

wb_ok([
    'requiresAction' => true,
    'checkoutToken' => $iyzico['checkoutToken'],
    'checkoutUrl' => $iyzico['checkoutUrl'],
    'final_price' => $finalPrice,
]);
