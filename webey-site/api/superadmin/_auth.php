<?php
declare(strict_types=1);

/**
 * api/superadmin/_auth.php — SHIM (Geçiş Katmanı)
 * ══════════════════════════════════════════════════════════════
 * Bu dosya artık yalnızca geriye dönük uyumluluk için duruyor.
 * YENİ endpoint'lerde _auth.php DEĞİL, _bootstrap.php kullan:
 *
 *   require_once __DIR__ . '/_bootstrap.php';   ✅ DOĞRU
 *   require_once __DIR__ . '/_auth.php';         ❌ ESKİ
 * ══════════════════════════════════════════════════════════════
 */

require_once __DIR__ . '/_bootstrap.php';

// Geriye dönük uyumluluk
$saUserId = $user['user_id'];