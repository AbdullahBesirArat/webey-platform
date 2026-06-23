<?php
declare(strict_types=1);
/**
 * api/mobile/customer/favorite-toggle.php
 * POST — Müşterinin favori salonunu ekler veya kaldırır.
 *
 * Body (JSON):
 *   business_id : int   (zorunlu)
 *   favorite    : bool  (zorunlu — true: ekle, false: kaldır)
 *
 * Yanıt:
 *   is_favorite : bool  — son durum
 *
 * Faz 8A — Bearer token zorunlu, customer tipi.
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';

wb_method('POST');

$session = mobile_auth($pdo, 'customer');
$userId  = $session['user_id'];

$in = wb_body();

// ── Input doğrulama ───────────────────────────────────────────────────────────
$businessId = (int)($in['business_id'] ?? 0);
if ($businessId < 1) {
    wb_err('Geçerli bir business_id girin.', 422, 'invalid_business_id');
}

if (!array_key_exists('favorite', $in)) {
    wb_err('favorite alanı zorunludur.', 422, 'missing_favorite');
}
$favorite = (bool)$in['favorite'];

// ── İşletmenin var ve aktif olduğunu doğrula ─────────────────────────────────
try {
    $bizStmt = $pdo->prepare(
        "SELECT id FROM businesses WHERE id = ? AND status = 'active' LIMIT 1"
    );
    $bizStmt->execute([$businessId]);
    if (!$bizStmt->fetchColumn()) {
        wb_err('İşletme bulunamadı.', 404, 'business_not_found');
    }
} catch (Throwable $e) {
    error_log('[mobile/customer/favorite-toggle.php] biz check: ' . $e->getMessage());
    wb_err('İşlem tamamlanamadı.', 500, 'internal_error');
}

// ── customer_favorites tablosunun var olup olmadığını kontrol et ──────────────
try {
    $pdo->query("SELECT 1 FROM customer_favorites LIMIT 1");
} catch (Throwable) {
    wb_err(
        'Favoriler henüz aktif değil. Lütfen migration SQL\'ini uygulayın.',
        503,
        'favorites_not_ready'
    );
}

// ── Favori güncelle ───────────────────────────────────────────────────────────
try {
    if ($favorite) {
        // Zaten varsa sessizce geç (UNIQUE KEY koruyor)
        $pdo->prepare(
            "INSERT IGNORE INTO customer_favorites (customer_user_id, business_id) VALUES (?, ?)"
        )->execute([$userId, $businessId]);
    } else {
        $pdo->prepare(
            "DELETE FROM customer_favorites WHERE customer_user_id = ? AND business_id = ?"
        )->execute([$userId, $businessId]);
    }

    wb_ok(['is_favorite' => $favorite]);

} catch (Throwable $e) {
    error_log('[mobile/customer/favorite-toggle.php] ' . $e->getMessage());
    wb_err('Favori güncellenemedi.', 500, 'internal_error');
}
