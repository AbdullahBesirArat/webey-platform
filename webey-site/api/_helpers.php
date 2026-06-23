<?php
declare(strict_types=1);

// Backward-compat include for endpoints that still load _helpers.php.
// Canonical email helpers live in _email_templates.php.
require_once __DIR__ . '/wb_response.php';
require_once __DIR__ . '/_email_templates.php';

if (!function_exists('respond_json')) {
    /** @deprecated wb_ok() veya wb_err() kullan */
    function respond_json(array $data, int $status = 200): void
    {
        $isOk = ($data['ok'] ?? $data['success'] ?? true) === true;
        if ($isOk) {
            wb_ok($data, $status);
            return;
        }
        wb_err($data['error'] ?? 'Hata', $status);
    }
}

if (!function_exists('read_json_body')) {
    /** @deprecated wb_body() kullan */
    function read_json_body(): array
    {
        return wb_body();
    }
}

if (!function_exists('require_method')) {
    /** @deprecated wb_method() kullan */
    function require_method(string $method): void
    {
        wb_method($method);
    }
}

if (!function_exists('require_auth')) {
    /** @deprecated wb_auth_admin() kullan */
    function require_auth(): array
    {
        return wb_auth_admin();
    }
}

/**
 * Müşteri Hoş Geldin Emaili
 * @param array $d [firstName, siteUrl]
 * @return array [subject, html]
 */
function wbEmailWelcomeUser(array $d): array
{
    $cfg     = require __DIR__ . '/_email_config.php';
    $siteUrl = rtrim($d['siteUrl'] ?? $cfg['site_url'], '/');
    $name    = htmlspecialchars($d['firstName'] ?? 'Değerli Üye', ENT_QUOTES);

    $content  = _wbIcon('🎉', '#19a0b6');
    $content .= "<h2 style='margin:0 0 16px;font-size:22px;color:#111827;text-align:center;'>Hoş Geldiniz!</h2>";
    $content .= "<p style='color:#374151;font-size:14.5px;line-height:1.7;'>Merhaba <strong style='color:#111827;'>{$name}</strong>,</p>";
    $content .= "<p style='color:#374151;font-size:14.5px;line-height:1.7;'>Kaydınız başarıyla tamamlandı. Artık Webey üzerinden kolayca randevu alabilirsiniz.</p>";

    $content .= "<div style='background:#f0fdfa;border-radius:12px;padding:18px 20px;margin:20px 0;border-left:4px solid #19a0b6;'>";
    $content .= "<p style='color:#134e4a;font-size:14px;margin:0 0 8px;font-weight:700;'>✨ Neler yapabilirsiniz?</p>";
    $content .= "<ul style='color:#374151;font-size:13.5px;line-height:1.9;margin:0;padding-left:18px;'>";
    $content .= "<li>Çevrenizdeki kuaför ve güzellik salonlarını keşfedin</li>";
    $content .= "<li>Dilediğiniz saate kolayca randevu alın</li>";
    $content .= "<li>Randevularınızı takip edin ve yönetin</li>";
    $content .= "</ul></div>";

    $content .= _wbBtn('Randevu Almaya Başla', $siteUrl, '#19a0b6');
    $content .= "<p style='color:#9ca3af;font-size:12px;text-align:center;margin-top:20px;'>İyi günler dileriz 👋</p>";

    $subject = "Webey'e Hoş Geldiniz! 🎉";
    return [$subject, _wbEmailWrap($subject, $content, 'Kaydınız tamamlandı, randevu almaya başlayabilirsiniz.')];
}
