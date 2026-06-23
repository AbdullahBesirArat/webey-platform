<?php
declare(strict_types=1);

/**
 * api/_bootstrap.php
 * ──────────────────────────────────────────────────────────
 * Admin/barber oturumu gerektiren endpoint'ler bu dosyayı include eder.
 * Otomatik olarak:
 *   - JSON Content-Type header'ını ayarlar
 *   - Session başlatır
 *   - DB bağlantısı ($pdo) kurar
 *   - Oturum kontrolü yapar → yoksa 401 döner
 *   - $user array'ini tanımlar
 */

// ── Hata ayarları (üretimde display_errors KAPALI) ──
ini_set('display_errors', '0');
ini_set('display_startup_errors', '0');
error_reporting(E_ALL);

// ── Merkezi response yardımcısı ──
require_once __DIR__ . '/wb_response.php';

header('Content-Type: application/json; charset=utf-8');

// ── Session ──
if (session_status() === PHP_SESSION_NONE) {
    // HTTPS'de cookie'yi secure yap (HTTP localhost'ta çalışmaya devam eder)
    $isHttps = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off')
            || (($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https')
            || (($_SERVER['SERVER_PORT'] ?? '') === '443');
    ini_set('session.cookie_samesite',  'Lax');
    ini_set('session.cookie_httponly',  '1');
    ini_set('session.cookie_secure',    $isHttps ? '1' : '0');
    ini_set('session.use_strict_mode',  '1');   // Session fixation koruması
    ini_set('session.cookie_lifetime',  '0');   // Tarayıcı kapanınca sil
    ini_set('session.gc_maxlifetime',   '7200'); // 2 saat server-side TTL
    session_start();
}

// ── Veritabanı ──
require_once __DIR__ . '/../db.php';

// ── CSRF Koruması ──
// POST / PUT / DELETE isteklerinde X-CSRF-Token header'ı zorunludur.
// GET isteklerinde atlanır.
wb_csrf_verify(true); // strict=true: session token yoksa da reddet

// ── Auth guard ──
if (empty($_SESSION['user_id'])) {
    wb_err('Yetkisiz erişim', 401, 'unauthorized');
}

$user = [
    'user_id'     => (int)$_SESSION['user_id'],
    'admin_id'    => isset($_SESSION['admin_id'])    ? (int)$_SESSION['admin_id']    : null,
    'business_id' => isset($_SESSION['business_id']) ? (int)$_SESSION['business_id'] : null,
];