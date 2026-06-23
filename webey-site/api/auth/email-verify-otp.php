<?php
// api/auth/email-verify-otp.php
// Verifies email OTP code
// POST { email, code, purpose?: "email_verify" | "password_reset" }
declare(strict_types=1);

require_once __DIR__ . '/../_public_bootstrap.php';

wb_method('POST');

$in = wb_body();
$email = strtolower(trim((string)($in['email'] ?? '')));
$code = trim((string)($in['code'] ?? ''));
$purposeIn = (string)($in['purpose'] ?? 'email_verify');
$purpose = in_array($purposeIn, ['email_verify', 'password_reset'], true) ? $purposeIn : 'email_verify';

if (!$email || !filter_var($email, FILTER_VALIDATE_EMAIL)) {
    wb_err('Geçersiz email adresi', 400, 'invalid_email');
}
if (!preg_match('/^\d{6}$/', $code)) {
    wb_err('Geçersiz kod formatı', 400, 'invalid_code');
}

try {
    $stmt = $pdo->prepare("\n        SELECT id, code, attempts\n        FROM email_otp_tokens\n        WHERE email = ? AND purpose = ?\n          AND expires_at > NOW()\n          AND used_at IS NULL\n        ORDER BY created_at DESC\n        LIMIT 1\n    ");
    $stmt->execute([$email, $purpose]);
    $token = $stmt->fetch();

    if (!$token) {
        wb_err('Kod bulunamadı veya süresi dolmuş. Yeni kod isteyin.', 410, 'token_expired');
    }

    if ((int)$token['attempts'] >= 5) {
        wb_err('Çok fazla yanlış deneme. Yeni kod isteyin.', 429, 'too_many_attempts');
    }

    if (!password_verify($code, $token['code'])) {
        $pdo->prepare('UPDATE email_otp_tokens SET attempts = attempts + 1 WHERE id = ?')
            ->execute([$token['id']]);
        $remaining = max(0, 4 - (int)$token['attempts']);
        wb_err("Yanlış kod. {$remaining} deneme hakkınız kaldı.", 400, 'wrong_code');
    }

    $pdo->prepare('UPDATE email_otp_tokens SET used_at = NOW() WHERE id = ?')
        ->execute([$token['id']]);

    if (!isset($_SESSION['email_otp_verified']) || !is_array($_SESSION['email_otp_verified'])) {
        $_SESSION['email_otp_verified'] = [];
    }
    if (!isset($_SESSION['email_otp_verified'][$purpose]) || !is_array($_SESSION['email_otp_verified'][$purpose])) {
        $_SESSION['email_otp_verified'][$purpose] = [];
    }

    // 10 dakika geçerli olacak şekilde session'a işaret koy
    $_SESSION['email_otp_verified'][$purpose][$email] = time() + 600;

    wb_ok(['verified' => true, 'email' => $email, 'purpose' => $purpose]);

} catch (Throwable $e) {
    error_log('[email-verify-otp] ' . $e->getMessage());
    wb_err('Doğrulama başarısız', 500, 'internal_error');
}
