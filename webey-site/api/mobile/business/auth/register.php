<?php
declare(strict_types=1);

require_once __DIR__ . '/../../_bootstrap.php';
require_once __DIR__ . '/../../_auth.php';
require_once __DIR__ . '/../../_email_otp.php';

wb_method('POST');

// TODO(mobile): IP/device bazlı business register rate limit Faz 3'te eklenmeli.
$body = wb_body();
$name = trim((string)($body['name'] ?? ''));
$email = strtolower(trim((string)($body['email'] ?? '')));
$phone = preg_replace('/\D+/', '', (string)($body['phone'] ?? ''));
$password = (string)($body['password'] ?? '');
$ownerName = trim((string)($body['owner_name'] ?? ''));

if (is_string($phone) && str_starts_with($phone, '90') && strlen($phone) === 12) {
    $phone = substr($phone, 2);
}
if (is_string($phone) && str_starts_with($phone, '0')) {
    $phone = substr($phone, 1);
}

if ($name === '') {
    wb_err('İşletme adı zorunlu', 422, 'validation_error');
}
if (mb_strlen($name) > 40) {
    wb_err('İşletme adı en fazla 40 karakter olabilir', 422, 'validation_error');
}
if ($email === '' || !filter_var($email, FILTER_VALIDATE_EMAIL)) {
    wb_err('Geçerli bir e-posta adresi girin', 422, 'validation_error');
}
if (mb_strlen($password) < 8) {
    wb_err('Şifre en az 8 karakter olmalı', 422, 'validation_error');
}
if (!is_string($phone) || !preg_match('/^5\d{9}$/', $phone)) {
    wb_err('Geçerli bir telefon numarası girin', 422, 'validation_error');
}
if ($ownerName !== '' && mb_strlen($ownerName) > 120) {
    $ownerName = mb_substr($ownerName, 0, 120);
}

// OTP-gated register: e-posta, hesap oluşturulmadan önce doğrulanmış olmalı.
if (!mobile_email_otp_recently_verified($pdo, $email, 'register')) {
    wb_err('E-posta adresinizi doğrulayın. Lütfen önce doğrulama kodunu girin.', 403, 'email_not_verified');
}

try {
    $pdo->beginTransaction();

    $emailStmt = $pdo->prepare("
        SELECT u.id
        FROM users u
        LEFT JOIN customers c ON c.user_id = u.id
        WHERE u.email = ? OR c.email = ?
        LIMIT 1
        FOR UPDATE
    ");
    $emailStmt->execute([$email, $email]);
    if ($emailStmt->fetchColumn()) {
        $pdo->rollBack();
        wb_err('Bu e-posta adresi zaten kayıtlı', 409, 'email_exists');
    }

    $hash = password_hash($password, PASSWORD_BCRYPT, ['cost' => 11]);

    $pdo->prepare("
        INSERT INTO users (email, name, password_hash, role, email_verified_at, created_at)
        VALUES (?, ?, ?, 'admin', NOW(), NOW())
    ")->execute([$email, $name, $hash]);
    $userId = (int)$pdo->lastInsertId();

    if ($userId <= 0) {
        throw new RuntimeException('User insert failed');
    }

    $pdo->prepare("
        INSERT INTO admin_users (user_id, onboarding_completed, created_at)
        VALUES (?, 0, NOW())
    ")->execute([$userId]);

    $pdo->prepare("
        INSERT INTO businesses
            (owner_id, name, owner_name, phone, type, status, onboarding_step, onboarding_completed)
        VALUES
            (?, ?, ?, ?, 'kuafor', 'draft', 1, 0)
    ")->execute([
        $userId,
        $name,
        $ownerName !== '' ? $ownerName : null,
        $phone,
    ]);

    $pdo->commit();

    // Kullanılan kayıt OTP'sini tüket (tekrar kullanılamasın).
    mobile_email_otp_consume($pdo, $email, 'register');

    $session = mobile_create_session($pdo, 'business', $userId, $body);
    $payload = mobile_user_payload($pdo, 'business', $userId);

    wb_ok([
        'token' => $session['token'],
        'token_type' => $session['token_type'],
        'expires_in' => $session['expires_in'],
        'user' => $payload,
    ], 201);
} catch (Throwable $e) {
    if (isset($pdo) && $pdo->inTransaction()) {
        $pdo->rollBack();
    }
    if ($e->getCode() === '23000' || str_contains($e->getMessage(), 'Duplicate entry')) {
        wb_err('Bu e-posta veya telefon zaten kayıtlı', 409, 'duplicate_account');
    }
    error_log('[mobile/business/auth/register.php] ' . $e->getMessage());
    wb_err('Kayıt başarısız. Lütfen tekrar deneyin.', 500, 'internal_error');
}
