<?php
// api/mobile/business/auth/email-send-otp.php  (Business)
// POST { email, purpose?: register|login|password_reset|email_verify }
declare(strict_types=1);

require_once __DIR__ . '/../../_bootstrap.php';
require_once __DIR__ . '/../../_email_otp.php';

wb_method('POST');

$in = wb_body();
mobile_email_otp_generate_send(
    $pdo,
    (string)($in['email'] ?? ''),
    (string)($in['purpose'] ?? 'register')
);
