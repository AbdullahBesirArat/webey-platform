<?php
declare(strict_types=1);

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_mailer.php';
require_once __DIR__ . '/../_email_templates.php';
require_once __DIR__ . '/../_email_templates_auth.php';

wb_method('POST');
wb_csrf_verify(true);

$sess = wb_auth();
$userId = (int)$sess['user_id'];
$data = wb_body();
$action = (string)($data['action'] ?? '');

try {
    switch ($action) {
        case 'update_email':
            $email = trim(strtolower((string)($data['email'] ?? '')));
            if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
                wb_err('Geçersiz e-posta adresi', 422, 'invalid_email');
            }

            $chk = $pdo->prepare('SELECT id FROM users WHERE email = ? AND id != ?');
            $chk->execute([$email, $userId]);
            if ($chk->fetch()) {
                wb_err('Bu e-posta zaten kullanımda', 409, 'email_taken');
            }

            $cur = $pdo->prepare('SELECT email, email_verify_sent_at FROM users WHERE id = ? LIMIT 1');
            $cur->execute([$userId]);
            $curRow = $cur->fetch();

            if ($curRow && strtolower((string)$curRow['email']) === $email) {
                wb_err('Bu zaten mevcut e-posta adresiniz', 400, 'same_email');
            }

            if (!empty($curRow['email_verify_sent_at'])) {
                $sentAt = strtotime((string)$curRow['email_verify_sent_at']);
                $diff = $sentAt ? (time() - $sentAt) : 0;
                if ($diff > 0 && $diff < 300) {
                    wb_err('Lütfen ' . (300 - $diff) . ' saniye bekleyip tekrar deneyin', 429, 'rate_limited');
                }
            }

            $token = bin2hex(random_bytes(32));
            $pdo->prepare(
                'UPDATE users
                 SET email_verify_token = ?, email_verify_sent_at = NOW()
                 WHERE id = ?'
            )->execute([$token, $userId]);

            $cfg = require __DIR__ . '/../_email_config.php';
            $verifyUrl = rtrim((string)$cfg['site_url'], '/') . '/email-dogrulandi.html?token=' . $token . '&new_email=' . urlencode($email);
            [$subject, $html] = wbEmailVerify([
                'name' => $email,
                'verifyUrl' => $verifyUrl,
            ]);

            $sent = wbMail($email, $email, $subject, $html);
            if (!$sent) {
                $pdo->prepare(
                    'UPDATE users
                     SET email_verify_token = NULL, email_verify_sent_at = NULL
                     WHERE id = ?'
                )->execute([$userId]);

                $mailErr = function_exists('wbMailGetLastError')
                    ? wbMailGetLastError()
                    : ['code' => 'unknown', 'provider' => '', 'message' => ''];

                error_log('[profile/update] mail_failed user:' . $userId . ' email:' . $email . ' reason:' . ($mailErr['code'] ?? 'unknown'));

                wb_err('Doğrulama e-postası gönderilemedi. Lütfen tekrar deneyin.', 500, 'mail_failed', [
                    'reason' => (string)($mailErr['code'] ?? 'unknown'),
                    'provider' => (string)($mailErr['provider'] ?? ''),
                ]);
            }

            $_SESSION['pending_email'] = $email;
            wb_ok([
                'pending' => true,
                'email' => $email,
                'message' => "Doğrulama linki {$email} adresine gönderildi. Linke tıkladıktan sonra e-posta adresiniz güncellenecek.",
            ]);
            break;

        case 'update_phone':
            $phone = preg_replace('/\D+/', '', (string)($data['phone'] ?? ''));
            if ($phone && !preg_match('/^5\d{9}$/', $phone)) {
                wb_err('Geçersiz numara (5xxxxxxxxx formatında olmalı)', 422, 'invalid_phone');
            }

            $pdo->prepare('UPDATE businesses SET phone = ? WHERE owner_id = ?')
                ->execute([$phone ?: null, $userId]);
            wb_ok(['phone' => $phone]);
            break;

        case 'change_password':
            $curPw = (string)($data['currentPassword'] ?? '');
            $newPw = (string)($data['newPassword'] ?? '');
            if (mb_strlen($newPw) < 8) {
                wb_err('Yeni şifre en az 8 karakter olmalı', 422, 'password_too_short');
            }

            $stmt = $pdo->prepare('SELECT password_hash FROM users WHERE id = ?');
            $stmt->execute([$userId]);
            $row = $stmt->fetch();
            if (!$row || !password_verify($curPw, (string)$row['password_hash'])) {
                wb_err('Mevcut şifre hatalı', 403, 'wrong_password');
            }

            $pdo->prepare('UPDATE users SET password_hash = ? WHERE id = ?')
                ->execute([password_hash($newPw, PASSWORD_BCRYPT, ['cost' => 11]), $userId]);
            wb_ok(['changed' => true]);
            break;

        default:
            wb_err('Geçersiz action', 400, 'invalid_action');
    }
} catch (Throwable $e) {
    error_log('[profile/update] ' . $e->getMessage());
    wb_err('Sunucu hatası', 500, 'internal_error');
}
