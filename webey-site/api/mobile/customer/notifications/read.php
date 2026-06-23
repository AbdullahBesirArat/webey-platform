<?php
declare(strict_types=1);
/**
 * api/mobile/customer/notifications/read.php
 * POST — Müşteri bildirimini (veya tümünü) okundu işaretler.
 *
 * Body (JSON) — iki kullanım:
 *   { "id": "123" }    → tek bildirim okundu işaretler
 *   { "all": true }    → token sahibine ait tüm bildirimleri okundu işaretler
 *
 * Yanıt: {}  (Flutter caller dönüşü görmezden gelir — Future<void>)
 *
 * Güvenlik: her UPDATE'e WHERE user_id = $userId eklenir;
 *   başka kullanıcıya ait id gönderilirse affected=false döner, hata üretilmez.
 *
 * Tablo: user_notifications
 *   Kolon: is_read TINYINT(1), read_at DATETIME — schema.sql'de mevcut, migration gerekmez.
 *
 * Faz 8C — Bearer token zorunlu, customer tipi.
 */

require_once __DIR__ . '/../../_bootstrap.php';
require_once __DIR__ . '/../../_auth.php';

wb_method('POST');

$session = mobile_auth($pdo, 'customer');
$userId  = $session['user_id'];

$in = wb_body();

// ── Mod: all veya single ──────────────────────────────────────────────────────
$markAll = !empty($in['all']);
$rawId   = $in['id'] ?? null;

if (!$markAll && ($rawId === null || $rawId === '')) {
    wb_err('id veya all:true zorunludur.', 422, 'missing_param');
}

try {
    if ($markAll) {
        // ── Tüm okunmamış bildirimleri okundu işaretle ────────────────────────
        $stmt = $pdo->prepare("
            UPDATE user_notifications
            SET is_read = 1, read_at = NOW()
            WHERE user_id = ? AND is_read = 0
        ");
        $stmt->execute([$userId]);
        $affected = $stmt->rowCount();

        wb_ok(['updated' => $affected > 0, 'count' => $affected]);

    } else {
        // ── Tek bildirim okundu işaretle ──────────────────────────────────────
        $notifId = (int)$rawId;
        if ($notifId < 1) {
            wb_err('Geçerli bir id girin.', 422, 'invalid_id');
        }

        $stmt = $pdo->prepare("
            UPDATE user_notifications
            SET is_read = 1, read_at = NOW()
            WHERE id = ? AND user_id = ? AND is_read = 0
        ");
        $stmt->execute([$notifId, $userId]);
        $affected = $stmt->rowCount();

        wb_ok(['updated' => $affected > 0]);
    }

} catch (Throwable $e) {
    error_log('[mobile/customer/notifications/read.php] ' . $e->getMessage());
    wb_err('Bildirim güncellenemedi.', 500, 'internal_error');
}
