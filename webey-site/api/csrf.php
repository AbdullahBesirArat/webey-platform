<?php
declare(strict_types=1);
/**
 * api/csrf.php — CSRF Token Endpoint'i
 * ══════════════════════════════════════════════════════════════
 * GET  /api/csrf.php  → { ok: true, data: { token: "..." } }
 *
 * Frontend sayfa yüklenince bu endpoint'i çağırır, aldığı token'ı
 * bellekte saklar ve tüm POST/PUT/DELETE isteklerinde
 *   X-CSRF-Token: <token>
 * header'ı olarak gönderir.
 *
 * Token 2 saat geçerlidir. Session'a bağlıdır.
 * ══════════════════════════════════════════════════════════════
 */

require_once __DIR__ . '/wb_response.php';

// Session başlat (token session'da saklanır)
if (session_status() === PHP_SESSION_NONE) {
    $isHttps = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off')
            || (($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https')
            || (($_SERVER['SERVER_PORT'] ?? '') === '443');
    ini_set('session.cookie_samesite',  'Lax');
    ini_set('session.cookie_httponly',  '1');
    ini_set('session.cookie_secure',    $isHttps ? '1' : '0');
    ini_set('session.use_strict_mode',  '1');
    session_start();
}

// Sadece GET kabul et
wb_method('GET');

// Token üret veya mevcut olanı döndür
$token = wb_csrf_token();

// Cache'e alınmasın
header('Cache-Control: no-store, no-cache');
header('Pragma: no-cache');

wb_ok(['token' => $token]);