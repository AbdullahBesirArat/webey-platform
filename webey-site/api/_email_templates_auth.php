<?php
// ============================================================
// _email_templates_auth.php
// Email Doğrulama + Şifre Sıfırlama şablonları
// _email_templates.php ile aynı klasörde olmalı
// ============================================================
declare(strict_types=1);

/**
 * Email Doğrulama Emaili
 * @param array $d [name, verifyUrl]
 * @return [subject, html]
 */
function wbEmailVerify(array $d): array
{
    $name = htmlspecialchars($d['name'] ?? 'Kullanıcı', ENT_QUOTES);
    $url  = $d['verifyUrl'] ?? '#';

    $content  = _wbIcon('📧', '#19a0b6');
    $content .= "<h2 style='margin:0 0 16px;font-size:22px;color:#111827;text-align:center;'>Email Adresinizi Doğrulayın</h2>";
    $content .= "<p style='color:#374151;font-size:14.5px;line-height:1.7;'>Merhaba <strong style='color:#111827;'>{$name}</strong>,</p>";
    $content .= "<p style='color:#374151;font-size:14.5px;line-height:1.7;'>Webey hesabınızı tamamlamak için email adresinizi doğrulamanız gerekiyor. Aşağıdaki butona tıklayın:</p>";
    $content .= _wbBtn('E-postamı Doğrula', $url, '#19a0b6');
    $content .= "<p style='color:#9ca3af;font-size:12.5px;text-align:center;margin-top:20px;'>Bu buton <strong>24 saat</strong> geçerlidir.</p>";
    $content .= "<p style='color:#9ca3af;font-size:12px;text-align:center;'>Bu emaili siz talep etmediyseniz görmezden gelebilirsiniz.</p>";
    $content .= "<p style='color:#d1d5db;font-size:11px;text-align:center;word-break:break-all;margin-top:16px;'>Link çalışmıyorsa kopyalayın: <span style='color:#6b7280;'>{$url}</span></p>";

    $subject = 'Webey – Email Adresinizi Doğrulayın';
    return [$subject, _wbEmailWrap($subject, $content, 'Hesabınızı aktifleştirmek için doğrulama yapın.')];
}

/**
 * Şifre Sıfırlama Emaili
 * @param array $d [name, resetUrl]
 * @return [subject, html]
 */
function wbEmailPasswordReset(array $d): array
{
    $name = htmlspecialchars($d['name'] ?? 'Kullanıcı', ENT_QUOTES);
    $url  = $d['resetUrl'] ?? '#';

    $content  = _wbIcon('🔑', '#f59e0b');
    $content .= "<h2 style='margin:0 0 16px;font-size:22px;color:#111827;text-align:center;'>Şifre Sıfırlama</h2>";
    $content .= "<p style='color:#374151;font-size:14.5px;line-height:1.7;'>Merhaba <strong style='color:#111827;'>{$name}</strong>,</p>";
    $content .= "<p style='color:#374151;font-size:14.5px;line-height:1.7;'>Webey hesabınız için şifre sıfırlama talebinde bulundunuz. Şifrenizi sıfırlamak için aşağıdaki butona tıklayın:</p>";
    $content .= _wbBtn('Şifremi Sıfırla', $url, '#f59e0b');
    $content .= "<div style='background:#fef3c7;border-radius:10px;padding:14px 18px;margin:20px 0;'>";
    $content .= "<p style='color:#92400e;font-size:13px;margin:0;'>⏱ Bu link <strong>1 saat</strong> içinde geçerliliğini yitirir.</p>";
    $content .= "</div>";
    $content .= "<p style='color:#9ca3af;font-size:12.5px;text-align:center;'>Bu emaili siz talep etmediyseniz şifreniz değişmeyecektir. Hesabınızı korumak için <a href='#' style='color:#19a0b6;'>bize bildirin</a>.</p>";
    $content .= "<p style='color:#d1d5db;font-size:11px;text-align:center;word-break:break-all;margin-top:16px;'>Link çalışmıyorsa kopyalayın: <span style='color:#6b7280;'>{$url}</span></p>";

    $subject = 'Webey – Şifre Sıfırlama';
    return [$subject, _wbEmailWrap($subject, $content, 'Şifrenizi sıfırlamak için linke tıklayın.')];
}