<?php
// api/auth/reset-password.php — Token ile yeni şifre belirle
declare(strict_types=1);

// BUG FIX: _public_bootstrap kullan — şifre sıfırlama giriş gerektirmez.
// Eski kod _bootstrap.php kullanıyordu, bu yüzden token ile şifre sıfırlanamıyordu.
require_once __DIR__ . '/../_public_bootstrap.php';

wb_method('POST');
// BUG FIX: wb_csrf_verify çağrısı kaldırıldı — _public_bootstrap zaten çağırıyor (strict=false).

$data     = wb_body();
$token    = trim((string)($data['token']    ?? ''));
$password = (string)($data['password']      ?? '');
$confirm  = (string)($data['confirm']       ?? '');

wb_validate(['token' => $token, 'password' => $password, 'confirm' => $confirm], [
    'token'    => ['required'],
    'password' => ['required'],
    'confirm'  => ['required'],
]);

if (strlen($token) < 32) {
    wb_err('Geçersiz token', 400, 'invalid_token');
}
if (mb_strlen($password) < 8) {
    wb_err('Şifre en az 8 karakter olmalıdır', 400, 'password_too_short');
}
if ($password !== $confirm) {
    wb_err('Şifreler eşleşmiyor', 400, 'password_mismatch');
}

try {
    $stmt = $pdo->prepare("
        SELECT id FROM users
        WHERE reset_token = ?
          AND reset_token_expires > NOW()
        LIMIT 1
    ");
    $stmt->execute([$token]);
    $user = $stmt->fetch();

    if (!$user) {
        wb_err('Bu link geçersiz veya süresi dolmuş. Yeni bir sıfırlama emaili talep edin.', 410, 'token_expired');
    }

    $hash = password_hash($password, PASSWORD_BCRYPT, ['cost' => 11]);

    $pdo->prepare("
        UPDATE users
        SET password_hash      = ?,
            reset_token         = NULL,
            reset_token_expires = NULL
        WHERE id = ?
    ")->execute([$hash, (int)$user['id']]);

    wb_ok(['message' => 'Şifreniz başarıyla güncellendi']);

} catch (Throwable $e) {
    error_log('[reset-password] ' . $e->getMessage());
    wb_err('Sunucu hatası, lütfen tekrar deneyin', 500, 'internal_error');
}