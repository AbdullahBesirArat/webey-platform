<?php
declare(strict_types=1);

require_once __DIR__ . '/../_bootstrap.php';
wb_method('POST');

$userId = (int)$user['user_id'];
$in = wb_body();
$action = (string)($in['action'] ?? '');

/**
 * Session'da email OTP doğrulama işaretini kontrol eder.
 */
function wb_user_email_otp_verified(string $purpose, string $email): bool
{
    if (!isset($_SESSION['email_otp_verified']) || !is_array($_SESSION['email_otp_verified'])) return false;
    if (!isset($_SESSION['email_otp_verified'][$purpose]) || !is_array($_SESSION['email_otp_verified'][$purpose])) return false;
    $expiresAt = (int)($_SESSION['email_otp_verified'][$purpose][$email] ?? 0);
    return $expiresAt >= time();
}

/**
 * Session'daki OTP doğrulama işaretini temizler.
 */
function wb_clear_user_email_otp_verified(string $purpose, string $email): void
{
    if (isset($_SESSION['email_otp_verified'][$purpose][$email])) {
        unset($_SESSION['email_otp_verified'][$purpose][$email]);
    }
}

try {
    switch ($action) {

        case 'update_name': {
            $fn = trim((string)($in['firstName'] ?? ''));
            $ln = trim((string)($in['lastName'] ?? ''));
            $bd = trim((string)($in['birthday'] ?? ''));

            $pdo->prepare("\n                INSERT INTO customers (user_id, first_name, last_name, birthday)\n                VALUES (?, ?, ?, ?)\n                ON DUPLICATE KEY UPDATE\n                    first_name = VALUES(first_name),\n                    last_name = VALUES(last_name),\n                    birthday = VALUES(birthday),\n                    updated_at = NOW()\n            ")->execute([
                $userId,
                $fn ?: null,
                $ln ?: null,
                ($bd && preg_match('/^\d{4}-\d{2}-\d{2}$/', $bd)) ? $bd : null,
            ]);

            wb_ok(['saved' => true]);
            break;
        }

        case 'update_address': {
            $city = trim((string)($in['city'] ?? ''));
            $dist = trim((string)($in['district'] ?? ''));
            $nbhd = trim((string)($in['neighborhood'] ?? ''));

            if (!$city || !$dist) {
                wb_err('İl ve ilçe zorunlu', 422, 'validation_error');
            }

            $pdo->prepare("\n                INSERT INTO customers (user_id, city, district, neighborhood)\n                VALUES (?, ?, ?, ?)\n                ON DUPLICATE KEY UPDATE\n                    city = VALUES(city),\n                    district = VALUES(district),\n                    neighborhood = VALUES(neighborhood),\n                    updated_at = NOW()\n            ")->execute([$userId, $city, $dist, $nbhd ?: null]);

            wb_ok(['saved' => true]);
            break;
        }

        case 'update_email': {
            $email = strtolower(trim((string)($in['email'] ?? '')));
            if (!$email || !filter_var($email, FILTER_VALIDATE_EMAIL)) {
                wb_err('Geçersiz e-posta', 422, 'validation_error');
            }

            $chk = $pdo->prepare('SELECT id FROM customers WHERE email = ? AND user_id != ? LIMIT 1');
            $chk->execute([$email, $userId]);
            if ($chk->fetchColumn()) {
                wb_err('Bu e-posta başka bir hesapta kayıtlı', 409, 'email_taken');
            }

            if (!wb_user_email_otp_verified('email_verify', $email)) {
                wb_err('E-posta doğrulama kodunu girip doğrulayın', 403, 'email_otp_required');
            }

            $pdo->prepare("\n                INSERT INTO customers (user_id, email, email_ok) VALUES (?, ?, 1)\n                ON DUPLICATE KEY UPDATE\n                    email = VALUES(email),\n                    email_ok = 1,\n                    updated_at = NOW()\n            ")->execute([$userId, $email]);

            wb_clear_user_email_otp_verified('email_verify', $email);
            wb_ok(['email' => $email, 'emailOk' => true]);
            break;
        }

        case 'update_phone': {
            $phone = preg_replace('/\D+/', '', (string)($in['phone'] ?? ''));
            if (!$phone || !preg_match('/^5\d{9}$/', $phone)) {
                wb_err('Geçersiz telefon (5xxxxxxxxx)', 422, 'validation_error');
            }

            $pseudoEmail = $phone . '@phone.user';
            $chk = $pdo->prepare('SELECT id FROM users WHERE email = ? AND id != ? LIMIT 1');
            $chk->execute([$pseudoEmail, $userId]);
            if ($chk->fetchColumn()) {
                wb_err('Bu numara başka bir hesapta kayıtlı', 409, 'phone_taken');
            }

            $pdo->prepare('UPDATE users SET email = ? WHERE id = ?')->execute([$pseudoEmail, $userId]);
            $pdo->prepare("\n                INSERT INTO customers (user_id, phone) VALUES (?, ?)\n                ON DUPLICATE KEY UPDATE phone = VALUES(phone), updated_at = NOW()\n            ")->execute([$userId, $phone]);

            $_SESSION['user_phone'] = $phone;
            wb_ok(['phone' => $phone]);
            break;
        }

        case 'change_password': {
            $cur = (string)($in['currentPassword'] ?? '');
            $new = (string)($in['newPassword'] ?? '');

            if (!$cur || !$new) {
                wb_err('Mevcut ve yeni şifre zorunlu', 422, 'validation_error');
            }
            if (mb_strlen($new) < 8) {
                wb_err('Yeni şifre en az 8 karakter olmalı', 422, 'validation_error');
            }

            $stmt = $pdo->prepare('SELECT password_hash FROM users WHERE id = ? LIMIT 1');
            $stmt->execute([$userId]);
            $row = $stmt->fetch();
            if (!$row || !password_verify($cur, $row['password_hash'])) {
                wb_err('Şifreniz yanlıştır. Eğer bilmiyorsanız "Şifremi unuttum" seçeneğini kullanın.', 403, 'wrong_password');
            }

            $pdo->prepare('UPDATE users SET password_hash = ? WHERE id = ?')
                ->execute([password_hash($new, PASSWORD_BCRYPT, ['cost' => 11]), $userId]);

            wb_ok(['changed' => true]);
            break;
        }

        case 'change_password_with_email_otp': {
            $email = strtolower(trim((string)($in['email'] ?? '')));
            $new = (string)($in['newPassword'] ?? '');
            $confirm = (string)($in['confirmPassword'] ?? '');

            if (!$email || !filter_var($email, FILTER_VALIDATE_EMAIL)) {
                wb_err('Geçerli bir e-posta gerekli', 422, 'validation_error');
            }
            if (mb_strlen($new) < 8) {
                wb_err('Yeni şifre en az 8 karakter olmalı', 422, 'validation_error');
            }
            if ($new !== $confirm) {
                wb_err('Yeni şifreler eşleşmiyor', 422, 'validation_error');
            }

            $st = $pdo->prepare('SELECT email FROM customers WHERE user_id = ? LIMIT 1');
            $st->execute([$userId]);
            $customerEmail = strtolower((string)($st->fetchColumn() ?? ''));
            if (!$customerEmail || $customerEmail !== $email) {
                wb_err('Bu hesap için doğrulanmış e-posta bulunamadı', 403, 'email_mismatch');
            }

            if (!wb_user_email_otp_verified('password_reset', $email)) {
                wb_err('Önce e-postaya gelen kodu doğrulayın', 403, 'email_otp_required');
            }

            $pdo->prepare('UPDATE users SET password_hash = ? WHERE id = ?')
                ->execute([password_hash($new, PASSWORD_BCRYPT, ['cost' => 11]), $userId]);

            wb_clear_user_email_otp_verified('password_reset', $email);
            wb_ok(['changed' => true]);
            break;
        }

        default:
            wb_err('Geçersiz action', 400, 'invalid_action');
    }

} catch (Throwable $e) {
    error_log('[user/profile/update.php] ' . $e->getMessage());
    wb_err('İşlem başarısız. Lütfen tekrar deneyin.', 500, 'internal_error');
}
