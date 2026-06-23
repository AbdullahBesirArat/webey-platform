<?php
// api/mobile/business/auth/password-reset-request.php  (Business)
// POST { email } -> purpose=password_reset OTP gönderir (enumeration-safe).
declare(strict_types=1);

require_once __DIR__ . '/../../_bootstrap.php';
require_once __DIR__ . '/../../_email_otp.php';

wb_method('POST');

$in = wb_body();
$email = mobile_email_otp_norm((string)($in['email'] ?? ''));
if ($email === '' || !filter_var($email, FILTER_VALIDATE_EMAIL)) {
    wb_err('Geçerli bir e-posta adresi girin', 422, 'invalid_email');
}

$exists = false;
try {
    $stmt = $pdo->prepare(
        "SELECT 1 FROM users u INNER JOIN admin_users au ON au.user_id = u.id
         WHERE u.email = ? AND u.role = 'admin' LIMIT 1"
    );
    $stmt->execute([$email]);
    $exists = (bool)$stmt->fetchColumn();
} catch (Throwable $e) {
    error_log('[mobile/business/auth/password-reset-request] ' . $e->getMessage());
}

if ($exists) {
    mobile_email_otp_generate_send($pdo, $email, 'password_reset');
}

wb_ok([
    'sent' => true,
    'message' => 'Doğrulama kodu e-posta adresinize gönderildi.',
    'expires_in' => 600,
    'purpose' => 'password_reset',
]);
