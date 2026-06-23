<?php
declare(strict_types=1);

require_once __DIR__ . '/../_public_bootstrap.php';
require_once __DIR__ . '/../_google_auth.php';

wb_method('POST');
wb_csrf_verify(true);

$data = wb_body();
$credential = trim((string)($data['credential'] ?? ''));

if ($credential === '') {
    wb_err('Google token eksik', 400, 'missing_token');
}

$identity = wb_google_extract_identity($credential);
if (!$identity) {
    wb_err('Gecersiz Google token', 401, 'invalid_token');
}

wb_ok([
    'email' => $identity['email'],
    'firstName' => $identity['first_name'],
    'lastName' => $identity['last_name'],
    'fullName' => $identity['full_name'],
    'avatar' => $identity['avatar'],
]);
