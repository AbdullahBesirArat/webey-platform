<?php
// api/mobile/_email_otp.php
// Mobil email OTP ortak helper'ı (Customer + Business paylaşır).
// email_otp_tokens tablosunu ve api/_mailer.php (Brevo) altyapısını yeniden kullanır.
// Güvenlik: OTP plaintext SAKLANMAZ (bcrypt hash). Sahte 123456 yalnızca
// _email_config debug modunda üretilir; production'da gerçek random kod gider.
declare(strict_types=1);

require_once __DIR__ . '/../_mailer.php';

if (!function_exists('mobile_email_otp_purposes')) {

    function mobile_email_otp_purposes(): array
    {
        return ['register', 'login', 'password_reset', 'email_verify'];
    }

    function mobile_email_otp_norm(string $email): string
    {
        return strtolower(trim($email));
    }

    function mobile_email_otp_purpose(mixed $raw, string $default = 'register'): string
    {
        $p = strtolower(trim((string)($raw ?? '')));
        return in_array($p, mobile_email_otp_purposes(), true) ? $p : $default;
    }

    function mobile_email_otp_ip(): ?string
    {
        $fwd = $_SERVER['HTTP_X_FORWARDED_FOR'] ?? $_SERVER['REMOTE_ADDR'] ?? '';
        $ip = trim(explode(',', (string)$fwd)[0]);
        return filter_var($ip, FILTER_VALIDATE_IP) ? $ip : null;
    }

    /**
     * 6 haneli OTP üretir, bcrypt hash'leyip kaydeder ve Brevo ile gönderir.
     * Başarıda wb_ok, başarısızlıkta wb_err ile ÇIKAR (thin endpoint'ler için).
     */
    function mobile_email_otp_generate_send(PDO $pdo, string $email, string $purpose): void
    {
        $email = mobile_email_otp_norm($email);
        if ($email === '' || !filter_var($email, FILTER_VALIDATE_EMAIL)) {
            wb_err('Geçerli bir e-posta adresi girin', 422, 'invalid_email');
        }
        $purpose = mobile_email_otp_purpose($purpose);

        // Resend cooldown: son 60 saniyede gönderim varsa reddet.
        try {
            $cd = $pdo->prepare(
                "SELECT COUNT(*) FROM email_otp_tokens
                 WHERE email = ? AND purpose = ?
                   AND created_at > DATE_SUB(NOW(), INTERVAL 60 SECOND)"
            );
            $cd->execute([$email, $purpose]);
            if ((int)$cd->fetchColumn() >= 1) {
                wb_err('Çok sık istek. Lütfen 60 saniye bekleyip tekrar deneyin.', 429, 'cooldown', ['retry_after' => 60]);
            }
        } catch (Throwable $e) {
            error_log('[mobile_email_otp] cooldown: ' . $e->getMessage());
        }

        // Eski aktif OTP'leri iptal et (aynı email+purpose).
        try {
            $pdo->prepare('DELETE FROM email_otp_tokens WHERE email = ? AND purpose = ?')
                ->execute([$email, $purpose]);
        } catch (Throwable $e) {
            error_log('[mobile_email_otp] cleanup: ' . $e->getMessage());
        }

        $cfg = require __DIR__ . '/../_email_config.php';
        $debug = !empty($cfg['debug']);
        $code = $debug ? '123456' : str_pad((string)random_int(1, 999999), 6, '0', STR_PAD_LEFT);
        if ($code === '000000') {
            $code = '147258';
        }
        $hash = password_hash($code, PASSWORD_BCRYPT);

        try {
            $pdo->prepare(
                "INSERT INTO email_otp_tokens (email, code, purpose, attempts, expires_at, ip, created_at)
                 VALUES (?, ?, ?, 0, DATE_ADD(NOW(), INTERVAL 10 MINUTE), ?, NOW())"
            )->execute([$email, $hash, $purpose, mobile_email_otp_ip()]);
        } catch (Throwable $e) {
            error_log('[mobile_email_otp] insert: ' . $e->getMessage());
            wb_err('Doğrulama kodu oluşturulamadı', 500, 'otp_create_failed');
        }

        [$subject, $html, $text] = mobile_email_otp_template($code, $purpose);

        // Debug modu: mail göndermeden başarı döner (yalnız geliştirme; prod debug=false).
        if ($debug) {
            error_log('[mobile_email_otp DEBUG] ' . $email . ' purpose=' . $purpose);
            wb_ok([
                'sent' => true,
                'debug' => true,
                'message' => 'Doğrulama kodu gönderildi (debug modu).',
                'expires_in' => 600,
                'purpose' => $purpose,
            ]);
        }

        $sent = wbMail($email, $email, $subject, $html, $text);
        if (!$sent) {
            $err = function_exists('wbMailGetLastError') ? wbMailGetLastError() : ['code' => 'unknown'];
            error_log('[mobile_email_otp] wbMail failed ' . $email . ' reason=' . ($err['code'] ?? '?'));
            wb_err('E-posta gönderilemedi. Lütfen tekrar deneyin.', 502, 'mail_failed', [
                'reason' => (string)($err['code'] ?? 'unknown'),
            ]);
        }

        wb_ok([
            'sent' => true,
            'message' => 'Doğrulama kodu e-posta adresinize gönderildi.',
            'expires_in' => 600,
            'purpose' => $purpose,
        ]);
    }

    /**
     * OTP'yi doğrular. Başarıda used_at set eder ve ['ok'=>true] döner (ÇIKMAZ).
     * Başarısızlıkta ['ok'=>false,'http'=>int,'code'=>string,'message'=>string,'remaining'=>?int] döner.
     */
    function mobile_email_otp_check(PDO $pdo, string $email, string $code, string $purpose): array
    {
        $email = mobile_email_otp_norm($email);
        $purpose = mobile_email_otp_purpose($purpose);
        $code = trim($code);

        if ($email === '' || !filter_var($email, FILTER_VALIDATE_EMAIL)) {
            return ['ok' => false, 'http' => 422, 'code' => 'invalid_email', 'message' => 'Geçersiz e-posta adresi'];
        }
        if (!preg_match('/^\d{6}$/', $code)) {
            return ['ok' => false, 'http' => 422, 'code' => 'invalid_code', 'message' => 'Geçersiz kod formatı'];
        }

        try {
            $stmt = $pdo->prepare(
                "SELECT id, code, attempts FROM email_otp_tokens
                 WHERE email = ? AND purpose = ? AND expires_at > NOW() AND used_at IS NULL
                 ORDER BY created_at DESC LIMIT 1"
            );
            $stmt->execute([$email, $purpose]);
            $token = $stmt->fetch();

            if (!$token) {
                return ['ok' => false, 'http' => 410, 'code' => 'token_expired', 'message' => 'Kodun süresi dolmuş veya bulunamadı. Yeni kod isteyin.'];
            }
            if ((int)$token['attempts'] >= 5) {
                return ['ok' => false, 'http' => 429, 'code' => 'too_many_attempts', 'message' => 'Çok fazla yanlış deneme. Yeni kod isteyin.'];
            }
            if (!password_verify($code, (string)$token['code'])) {
                $pdo->prepare('UPDATE email_otp_tokens SET attempts = attempts + 1 WHERE id = ?')
                    ->execute([$token['id']]);
                $remaining = max(0, 4 - (int)$token['attempts']);
                return ['ok' => false, 'http' => 400, 'code' => 'wrong_code', 'message' => "Yanlış kod. {$remaining} deneme hakkınız kaldı.", 'remaining' => $remaining];
            }
            $pdo->prepare('UPDATE email_otp_tokens SET used_at = NOW() WHERE id = ?')
                ->execute([$token['id']]);
            return ['ok' => true];
        } catch (Throwable $e) {
            error_log('[mobile_email_otp_check] ' . $e->getMessage());
            return ['ok' => false, 'http' => 500, 'code' => 'internal_error', 'message' => 'Doğrulama başarısız'];
        }
    }

    /**
     * email+purpose için son $within saniye içinde DOĞRULANMIŞ (used_at) OTP var mı?
     * OTP-gated register / password reset için stateless kapı.
     */
    function mobile_email_otp_recently_verified(PDO $pdo, string $email, string $purpose, int $within = 900): bool
    {
        $email = mobile_email_otp_norm($email);
        $purpose = mobile_email_otp_purpose($purpose);
        try {
            $stmt = $pdo->prepare(
                "SELECT 1 FROM email_otp_tokens
                 WHERE email = ? AND purpose = ? AND used_at IS NOT NULL
                   AND used_at > DATE_SUB(NOW(), INTERVAL ? SECOND)
                 ORDER BY used_at DESC LIMIT 1"
            );
            $stmt->execute([$email, $purpose, $within]);
            return (bool)$stmt->fetchColumn();
        } catch (Throwable $e) {
            error_log('[mobile_email_otp_recently_verified] ' . $e->getMessage());
            return false;
        }
    }

    /** Doğrulanmış OTP'leri tüketir (tekrar kullanılamasın). */
    function mobile_email_otp_consume(PDO $pdo, string $email, string $purpose): void
    {
        $email = mobile_email_otp_norm($email);
        $purpose = mobile_email_otp_purpose($purpose);
        try {
            $pdo->prepare('DELETE FROM email_otp_tokens WHERE email = ? AND purpose = ?')
                ->execute([$email, $purpose]);
        } catch (Throwable $e) {
            error_log('[mobile_email_otp_consume] ' . $e->getMessage());
        }
    }

    function mobile_email_otp_template(string $code, string $purpose): array
    {
        $titles = [
            'register' => 'Webey doğrulama kodunuz',
            'login' => 'Webey giriş kodunuz',
            'password_reset' => 'Webey şifre sıfırlama kodunuz',
            'email_verify' => 'Webey doğrulama kodunuz',
        ];
        $leads = [
            'register' => 'Webey hesabınızı oluşturmak için doğrulama kodunuz:',
            'login' => 'Webey hesabınıza giriş kodunuz:',
            'password_reset' => 'Webey şifrenizi sıfırlamak için kodunuz:',
            'email_verify' => 'Webey hesabınız için doğrulama kodunuz:',
        ];
        $title = $titles[$purpose] ?? $titles['register'];
        $lead = $leads[$purpose] ?? $leads['register'];

        $html = "<!DOCTYPE html><html lang='tr'><head><meta charset='UTF-8'/>"
            . "<meta name='viewport' content='width=device-width,initial-scale=1.0'/></head>"
            . "<body style='margin:0;background:#f6f7f9;'>"
            . "<div style=\"font-family:'Segoe UI',Arial,sans-serif;max-width:480px;margin:0 auto;padding:32px 16px;\">"
            . "<h2 style='color:#19a0b6;text-align:center;margin:0 0 8px;'>{$title}</h2>"
            . "<p style='color:#374151;font-size:15px;text-align:center;margin:0 0 4px;'>{$lead}</p>"
            . "<div style='background:#f0fdfa;border:2px solid #19a0b6;border-radius:16px;padding:24px;text-align:center;margin:24px 0;'>"
            . "<span style='font-size:40px;font-weight:900;letter-spacing:12px;color:#111827;'>{$code}</span></div>"
            . "<p style='color:#6b7280;font-size:13px;text-align:center;margin:0 0 6px;'>Bu kod <strong>10 dakika</strong> içinde geçerlidir.</p>"
            . "<p style='color:#9ca3af;font-size:12px;text-align:center;margin:0 0 18px;'>Bu işlemi siz yapmadıysanız bu e-postayı dikkate almayın.</p>"
            . "<p style='color:#9ca3af;font-size:12px;text-align:center;margin:0;'>Webey · destek@webey.com.tr</p>"
            . "</div></body></html>";

        $text = "{$title}\n\n{$lead}\n\n    {$code}\n\n"
            . "Bu kod 10 dakika içinde geçerlidir.\n"
            . "Bu işlemi siz yapmadıysanız bu e-postayı dikkate almayın.\n\nWebey · destek@webey.com.tr";

        return [$title, $html, $text];
    }
}
