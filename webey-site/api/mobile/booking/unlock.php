<?php
declare(strict_types=1);
/**
 * api/mobile/booking/unlock.php
 * POST — slot kilidini serbest bırakır.
 *
 * Body (JSON):
 *   lock_token : string (zorunlu) — 48 karakter hex
 *
 * Token sahipliği = yetki kanıtı. Idempotent: kilit yoksa/dolmuşsa da ok döner.
 * Faz 5A — Bearer token zorunlu, customer tipi.
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';

wb_method('POST');

mobile_auth($pdo, 'customer');

$in        = wb_body();
$lockToken = trim((string)($in['lock_token'] ?? ''));

if ($lockToken === '' || !preg_match('/^[0-9a-f]{48}$/', $lockToken)) {
    wb_err('lock_token geçersiz (48 karakter hex bekleniyor)', 422, 'invalid_token');
}

try {
    $pdo->prepare(
        'DELETE FROM slot_locks WHERE lock_token = ? AND expires_at >= NOW()'
    )->execute([$lockToken]);
} catch (Throwable $e) {
    error_log('[mobile/booking/unlock.php] ' . $e->getMessage());
    wb_err('Kilit serbest bırakılamadı', 500, 'internal_error');
}

wb_ok(['unlocked' => true]);
