<?php
declare(strict_types=1);
/**
 * api/billing/remove-card.php — Kayıtlı kart sil
 * POST { token } — admin auth gerekli
 */

require_once __DIR__ . '/../admin/_bootstrap.php';
wb_method('POST');

$body   = wb_body();
$userId = $user['user_id'];
$token  = trim($body['token'] ?? '');

if (!$token) { wb_err('Token gerekli', 400, 'missing_param'); }

try {
    $pdo->prepare("UPDATE payment_cards SET deleted_at=NOW() WHERE user_id=? AND iyzico_card_token=? AND deleted_at IS NULL")
        ->execute([$userId, $token]);
    wb_ok([]);
} catch (Throwable $e) {
    error_log('[billing/remove-card.php] ' . $e->getMessage());
    wb_err('Kart silinemedi', 500, 'internal_error');
}