<?php
declare(strict_types=1);

/**
 * api/billing/payment-callback.php
 * Iyzico payment callback. Redirects user back to pricing page.
 */

ini_set('display_errors', '0');
error_reporting(E_ALL);

require_once __DIR__ . '/../../db.php';
require_once __DIR__ . '/../_iyzico.php';
require_once __DIR__ . '/_plans.php';
require_once __DIR__ . '/_subscription_mail.php';

$cfg = require __DIR__ . '/../_iyzico_config.php';

$plan = preg_replace('/[^a-z0-9_]/', '', (string)($_GET['plan'] ?? ''));
$token = trim((string)($_POST['token'] ?? ''));

$PLANS = WB_PLANS;
if (!isset($PLANS[$plan])) {
    header('Location: /fiyat.html?payment=error');
    exit;
}

if (!empty($cfg['debug'])) {
    $host = strtolower((string)($_SERVER['HTTP_HOST'] ?? $_SERVER['SERVER_NAME'] ?? ''));
    $isLocal = in_array($host, ['localhost', '127.0.0.1', '::1'], true)
        || str_ends_with($host, '.local')
        || str_ends_with($host, '.test');

    if (!$isLocal) {
        error_log('[payment-callback] Critical: iyzico debug mode enabled in production.');
        header('Location: /fiyat.html?payment=error');
        exit;
    }

    if (session_status() === PHP_SESSION_NONE) {
        session_start();
    }

    $userId = (int)($_SESSION['user_id'] ?? 0);
    $paymentId = 'DEBUG_' . time();
    if ($userId <= 0) {
        header('Location: /fiyat.html?payment=error');
        exit;
    }
} else {
    if ($token === '') {
        error_log('[payment-callback] Missing token.');
        header('Location: /fiyat.html?payment=failed');
        exit;
    }

    $userIdFromGet = (int)($_GET['userId'] ?? 0);
    $verifyPayload = [
        'locale' => 'tr',
        'conversationId' => 'sub_' . $userIdFromGet,
        'token' => $token,
    ];
    $resp = _iyzicoPost($cfg, '/payment/iyzipos/checkoutform/auth/ecom/detail', $verifyPayload);

    if (($resp['status'] ?? '') !== 'success' || ($resp['paymentStatus'] ?? '') !== 'SUCCESS') {
        error_log('[payment-callback] Verification failed: ' . json_encode($resp));
        header('Location: /fiyat.html?payment=failed');
        exit;
    }

    $convId = (string)($resp['conversationId'] ?? '');
    $userIdFromConv = (int)str_replace('sub_', '', $convId);
    if ($userIdFromConv <= 0 || $userIdFromConv !== $userIdFromGet) {
        error_log('[payment-callback] conversationId mismatch: conv=' . $convId . ' get=' . $userIdFromGet);
        header('Location: /fiyat.html?payment=failed');
        exit;
    }

    $userId = $userIdFromConv;
    $paymentId = (string)($resp['paymentId'] ?? '');
}

$planInfo = $PLANS[$plan];
$startDate = new DateTime();
$endDate = (clone $startDate)->modify('+' . (int)$planInfo['months'] . ' months');

$userRowStmt = $pdo->prepare("
    SELECT u.name, u.email, b.name AS biz_name
    FROM users u
    LEFT JOIN businesses b ON b.owner_id = u.id
    WHERE u.id = ?
    LIMIT 1
");
$userRowStmt->execute([$userId]);
$userInfo = $userRowStmt->fetch(PDO::FETCH_ASSOC) ?: [];

try {
    $pdo->beginTransaction();

    $pdo->prepare("
        UPDATE subscriptions
        SET status = 'cancelled', cancelled_at = NOW()
        WHERE user_id = ? AND status IN ('active', 'trialing')
    ")->execute([$userId]);

    $pdo->prepare("
        INSERT INTO subscriptions (user_id, plan, status, price, start_date, end_date, iyzico_subscription_id, created_at)
        VALUES (?, ?, 'active', ?, ?, ?, ?, NOW())
    ")->execute([
        $userId,
        $plan,
        (float)$planInfo['price'],
        $startDate->format('Y-m-d H:i:s'),
        $endDate->format('Y-m-d H:i:s'),
        $paymentId,
    ]);
    $subId = (int)$pdo->lastInsertId();

    $pdo->prepare("
        INSERT INTO invoices (subscription_id, user_id, plan_label, amount, status, iyzico_payment_id, paid_at, created_at)
        VALUES (?, ?, ?, ?, 'paid', ?, NOW(), NOW())
    ")->execute([$subId, $userId, $planInfo['label'], (float)$planInfo['price'], $paymentId]);

    $pdo->prepare("
        UPDATE businesses
        SET status = 'active', updated_at = NOW()
        WHERE owner_id = ? AND status = 'suspended' AND onboarding_completed = 1
    ")->execute([$userId]);

    wb_queue_subscription_purchase_email(
        $pdo,
        (string)($userInfo['email'] ?? ''),
        (string)($userInfo['name'] ?? 'İşletme Sahibi'),
        (string)($userInfo['biz_name'] ?? 'İşletmeniz'),
        (string)$planInfo['label'],
        $startDate,
        $endDate,
        '/admin-profile.html#billing',
        false
    );

    $pdo->commit();

    header('Location: /fiyat.html?payment=success&plan=' . urlencode($plan));
    exit;
} catch (Throwable $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    error_log('[payment-callback] DB error: ' . $e->getMessage());
    header('Location: /fiyat.html?payment=error');
    exit;
}
