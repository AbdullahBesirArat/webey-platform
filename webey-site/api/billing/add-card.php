<?php
declare(strict_types=1);
/**
 * api/billing/add-card.php — Kart kaydet (iyzico checkout form ile)
 * POST — admin auth gerekli
 * debug=true → Sahte token üretir, iyzico çağrılmaz
 */

require_once __DIR__ . '/../admin/_bootstrap.php';
require_once __DIR__ . '/../_iyzico.php';
wb_method('POST');

$body   = wb_body();
$userId = $user['user_id'];
$cfg    = require __DIR__ . '/../_iyzico_config.php';

$cardHolderName = trim($body['cardHolderName'] ?? '');
$cardNumber     = preg_replace('/\D/', '', $body['cardNumber'] ?? '');
$expireMonth    = trim($body['expireMonth'] ?? '');
$expireYear     = trim($body['expireYear'] ?? '');
$cvc            = trim($body['cvc'] ?? '');

if (!$cardHolderName || strlen($cardNumber) < 15 || !$expireMonth || !$expireYear || !$cvc) {
    wb_err('Kart bilgileri eksik', 400, 'missing_param');
}

$last4 = substr($cardNumber, -4);
$brand = str_starts_with($cardNumber,'4') ? 'Visa'
       : (preg_match('/^5[1-5]/', $cardNumber) ? 'Mastercard'
       : (preg_match('/^9792/', $cardNumber) ? 'Troy' : 'Kart'));

if ($cfg['debug']) {
    $cardToken = 'card_debug_' . bin2hex(random_bytes(10));
    error_log('[iyzico DEBUG] AddCard | user:' . $userId . ' brand:' . $brand . ' last4:' . $last4);
} else {
    // Gerçek iyzico entegrasyonu: hesap açıldıktan sonra etkinleştirilecek
    wb_err('Kart kaydetme özelliği yakında aktif olacak.', 503, 'not_implemented');
}

try {
    $countStmt = $pdo->prepare("SELECT COUNT(*) FROM payment_cards WHERE user_id=? AND deleted_at IS NULL");
    $countStmt->execute([$userId]);
    $isFirst = ($countStmt->fetchColumn() == 0) ? 1 : 0;

    $pdo->prepare("INSERT INTO payment_cards (user_id,iyzico_card_token,card_brand,card_last4,expire_month,expire_year,is_default,created_at) VALUES (?,?,?,?,?,?,?,NOW())")
        ->execute([$userId, $cardToken, $brand, $last4, $expireMonth, $expireYear, $isFirst]);

    wb_ok(['token' => $cardToken, 'brand' => $brand, 'last4' => $last4, 'debug' => $cfg['debug']]);

} catch (Throwable $e) {
    error_log('[billing/add-card.php] ' . $e->getMessage());
    wb_err('Kart kaydedilemedi', 500, 'internal_error');
}