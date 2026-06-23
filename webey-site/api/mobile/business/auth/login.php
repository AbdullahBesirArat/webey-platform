<?php
declare(strict_types=1);

require_once __DIR__ . '/../../_bootstrap.php';
require_once __DIR__ . '/../../_auth.php';

wb_method('POST');

// TODO(mobile): IP/device bazlı business login rate limit Faz 3'te eklenmeli.
$body = wb_body();
$email = strtolower(trim((string)($body['email'] ?? '')));
$password = (string)($body['password'] ?? '');

if ($email === '' || !filter_var($email, FILTER_VALIDATE_EMAIL) || $password === '') {
    wb_err('E-posta veya şifre hatalı', 401, 'invalid_credentials');
}

try {
    $stmt = $pdo->prepare("
        SELECT u.id, u.password_hash, u.role, au.id AS admin_id, b.id AS business_id
        FROM users u
        INNER JOIN admin_users au ON au.user_id = u.id
        LEFT JOIN businesses b ON b.owner_id = u.id
        WHERE u.email = ?
          AND u.role IN ('admin', 'superadmin')
        LIMIT 1
    ");
    $stmt->execute([$email]);
    $user = $stmt->fetch();

    if (!$user || empty($user['password_hash']) || !password_verify($password, (string)$user['password_hash'])) {
        wb_err('E-posta veya şifre hatalı', 401, 'invalid_credentials');
    }

    $userId = (int)$user['id'];
    $userType = !empty($user['business_id']) ? 'business' : 'admin';

    $pdo->prepare('UPDATE users SET last_login_at = NOW() WHERE id = ?')->execute([$userId]);

    $session = mobile_create_session($pdo, $userType, $userId, $body);
    $payload = mobile_user_payload($pdo, $userType, $userId);

    wb_ok([
        'token' => $session['token'],
        'token_type' => $session['token_type'],
        'expires_in' => $session['expires_in'],
        'user' => $payload,
    ]);
} catch (Throwable $e) {
    error_log('[mobile/business/auth/login.php] ' . $e->getMessage());
    wb_err('Giriş yapılamadı. Lütfen tekrar deneyin.', 500, 'internal_error');
}
