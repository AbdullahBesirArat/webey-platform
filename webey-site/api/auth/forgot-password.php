<?php
// api/auth/forgot-password.php — Şifre sıfırlama emaili gönder
declare(strict_types=1);

// BUG FIX: _public_bootstrap kullan — şifre sıfırlama giriş gerektirmez.
// Eski kod _bootstrap.php kullanıyordu, bu yüzden giriş yapmamış kullanıcılar 401 alıyordu.
require_once __DIR__ . '/../_public_bootstrap.php';
require_once __DIR__ . '/../_mailer.php';
require_once __DIR__ . '/../_email_templates.php';
require_once __DIR__ . '/../_email_templates_auth.php';

wb_method('POST');
// BUG FIX: wb_csrf_verify çağrısı kaldırıldı — _public_bootstrap zaten çağırıyor (strict=false).

$data  = wb_body();
$email = strtolower(trim((string)($data['email'] ?? '')));

if (!$email || !filter_var($email, FILTER_VALIDATE_EMAIL)) {
    wb_err('Geçerli bir email adresi girin', 400, 'invalid_email');
}

// Hep aynı mesaj döndür (email varlığını sızdırma)
$genericMsg = 'Eğer bu adres kayıtlıysa şifre sıfırlama emaili gönderildi';

try {
    $stmt = $pdo->prepare("SELECT id, email, reset_token, reset_token_expires FROM users WHERE email = ? LIMIT 1");
    $stmt->execute([$email]);
    $user = $stmt->fetch();

    if (!$user) {
        wb_ok(['message' => $genericMsg]);
    }

    $tz        = new DateTimeZone('Europe/Istanbul');
    $now       = new DateTimeImmutable('now', $tz);
    $token     = '';
    $expiresAt = null;

    if (!empty($user['reset_token_expires'])) {
        $expiresAt = new DateTimeImmutable((string)$user['reset_token_expires'], $tz);
        $createdAt = $expiresAt->modify('-1 hour');
        $diff      = $now->getTimestamp() - $createdAt->getTimestamp();
        if ($diff < 300) {
            $wait = 300 - $diff;
            wb_err("Lütfen {$wait} saniye bekleyip tekrar deneyin", 429, 'rate_limited');
        }
    }

    $hasActiveToken = !empty($user['reset_token'])
        && $expiresAt instanceof DateTimeImmutable
        && $expiresAt > $now;

    if ($hasActiveToken) {
        $token = (string)$user['reset_token'];
    } else {
        $token     = bin2hex(random_bytes(32));
        $expiresAt = $now->modify('+1 hour');

        $pdo->prepare("UPDATE users SET reset_token = ?, reset_token_expires = ? WHERE id = ?")
            ->execute([$token, $expiresAt->format('Y-m-d H:i:s'), (int)$user['id']]);
    }

    $cfg      = require __DIR__ . '/../_email_config.php';
    $resetUrl = rtrim($cfg['site_url'], '/') . '/sifre-sifirla.html?token=' . $token;
    [$subject, $html] = wbEmailPasswordReset(['name' => $user['email'], 'resetUrl' => $resetUrl]);
    $mailSent = wbMail($user['email'], $user['email'], $subject, $html);
    if (!$mailSent) {
        $mailErr = wbMailGetLastError();
        error_log('[forgot-password] mail_failed provider=' . ($mailErr['provider'] ?? '') . ' code=' . ($mailErr['code'] ?? '') . ' message=' . ($mailErr['message'] ?? ''));
    }

    wb_ok(['message' => $genericMsg]);

} catch (Throwable $e) {
    error_log('[forgot-password] ' . $e->getMessage());
    // Güvenlik: hata detayı verme, generic mesaj dön
    wb_ok(['message' => $genericMsg]);
}
