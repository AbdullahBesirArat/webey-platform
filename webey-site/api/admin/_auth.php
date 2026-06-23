<?php
declare(strict_types=1);

/**
 * api/admin/_auth.php — SHIM (Geçiş Katmanı)
 * ══════════════════════════════════════════════════════════════
 * Bu dosya artık yalnızca geriye dönük uyumluluk için duruyor.
 * YENİ endpoint'lerde _auth.php DEĞİL, _bootstrap.php kullan:
 *
 *   require_once __DIR__ . '/_bootstrap.php';   ✅ DOĞRU
 *   require_once __DIR__ . '/_auth.php';         ❌ ESKİ
 *
 * _auth.php kullanan mevcut dosyalar çalışmaya devam eder çünkü
 * bu shim, _bootstrap.php'yi include eder.
 * Dosyaları Faz 2'de tek tek _bootstrap.php'ye geçireceğiz.
 * ══════════════════════════════════════════════════════════════
 */

require_once __DIR__ . '/_bootstrap.php';

// Geriye dönük uyumluluk için eski değişken adları
// (eski endpoint'ler $user_id ve $admin_id kullanıyor)
$user_id  = $user['user_id'];
$admin_id = $user['admin_id'];