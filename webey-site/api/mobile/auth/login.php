<?php
declare(strict_types=1);

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';

wb_method('POST');

// TODO(mobile): IP/device bazlı login rate limit Faz 3'te eklenmeli.
$body = wb_body();
$email = strtolower(trim((string)($body['email'] ?? '')));
$password = (string)($body['password'] ?? '');

if ($email === '' || !filter_var($email, FILTER_VALIDATE_EMAIL) || $password === '') {
    wb_err('E-posta veya şifre hatalı', 401, 'invalid_credentials');
}

try {
    $stmt = $pdo->prepare("
        SELECT u.id, u.password_hash
        FROM users u
        LEFT JOIN customers c ON c.user_id = u.id
        WHERE (u.email = ? OR c.email = ?)
          AND u.role = 'user'
        LIMIT 1
    ");
    $stmt->execute([$email, $email]);
    $user = $stmt->fetch();

    if (!$user || empty($user['password_hash']) || !password_verify($password, (string)$user['password_hash'])) {
        wb_err('E-posta veya şifre hatalı', 401, 'invalid_credentials');
    }

    $userId = (int)$user['id'];
    $pdo->prepare('UPDATE users SET last_login_at = NOW() WHERE id = ?')->execute([$userId]);

    $session = mobile_create_session($pdo, 'customer', $userId, $body);
    $payload = mobile_user_payload($pdo, 'customer', $userId);

    wb_ok([
        'token' => $session['token'],
        'token_type' => $session['token_type'],
        'expires_in' => $session['expires_in'],
        'user' => $payload,
    ]);
} catch (Throwable $e) {
    error_log('[mobile/auth/login.php] ' . $e->getMessage());
    wb_err('Giriş yapılamadı. Lütfen tekrar deneyin.', 500, 'internal_error');
}
