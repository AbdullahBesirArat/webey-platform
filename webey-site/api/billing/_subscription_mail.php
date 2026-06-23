<?php
declare(strict_types=1);

function wb_queue_subscription_email(PDO $pdo, string $toEmail, string $toName, string $subject, string $html): void
{
    if (!filter_var($toEmail, FILTER_VALIDATE_EMAIL)) {
        return;
    }

    $pdo->prepare("
        INSERT INTO email_queue (to_email, to_name, subject, body_html, status, created_at)
        VALUES (?, ?, ?, ?, 'pending', NOW())
    ")->execute([$toEmail, $toName, $subject, $html]);
}

function wb_subscription_mail_shell(string $headline, string $bodyHtml, string $ctaLabel, string $ctaUrl, string $accent = '#0ea5b3'): string
{
    return <<<HTML
<!DOCTYPE html>
<html lang="tr">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <title>Webey - Plan Bilgilendirmesi</title>
</head>
<body style="margin:0;padding:0;background:#f4f6f8;font-family:Inter,Arial,sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background:#f4f6f8;">
    <tr>
      <td align="center" style="padding:32px 16px;">
        <table width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;">
          <tr>
            <td align="center" style="padding-bottom:20px;">
              <span style="font-size:26px;font-weight:900;color:#0ea5b3;letter-spacing:-1px;">webey</span>
            </td>
          </tr>
          <tr>
            <td style="background:#fff;border-radius:20px;overflow:hidden;box-shadow:0 4px 24px rgba(0,0,0,.08);">
              <div style="background:{$accent};padding:26px 28px;text-align:center;">
                <h1 style="margin:0;color:#fff;font-size:22px;font-weight:700;">{$headline}</h1>
              </div>
              <div style="padding:32px 34px;">
                {$bodyHtml}
                <div style="text-align:center;margin-top:24px;">
                  <a href="{$ctaUrl}" style="display:inline-block;padding:14px 32px;background:{$accent};color:#fff;border-radius:10px;text-decoration:none;font-size:15px;font-weight:700;">
                    {$ctaLabel}
                  </a>
                </div>
              </div>
            </td>
          </tr>
          <tr>
            <td style="padding:18px 0;text-align:center;color:#94a3b8;font-size:12px;">
              © 2026 Webey · Tum haklari saklidir.
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>
HTML;
}

function wb_queue_subscription_purchase_email(
    PDO $pdo,
    string $toEmail,
    string $toName,
    string $bizName,
    string $planLabel,
    DateTimeInterface $startDate,
    DateTimeInterface $endDate,
    string $profileUrl,
    bool $isQueued = false
): void {
    $periodText = $startDate->format('d.m.Y') . ' - ' . $endDate->format('d.m.Y');

    if ($isQueued) {
        $subject = "{$bizName} - Yeni planiniz secildi";
        $headline = 'Yeni planiniz secildi';
        $bodyHtml = "
          <p style=\"margin:0 0 14px;color:#374151;font-size:15px;\">Merhaba <strong>{$toName}</strong>,</p>
          <p style=\"margin:0 0 18px;color:#4b5563;font-size:14px;line-height:1.7;\">
            Yeni planiniz basariyla secildi. Mevcut planiniz bittiginde yeni planiniz otomatik olarak aktif edilecektir.
          </p>
          <div style=\"background:#f8f9ff;border-radius:12px;padding:16px 18px;border-left:4px solid #0ea5b3;margin-bottom:22px;\">
            <p style=\"margin:0;color:#111827;font-size:14px;line-height:1.8;\">
              Isletme: <strong>{$bizName}</strong><br>
              Plan: <strong>{$planLabel}</strong><br>
              Sure: <strong>{$periodText}</strong><br>
              Durum: <strong>Siraya alindi</strong>
            </p>
          </div>
          <p style=\"margin:0;color:#4b5563;font-size:14px;line-height:1.7;\">
            Yeni planiniz aktif oldugunda size ayrica basari maili gonderilecektir.
          </p>
        ";
    } else {
        $subject = "{$bizName} - Yeni planiniz aktif edildi";
        $headline = 'Yeni planiniz aktif edildi';
        $bodyHtml = "
          <p style=\"margin:0 0 14px;color:#374151;font-size:15px;\">Merhaba <strong>{$toName}</strong>,</p>
          <p style=\"margin:0 0 18px;color:#4b5563;font-size:14px;line-height:1.7;\">
            Yeni planiniz basariyla aktif edildi.
          </p>
          <div style=\"background:#f8f9ff;border-radius:12px;padding:16px 18px;border-left:4px solid #0ea5b3;margin-bottom:22px;\">
            <p style=\"margin:0;color:#111827;font-size:14px;line-height:1.8;\">
              Isletme: <strong>{$bizName}</strong><br>
              Plan: <strong>{$planLabel}</strong><br>
              Sure: <strong>{$periodText}</strong><br>
              Durum: <strong>Aktif</strong>
            </p>
          </div>
          <p style=\"margin:0;color:#4b5563;font-size:14px;line-height:1.7;\">
            Plan durumunuzu profil sayfanizdan takip edebilirsiniz.
          </p>
        ";
    }

    $html = wb_subscription_mail_shell($headline, $bodyHtml, 'Profile Git', $profileUrl);
    wb_queue_subscription_email($pdo, $toEmail, $toName, $subject, $html);
}

function wb_queue_subscription_activation_email(
    PDO $pdo,
    string $toEmail,
    string $toName,
    string $bizName,
    string $planLabel,
    DateTimeInterface $startDate,
    DateTimeInterface $endDate,
    string $profileUrl
): void {
    $periodText = $startDate->format('d.m.Y') . ' - ' . $endDate->format('d.m.Y');
    $subject = "{$bizName} - Yeni planiniz aktif oldu";
    $headline = 'Yeni planiniz aktif oldu';
    $bodyHtml = "
      <p style=\"margin:0 0 14px;color:#374151;font-size:15px;\">Merhaba <strong>{$toName}</strong>,</p>
      <p style=\"margin:0 0 18px;color:#4b5563;font-size:14px;line-height:1.7;\">
        Sectiginiz yeni plan basariyla aktif oldu. Isletmeniz yayinda kalmaya devam ediyor.
      </p>
      <div style=\"background:#f8f9ff;border-radius:12px;padding:16px 18px;border-left:4px solid #0ea5b3;margin-bottom:22px;\">
        <p style=\"margin:0;color:#111827;font-size:14px;line-height:1.8;\">
          Isletme: <strong>{$bizName}</strong><br>
          Plan: <strong>{$planLabel}</strong><br>
          Sure: <strong>{$periodText}</strong><br>
          Durum: <strong>Aktif</strong>
        </p>
      </div>
      <p style=\"margin:0;color:#4b5563;font-size:14px;line-height:1.7;\">
        Plan detaylarinizi profil sayfanizdan gorebilirsiniz.
      </p>
    ";

    $html = wb_subscription_mail_shell($headline, $bodyHtml, 'Profile Git', $profileUrl);
    wb_queue_subscription_email($pdo, $toEmail, $toName, $subject, $html);
}
