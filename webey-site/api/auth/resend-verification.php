<?php
// api/auth/resend-verification.php — Doğrulama emailini tekrar gönder (rate-limited: 5dk)
declare(strict_types=1);

// FIX: Email doğrulanmamış kullanıcı giriş yapamaz — bu endpoint public olmalı.
// _bootstrap.php auth zorunlu kılıyordu, doğrulama linki asla çalışmıyordu.
require_once __DIR__ . '/../_public_bootstrap.php';
require_once __DIR__ . '/../_mailer.php';
require_once __DIR__ . '/../_email_templates.php';
require_once __DIR__ . '/../_email_templates_auth.php';

wb_method('POST');
wb_csrf_verify(false);

$data  = wb_body();
$email = strtolower(trim((string)($data['email'] ?? $_SESSION['email'] ?? '')));

if (!$email || !filter_var($email, FILTER_VALIDATE_EMAIL)) {
    wb_err('Geçerli bir email adresi girin', 400, 'invalid_email');
}

try {
    $stmt = $pdo->prepare("
        SELECT id, email, email_verified_at, email_verify_sent_at
        FROM users WHERE email = ? LIMIT 1
    ");
    $stmt->execute([$email]);
    $user = $stmt->fetch();

    // Güvenlik: varlık sızdırma
    if (!$user) {
        wb_ok(['message' => 'Eğer bu adres kayıtlıysa email gönderildi']);
    }

    if ($user['email_verified_at']) {
        wb_err('Bu email zaten doğrulanmış', 400, 'already_verified');
    }

    // Rate limit: 5 dakikada bir (DB timezone-safe)
    if ($user['email_verify_sent_at']) {
        $tz   = new DateTimeZone('Europe/Istanbul');
        $sent = new DateTime($user['email_verify_sent_at'], $tz);
        $now  = new DateTime('now', $tz);
        $diff = $now->getTimestamp() - $sent->getTimestamp();
        if ($diff < 300 && $diff >= 0) {
            $wait = 300 - $diff;
            wb_err("Lütfen {$wait} saniye bekleyip tekrar deneyin", 429, 'rate_limited');
        }
        // diff negatifse (timezone kayması) engelleme
    }

    $token = bin2hex(random_bytes(32));
    $pdo->prepare("UPDATE users SET email_verify_token = ?, email_verify_sent_at = NOW() WHERE id = ?")
        ->execute([$token, (int)$user['id']]);

    $cfg       = require __DIR__ . '/../_email_config.php';
    $verifyUrl = rtrim($cfg['site_url'], '/') . '/email-dogrulandi.html?token=' . $token;
    [$subject, $html] = wbEmailVerify(['name' => $user['email'], 'verifyUrl' => $verifyUrl]);
    wbMail($user['email'], $user['email'], $subject, $html);

    wb_ok(['message' => 'Doğrulama emaili tekrar gönderildi']);

} catch (Throwable $e) {
    error_log('[resend-verification] ' . $e->getMessage());
    wb_err('Sunucu hatası', 500, 'internal_error');
}
