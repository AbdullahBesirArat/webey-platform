<?php
// api/mobile/business/auth/password-reset-confirm.php  (Business)
// POST { email, code, new_password } -> OTP doğrular ve yeni şifreyi kaydeder.
declare(strict_types=1);

require_once __DIR__ . '/../../_bootstrap.php';
require_once __DIR__ . '/../../_email_otp.php';

wb_method('POST');

$in = wb_body();
$email = mobile_email_otp_norm((string)($in['email'] ?? ''));
$code = (string)($in['code'] ?? '');
$newPassword = (string)($in['new_password'] ?? $in['password'] ?? '');

if ($email === '' || !filter_var($email, FILTER_VALIDATE_EMAIL)) {
    wb_err('Geçersiz e-posta adresi', 422, 'invalid_email');
}
if (mb_strlen($newPassword) < 8) {
    wb_err('Şifre en az 8 karakter olmalı', 422, 'weak_password');
}

$res = mobile_email_otp_check($pdo, $email, $code, 'password_reset');
if (empty($res['ok'])) {
    $extra = array_key_exists('remaining', $res) ? ['remaining' => $res['remaining']] : [];
    wb_err((string)$res['message'], (int)$res['http'], (string)$res['code'], $extra);
}

try {
    $stmt = $pdo->prepare(
        "SELECT u.id FROM users u INNER JOIN admin_users au ON au.user_id = u.id
         WHERE u.email = ? AND u.role = 'admin' LIMIT 1"
    );
    $stmt->execute([$email]);
    $userId = (int)$stmt->fetchColumn();
    if ($userId <= 0) {
        wb_err('Hesap bulunamadı', 404, 'user_not_found');
    }

    $hash = password_hash($newPassword, PASSWORD_BCRYPT, ['cost' => 11]);
    $pdo->prepare('UPDATE users SET password_hash = ?, email_verified_at = COALESCE(email_verified_at, NOW()) WHERE id = ?')
        ->execute([$hash, $userId]);

    mobile_email_otp_consume($pdo, $email, 'password_reset');

    wb_ok(['reset' => true, 'message' => 'Şifreniz güncellendi. Yeni şifrenizle giriş yapabilirsiniz.']);
} catch (Throwable $e) {
    error_log('[mobile/business/auth/password-reset-confirm] ' . $e->getMessage());
    wb_err('Şifre güncellenemedi. Lütfen tekrar deneyin.', 500, 'internal_error');
}
