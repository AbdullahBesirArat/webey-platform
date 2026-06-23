<?php
declare(strict_types=1);
/**
 * api/mobile/customer/favorite-check.php
 * GET — Verilen işletmenin müşterinin favorilerinde olup olmadığını kontrol eder.
 *
 * Query params:
 *   business_id : int (zorunlu)
 *
 * Yanıt:
 *   is_favorite : bool
 *
 * Faz 8A — Bearer token zorunlu, customer tipi.
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';

wb_method('GET');

$session = mobile_auth($pdo, 'customer');
$userId  = $session['user_id'];

// ── Query parametresi ─────────────────────────────────────────────────────────
$businessId = mobile_int_param('business_id', null);
if ($businessId === null || $businessId < 1) {
    wb_err('Geçerli bir business_id girin.', 422, 'invalid_business_id');
}

// ── customer_favorites tablosunun var olup olmadığını kontrol et ──────────────
// Tablo yoksa false döndür; Flutter salon detail sayfası graceful handle eder.
try {
    $pdo->query("SELECT 1 FROM customer_favorites LIMIT 1");
} catch (Throwable) {
    wb_ok(['is_favorite' => false]);
}

// ── Favori kontrolü ───────────────────────────────────────────────────────────
try {
    $stmt = $pdo->prepare("
        SELECT 1
        FROM customer_favorites
        WHERE customer_user_id = ? AND business_id = ?
        LIMIT 1
    ");
    $stmt->execute([$userId, $businessId]);
    $exists = (bool)$stmt->fetchColumn();

    wb_ok(['is_favorite' => $exists]);

} catch (Throwable $e) {
    error_log('[mobile/customer/favorite-check.php] ' . $e->getMessage());
    wb_err('Favori durumu alınamadı.', 500, 'internal_error');
}
