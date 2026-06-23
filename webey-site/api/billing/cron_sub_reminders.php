<?php
declare(strict_types=1);

// api/billing/cron_sub_reminders.php
// Subscription end reminder cron.
// Runs every 30 minutes and sends:
// - 3 days before end
// - 2 days before end
// - 1 day before end
// - after subscription has ended

if (PHP_SAPI !== 'cli' && (string)($_SERVER['REMOTE_ADDR'] ?? '') !== '127.0.0.1') {
    http_response_code(403);
    exit('Forbidden');
}

require __DIR__ . '/../../db.php';
require __DIR__ . '/../_mailer.php';
require __DIR__ . '/../_email_templates.php';
require __DIR__ . '/../_sms.php';
require __DIR__ . '/_plans.php';
require __DIR__ . '/_subscription_mail.php';

$now = new DateTimeImmutable('now', new DateTimeZone('Europe/Istanbul'));
$counts = ['notification' => 0, 'email' => 0, 'sms' => 0];
$errors = 0;

echo '[' . $now->format('Y-m-d H:i:s') . "] Subscription reminder cron started\n";

function shouldSend(PDO $pdo, int $subId, string $remindType, string $channel): bool
{
    try {
        $pdo->prepare("
            INSERT INTO subscription_reminders (subscription_id, remind_type, channel, status, sent_at)
            VALUES (?, ?, ?, 'sent', NOW())
        ")->execute([$subId, $remindType, $channel]);
        return true;
    } catch (Throwable) {
        return false;
    }
}

function insertSubNotification(
    PDO $pdo,
    int $bizId,
    string $type,
    string $planLabel,
    string $endDate,
    string $remindType
): void {
    $title = match ($remindType) {
        'expiry_3d' => 'Aktif planinizin bitimine 3 gun kaldi',
        'expiry_2d' => 'Aktif planinizin bitimine 2 gun kaldi',
        'expiry_1d' => 'Aktif planinizin bitimine 1 gun kaldi',
        default => 'Aktif planiniz bitmistir',
    };

    $desc = match ($remindType) {
        'expiry_3d' => "{$planLabel} planinizin bitimine 3 gun kalmistir. Yenilemek icin panelinizdeki profile giderek yeni bir plan seciniz.",
        'expiry_2d' => "{$planLabel} planinizin bitimine 2 gun kalmistir. Yenilemek icin panelinizdeki profile giderek yeni bir plan seciniz.",
        'expiry_1d' => "{$planLabel} planinizin bitimine 1 gun kalmistir. Yenilemek icin panelinizdeki profile giderek yeni bir plan seciniz.",
        default => "{$planLabel} planiniz {$endDate} tarihinde bitmistir. Yenilemek icin panelinizdeki profile giderek yeni bir plan seciniz.",
    };

    $pdo->prepare("
        INSERT INTO notifications
            (business_id, type, customer_name, service_name, result, is_read, is_deleted, created_at)
        VALUES (?, ?, ?, ?, 'info', 0, 0, NOW())
    ")->execute([$bizId, $type, $title, $desc]);
}

function buildReminderSubject(string $bizName, string $remindType): string
{
    return match ($remindType) {
        'expiry_3d' => "{$bizName} - Aktif planinizin bitimine 3 gun kalmistir",
        'expiry_2d' => "{$bizName} - Aktif planinizin bitimine 2 gun kalmistir",
        'expiry_1d' => "{$bizName} - Aktif planinizin bitimine 1 gun kalmistir",
        default => "{$bizName} - Aktif planiniz bitmistir",
    };
}

function buildSubEmail(
    string $bizName,
    string $ownerName,
    string $planLabel,
    string $endDate,
    string $remindType,
    string $planUrl
): string {
    [$headline, $message, $accent] = match ($remindType) {
        'expiry_3d' => [
            'Aktif planinizin bitimine 3 gun kalmistir',
            "Aktif planinizin bitimine <strong>3 gun kalmistir</strong>. Yenilemek icin lutfen panelinizdeki profile giderek yeni bir plan seciniz.",
            '#0ea5b3',
        ],
        'expiry_2d' => [
            'Aktif planinizin bitimine 2 gun kalmistir',
            "Aktif planinizin bitimine <strong>2 gun kalmistir</strong>. Yenilemek icin lutfen panelinizdeki profile giderek yeni bir plan seciniz.",
            '#f59e0b',
        ],
        'expiry_1d' => [
            'Aktif planinizin bitimine 1 gun kalmistir',
            "Aktif planinizin bitimine <strong>1 gun kalmistir</strong>. Yenilemek icin lutfen panelinizdeki profile giderek yeni bir plan seciniz.",
            '#f97316',
        ],
        default => [
            'Aktif planiniz bitmistir',
            "Aktif planiniz <strong>bitmistir</strong>. Yenilemek icin lutfen panelinizdeki profile giderek yeni bir plan seciniz.",
            '#ef4444',
        ],
    };

    $bodyHtml = "
      <p style=\"margin:0 0 14px;color:#374151;font-size:15px;\">Merhaba <strong>{$ownerName}</strong>,</p>
      <p style=\"margin:0 0 18px;color:#4b5563;font-size:14px;line-height:1.7;\">{$message}</p>
      <div style=\"background:#f8f9ff;border-radius:12px;padding:16px 18px;border-left:4px solid {$accent};margin-bottom:22px;\">
        <p style=\"margin:0;color:#111827;font-size:14px;line-height:1.8;\">
          Isletme: <strong>{$bizName}</strong><br>
          Plan: <strong>{$planLabel}</strong><br>
          Bitis: <strong>{$endDate}</strong>
        </p>
      </div>
    ";

    return wb_subscription_mail_shell($headline, $bodyHtml, 'Profile Git', $planUrl, $accent);
}

function smsSubText(string $bizName, string $remindType): string
{
    return match ($remindType) {
        'expiry_3d' => "Webey: {$bizName} aktif planinizin bitimine 3 gun kalmistir. Profilinizden yeni plan seciniz.",
        'expiry_2d' => "Webey: {$bizName} aktif planinizin bitimine 2 gun kalmistir. Profilinizden yeni plan seciniz.",
        'expiry_1d' => "Webey: {$bizName} aktif planinizin bitimine 1 gun kalmistir. Profilinizden yeni plan seciniz.",
        default => "Webey: {$bizName} aktif planiniz bitmistir. Profilinizden yeni plan seciniz.",
    };
}

$planLabels = array_map(
    static fn(array $plan): string => (string)$plan['label'],
    WB_PLANS
);

$cfg = require __DIR__ . '/../_email_config.php';
$planUrl = rtrim((string)($cfg['site_url'] ?? 'https://webey.com.tr'), '/') . '/admin-profile.html#billing';

$windows = [
    'expiry_3d' => "s.end_date BETWEEN DATE_ADD(NOW(), INTERVAL 71 HOUR) AND DATE_ADD(NOW(), INTERVAL 73 HOUR)",
    'expiry_2d' => "s.end_date BETWEEN DATE_ADD(NOW(), INTERVAL 47 HOUR) AND DATE_ADD(NOW(), INTERVAL 49 HOUR)",
    'expiry_1d' => "s.end_date BETWEEN DATE_ADD(NOW(), INTERVAL 23 HOUR) AND DATE_ADD(NOW(), INTERVAL 25 HOUR)",
    'expired' => "s.end_date BETWEEN DATE_SUB(NOW(), INTERVAL 60 MINUTE) AND NOW()",
];

foreach ($windows as $remindType => $whereClause) {
    $stmt = $pdo->query("
        SELECT
            s.id AS sub_id,
            s.plan,
            s.end_date,
            u.id AS user_id,
            u.email AS user_email,
            u.name AS user_name,
            b.id AS biz_id,
            b.name AS biz_name,
            b.phone AS biz_phone
        FROM subscriptions s
        JOIN users u ON u.id = s.user_id
        LEFT JOIN businesses b ON b.owner_id = u.id
        WHERE s.status IN ('active','trialing')
          AND {$whereClause}
        LIMIT 200
    ");
    $subs = $stmt->fetchAll(PDO::FETCH_ASSOC);

    echo "  [{$remindType}]: " . count($subs) . " subscriptions\n";

    foreach ($subs as $sub) {
        $subId = (int)$sub['sub_id'];
        $bizId = (int)($sub['biz_id'] ?? 0);
        $planLabel = $planLabels[(string)$sub['plan']] ?? (string)$sub['plan'];
        $endDate = (new DateTimeImmutable((string)$sub['end_date']))->format('d.m.Y');
        $ownerName = (string)($sub['user_name'] ?: ($sub['biz_name'] ?: 'Isletme Sahibi'));
        $bizName = (string)($sub['biz_name'] ?: 'Isletmeniz');

        $notifType = match ($remindType) {
            'expiry_3d' => 'subscription_expiry_3d',
            'expiry_2d' => 'subscription_expiry_2d',
            'expiry_1d' => 'subscription_expiry_1d',
            default => 'subscription_expired',
        };

        if ($bizId && shouldSend($pdo, $subId, $remindType, 'notification')) {
            try {
                insertSubNotification($pdo, $bizId, $notifType, $planLabel, $endDate, $remindType);
                $counts['notification']++;
                echo "    [panel] sub#{$subId} biz#{$bizId}\n";
            } catch (Throwable $e) {
                $errors++;
                error_log("[cron_sub][notif] sub#{$subId} " . $e->getMessage());
            }
        }

        if (!empty($sub['user_email']) && shouldSend($pdo, $subId, $remindType, 'email')) {
            try {
                $subject = buildReminderSubject($bizName, $remindType);
                $html = buildSubEmail($bizName, $ownerName, $planLabel, $endDate, $remindType, $planUrl);
                wb_queue_subscription_email($pdo, (string)$sub['user_email'], $ownerName, $subject, $html);
                $counts['email']++;
                echo "    [email] sub#{$subId} -> {$sub['user_email']}\n";
            } catch (Throwable $e) {
                $errors++;
                error_log("[cron_sub][email] sub#{$subId} " . $e->getMessage());
            }
        }

        $phone = trim((string)($sub['biz_phone'] ?? ''));
        if ($phone && shouldSend($pdo, $subId, $remindType, 'sms')) {
            try {
                $smsText = smsSubText($bizName, $remindType);
                queueSms($pdo, $phone, $smsText, 'sub_reminder', null, null);
                $counts['sms']++;
                echo "    [sms] sub#{$subId} -> {$phone}\n";
            } catch (Throwable $e) {
                $errors++;
                error_log("[cron_sub][sms] sub#{$subId} " . $e->getMessage());
            }
        }
    }
}

try {
    $expired = $pdo->exec("
        UPDATE subscriptions
        SET status = 'expired'
        WHERE status IN ('active','trialing')
          AND end_date < DATE_SUB(NOW(), INTERVAL 60 MINUTE)
    ");
    if ($expired > 0) {
        echo "  [expire] {$expired} subscriptions marked as expired\n";
    }
} catch (Throwable $e) {
    error_log('[cron_sub][expire] ' . $e->getMessage());
}

echo '[' . date('H:i:s') . "] Done - panel:{$counts['notification']} email:{$counts['email']} sms:{$counts['sms']} errors:{$errors}\n\n";
