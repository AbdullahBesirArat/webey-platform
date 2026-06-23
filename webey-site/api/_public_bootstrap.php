<?php
declare(strict_types=1);

/**
 * api/_public_bootstrap.php
 * ══════════════════════════════════════════════════════════════
 * Auth gerektirmeyen (public) endpoint'ler için standart bootstrap.
 * Bu dosyayı include eden her endpoint otomatik olarak:
 *   - JSON Content-Type header'ı alır
 *   - Session güvenli şekilde başlatılır (opsiyonel oturum bilgisi için)
 *   - DB bağlantısı ($pdo) kurulur
 *   - CSRF koruması uygulanır: session token varsa doğrular (strict=false)
 *   - Auth guard YOKTUR — giriş yapılmamış kullanıcılar erişebilir
 *
 * Kullanım:
 *   require_once __DIR__ . '/_public_bootstrap.php';
 *   wb_method('GET');
 *   wb_ok([...]);
 *
 * ══════════════════════════════════════════════════════════════
 */

ini_set('display_errors', '0');
ini_set('display_startup_errors', '0');
error_reporting(E_ALL);

require_once __DIR__ . '/wb_response.php';
require_once __DIR__ . '/../db.php';

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

// ── Session (soft — auth yok, sadece oturum bilgisi okumak için) ─────────────
if (session_status() === PHP_SESSION_NONE) {
    $isHttps = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off')
            || (($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https')
            || (($_SERVER['SERVER_PORT'] ?? '') === '443');
    ini_set('session.cookie_samesite',  'Lax');
    ini_set('session.cookie_httponly',  '1');
    ini_set('session.cookie_secure',    $isHttps ? '1' : '0');
    ini_set('session.use_strict_mode',  '1');
    ini_set('session.cookie_lifetime',  '0');
    ini_set('session.gc_maxlifetime',   '7200');
    session_start();
}

// ── CSRF (strict=false: session token varsa doğrula, yoksa geç) ──────────────
wb_csrf_verify(false);