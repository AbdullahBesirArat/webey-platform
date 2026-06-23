<?php
declare(strict_types=1);
/**
 * api/user/me.php — Geriye Dönük Uyumluluk Shim
 * ────────────────────────────────────────────────
 * index.js, kuafor.js, user-profile.js bu endpoint'i çağırıyor.
 * Artık session/me.php'e yönlendiriyor — response formatı aynı.
 *
 * YENİ KOD: /api/session/me.php kullan.
 */
require __DIR__ . '/../session/me.php';