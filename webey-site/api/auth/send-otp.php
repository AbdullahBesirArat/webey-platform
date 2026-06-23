<?php
// api/auth/send-otp.php
// Telefon numarasına 6 haneli SMS doğrulama kodu gönderir
// POST { phone: "5321234567" }
// debug=true → kod göndermez, kodu response'da döndürür
declare(strict_types=1);

require_once __DIR__ . '/../_public_bootstrap.php';
require_once __DIR__ . '/../_sms.php';

wb_method('POST');

$in    = wb_body();
$phone = preg_replace('/\D/', '', (string)($in['phone'] ?? ''));
$purpose = in_array($in['purpose'] ?? '', ['register','login','phone_change'], true)
         ? $in['purpose'] : 'register';

// Telefon formatı: 5XXXXXXXXX (10 hane)
if (!preg_match('/^5\d{9}$/', $phone)) {
    wb_err('Geçerli bir telefon numarası girin (5XX XXX XX XX)', 400, 'invalid_phone');
}

// ── Rate limiting: aynı telefona 1 dakikada max 3 OTP ───────────────
try {
    $rateCheck = $pdo->prepare("
        SELECT COUNT(*) FROM otp_tokens
        WHERE phone=? AND created_at > DATE_SUB(NOW(), INTERVAL 1 MINUTE) AND purpose=?
    ");
    $rateCheck->execute([$phone, $purpose]);
    if ((int)$rateCheck->fetchColumn() >= 3) {
        wb_err('Çok fazla deneme. 1 dakika bekleyin.', 429, 'rate_limited');
    }
} catch (Throwable) {}

// ── Eski token'ları temizle ──────────────────────────────────────────
try {
    $pdo->prepare("DELETE FROM otp_tokens WHERE phone=? AND purpose=? AND (expires_at < NOW() OR used_at IS NOT NULL)")
        ->execute([$phone, $purpose]);
} catch (Throwable) {}

// ── Yeni OTP üret ────────────────────────────────────────────────────
$cfg_pre = require __DIR__ . '/../_sms_config.php';
$code    = !empty($cfg_pre['debug']) ? '123456' : str_pad((string)random_int(0, 999999), 6, '0', STR_PAD_LEFT);
$ip      = trim(explode(',', $_SERVER['HTTP_X_FORWARDED_FOR'] ?? $_SERVER['REMOTE_ADDR'] ?? '')[0]);

try {
    $pdo->prepare("
        INSERT INTO otp_tokens (phone, code, purpose, attempts, expires_at, ip, created_at)
        VALUES (?, ?, ?, 0, DATE_ADD(NOW(), INTERVAL 5 MINUTE), ?, NOW())
    ")->execute([$phone, password_hash($code, PASSWORD_BCRYPT), $purpose, $ip]);
} catch (Throwable $e) {
    error_log('[send-otp] DB: ' . $e->getMessage());
    wb_err('Kod oluşturulamadı', 500);
}

// ── SMS gönder ───────────────────────────────────────────────────────
$cfg = require __DIR__ . '/../_sms_config.php';

if ($cfg['debug']) {
    // Debug modunda kodu direkt response'a koy (geliştirme kolaylığı)
    error_log('[OTP DEBUG] phone:' . $phone . ' code:' . $code);
    wb_ok([
        'sent'      => true,
        'debug'     => true,
        'message'   => 'Kod gönderildi (debug modu)',
        'expires_in'=> 300,
    ]);
}

$message = "Webey doğrulama kodunuz: {$code}\nBu kodu kimseyle paylaşmayın. 5 dakika geçerlidir.";
$ok = wbSms($phone, $message);

if (!$ok) {
    // SMS gitmedi ama token DB'de duruyor — kullanıcıya hata göster
    error_log('[send-otp] SMS gönderilemedi: ' . $phone);
    wb_err('SMS gönderilemedi. Lütfen tekrar deneyin.', 500, 'sms_failed');
}

wb_ok([
    'sent'      => true,
    'message'   => 'Doğrulama kodu gönderildi',
    'expires_in'=> 300,
]);
