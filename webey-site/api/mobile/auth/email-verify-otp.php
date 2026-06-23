<?php
// api/mobile/auth/email-verify-otp.php  (Customer)
// POST { email, code, purpose?: register|login|password_reset|email_verify }
// Doğru kodda used_at set edilir; register/şifre-sıfırlama "recently_verified" kontrolüyle ilerler.
declare(strict_types=1);

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_email_otp.php';

wb_method('POST');

$in = wb_body();
$email = mobile_email_otp_norm((string)($in['email'] ?? ''));
$purpose = mobile_email_otp_purpose($in['purpose'] ?? 'register');

$res = mobile_email_otp_check($pdo, $email, (string)($in['code'] ?? ''), $purpose);

if (empty($res['ok'])) {
    $extra = array_key_exists('remaining', $res) ? ['remaining' => $res['remaining']] : [];
    wb_err((string)$res['message'], (int)$res['http'], (string)$res['code'], $extra);
}

wb_ok([
    'verified' => true,
    'email' => $email,
    'purpose' => $purpose,
]);
