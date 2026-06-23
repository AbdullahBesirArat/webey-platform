<?php
// api/auth/email-send-otp.php
// Sends a 6-digit OTP to email address
// POST { email: "user@example.com", purpose?: "email_verify" | "password_reset" }
declare(strict_types=1);

require_once __DIR__ . '/../_public_bootstrap.php';
require_once __DIR__ . '/../_mailer.php';

wb_method('POST');

$in = wb_body();
$email = strtolower(trim((string)($in['email'] ?? '')));
$purposeIn = (string)($in['purpose'] ?? 'email_verify');
$purpose = in_array($purposeIn, ['email_verify', 'password_reset'], true) ? $purposeIn : 'email_verify';

if (!$email || !filter_var($email, FILTER_VALIDATE_EMAIL)) {
    wb_err('Geçerli bir email adresi girin', 400, 'invalid_email');
}

try {
    $rateCheck = $pdo->prepare("\n        SELECT COUNT(*) FROM email_otp_tokens\n        WHERE email = ? AND created_at > DATE_SUB(NOW(), INTERVAL 1 MINUTE)\n          AND purpose = ?\n    ");
    $rateCheck->execute([$email, $purpose]);
    if ((int)$rateCheck->fetchColumn() >= 3) {
        wb_err('Çok fazla deneme. 1 dakika bekleyin.', 429, 'rate_limited');
    }
} catch (Throwable) {
}

try {
    $pdo->prepare("DELETE FROM email_otp_tokens WHERE email = ? AND purpose = ?")
        ->execute([$email, $purpose]);
} catch (Throwable) {
}

$cfgPre = require __DIR__ . '/../_email_config.php';
$code = !empty($cfgPre['debug']) ? '123456' : str_pad((string)random_int(0, 999999), 6, '0', STR_PAD_LEFT);
$hash = password_hash($code, PASSWORD_BCRYPT);
$ip = trim(explode(',', $_SERVER['HTTP_X_FORWARDED_FOR'] ?? $_SERVER['REMOTE_ADDR'] ?? '')[0]);

try {
    $pdo->prepare("\n        INSERT INTO email_otp_tokens (email, code, purpose, attempts, expires_at, ip, created_at)\n        VALUES (?, ?, ?, 0, DATE_ADD(NOW(), INTERVAL 5 MINUTE), ?, NOW())\n    ")->execute([$email, $hash, $purpose, $ip]);
} catch (Throwable $e) {
    error_log('[email-send-otp] DB: ' . $e->getMessage());
    wb_err('Kod oluşturulamadı', 500);
}

$subjectTitle = $purpose === 'password_reset' ? 'Şifre Sıfırlama Kodu' : 'Email Doğrulama';
$bodyLead = $purpose === 'password_reset'
    ? 'Webey hesabınız için şifre sıfırlama kodunuz:'
    : 'Webey hesabı için doğrulama kodunuz:';

$html  = "<!DOCTYPE html><html lang='tr'><head><meta charset='UTF-8'/></head><body>";
$html .= "<div style='font-family:Inter,Arial,sans-serif;max-width:480px;margin:0 auto;padding:32px 16px;'>";
$html .= "<h2 style='color:#19a0b6;text-align:center;margin-bottom:8px;'>{$subjectTitle}</h2>";
$html .= "<p style='color:#374151;font-size:15px;text-align:center;'>{$bodyLead}</p>";
$html .= "<div style='background:#f0fdfa;border:2px solid #19a0b6;border-radius:16px;padding:24px;text-align:center;margin:24px 0;'>";
$html .= "<span style='font-size:40px;font-weight:900;letter-spacing:12px;color:#111827;'>{$code}</span>";
$html .= "</div>";
$html .= "<p style='color:#9ca3af;font-size:13px;text-align:center;'>Bu kod <strong>5 dakika</strong> geçerlidir.</p>";
$html .= "<p style='color:#9ca3af;font-size:12px;text-align:center;'>Bu emaili siz talep etmediyseniz görmezden gelebilirsiniz.</p>";
$html .= "</div></body></html>";

$text = ($purpose === 'password_reset')
    ? "Webey şifre sıfırlama kodunuz: {$code}\nBu kod 5 dakika geçerlidir."
    : "Webey email doğrulama kodunuz: {$code}\nBu kod 5 dakika geçerlidir.";

if (!empty($cfgPre['debug'])) {
    error_log('[EMAIL OTP DEBUG] email:' . $email . ' code:' . $code . ' purpose:' . $purpose);
    wb_ok([
        'sent' => true,
        'debug' => true,
        'message' => 'Kod gönderildi (debug modu)',
        'expires_in' => 300,
        'purpose' => $purpose,
    ]);
}

$mailSubject = $purpose === 'password_reset'
    ? 'Webey - Şifre Sıfırlama Kodu'
    : 'Webey - Email Doğrulama Kodu';

$sent = wbMail($email, $email, $mailSubject, $html, $text);

if (!$sent) {
    $mailErr = function_exists('wbMailGetLastError') ? wbMailGetLastError() : ['code' => 'unknown', 'provider' => ''];
    $reason = (string)($mailErr['code'] ?? 'unknown');
    $provider = (string)($mailErr['provider'] ?? '');
    error_log('[email-send-otp] wbMail failed: ' . $email . ' reason:' . $reason);
    wb_err('Email gönderilemedi. Lütfen tekrar deneyin.', 500, 'mail_failed', [
        'reason' => $reason,
        'provider' => $provider,
    ]);
}

wb_ok([
    'sent' => true,
    'message' => 'Doğrulama kodu email adresinize gönderildi',
    'expires_in' => 300,
    'purpose' => $purpose,
]);
