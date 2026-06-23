<?php
declare(strict_types=1);
/**
 * api/billing/cards.php — Kayıtlı kartları listele
 * GET — admin auth gerekli
 */

require_once __DIR__ . '/../admin/_bootstrap.php';
wb_method('GET');

$userId = $user['user_id'];

try {
    $stmt = $pdo->prepare("
        SELECT id, iyzico_card_token AS token, card_brand AS brand,
               card_last4 AS last4, expire_month AS expMonth,
               expire_year AS expYear, is_default AS isDefault
        FROM payment_cards
        WHERE user_id=? AND deleted_at IS NULL
        ORDER BY is_default DESC, created_at DESC
    ");
    $stmt->execute([$userId]);
    $cards = $stmt->fetchAll();
    wb_ok(['cards' => $cards]);
} catch (Throwable $e) {
    error_log('[billing/cards.php] ' . $e->getMessage());
    wb_ok(['cards' => []]); // graceful: tablo yoksa boş dön
}