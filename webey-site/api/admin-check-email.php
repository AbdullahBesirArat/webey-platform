<?php
// api/admin-check-email.php — Admin kayıt sırasında email müsaitlik kontrolü
// Rate-limited: IP başına 1 saniye
declare(strict_types=1);

// FIX: Admin kayıt sırasında kullanılır — giriş öncesi çağrılır, public olmalı.
// _bootstrap.php auth zorunlu kılıyordu, kayıt formu email kontrolü yapamıyordu.
require_once __DIR__ . '/_public_bootstrap.php';

wb_method('POST');

// Basit IP rate-limit (1 saniye)
try {
    $ip   = $_SERVER['REMOTE_ADDR'] ?? '0.0.0.0';
    $f    = sys_get_temp_dir() . '/emailchk_' . sha1($ip) . '.txt';
    $now  = time();
    $last = is_file($f) ? (int)@file_get_contents($f) : 0;
    if ($now - $last < 1) {
        wb_err('Çok hızlı deneme, lütfen bekleyin', 429, 'rate_limited');
    }
    @file_put_contents($f, (string)$now);
} catch (Throwable) {
    // rate-limit başarısız olursa devam et
}

$data  = wb_body();
$email = strtolower(trim((string)($data['email'] ?? '')));

if (!$email || !filter_var($email, FILTER_VALIDATE_EMAIL)) {
    wb_ok(['available' => true]); // geçersiz email → sessizce geçer
}

try {
    // Privacy-hardening: do not leak account existence.
    wb_ok(['available' => true]);

} catch (Throwable $e) {
    error_log('[admin-check-email] ' . $e->getMessage());
    wb_err('Sunucu hatası', 500, 'internal_error');
}
