<?php
declare(strict_types=1);
/**
 * api/billing/cron_expire.php
 *
 * Gunluk cron job:
 * - Suresi dolan abonelikleri expire eder
 * - Sirasi gelen queued planlari aktiflestirir
 * - Gerekirse isletmeleri suspended/active durumuna ceker
 */

require_once __DIR__ . '/../wb_response.php';

if (PHP_SAPI !== 'cli') {
    $secret = getenv('CRON_SECRET') ?: '';

    if ($secret === '') {
        error_log('[cron_expire] CRON_SECRET ortam degiskeni tanimli degil, web erisimi reddedildi.');
        http_response_code(403);
        exit('Forbidden: CRON_SECRET is not configured.');
    }

    if (!hash_equals($secret, (string)($_GET['secret'] ?? ''))) {
        http_response_code(403);
        exit('Forbidden');
    }

    header('Content-Type: application/json; charset=utf-8');
}

require_once __DIR__ . '/../db.php';
require_once __DIR__ . '/_plans.php';
require_once __DIR__ . '/_subscription_mail.php';

$now = date('Y-m-d H:i:s');
$log = [];
$log[] = "[{$now}] Cron basladi";
$siteCfg = require __DIR__ . '/../_email_config.php';
$profileUrl = rtrim((string)($siteCfg['site_url'] ?? 'https://webey.com.tr'), '/') . '/admin-profile.html#billing';
$planLabels = array_map(
    static fn(array $plan): string => (string)$plan['label'],
    WB_PLANS
);

try {
    $stmt = $pdo->prepare("
        UPDATE subscriptions
        SET status = 'expired', updated_at = NOW()
        WHERE status = 'active'
          AND end_date < NOW()
    ");
    $stmt->execute();
    $expiredCount = $stmt->rowCount();
    $log[] = "Expire edilen abonelik: {$expiredCount}";
} catch (Throwable $e) {
    $log[] = "HATA (expire): " . $e->getMessage();
    $expiredCount = 0;
}

try {
    $qStmt = $pdo->prepare("
        SELECT s.id, s.user_id
        FROM subscriptions s
        WHERE s.status = 'queued'
          AND s.start_date <= NOW()
          AND NOT EXISTS (
              SELECT 1 FROM subscriptions s2
              WHERE s2.user_id = s.user_id
                AND s2.status = 'active'
                AND s2.end_date > NOW()
          )
    ");
    $qStmt->execute();
    $toActivate = $qStmt->fetchAll(PDO::FETCH_ASSOC);
    $activatedQueued = 0;

    $mailStmt = $pdo->prepare("
        SELECT
            u.email AS user_email,
            u.name AS user_name,
            b.name AS biz_name,
            s.plan,
            s.start_date,
            s.end_date
        FROM subscriptions s
        JOIN users u ON u.id = s.user_id
        LEFT JOIN businesses b ON b.owner_id = s.user_id
        WHERE s.id = ?
        LIMIT 1
    ");

    foreach ($toActivate as $qa) {
        $queuedId = (int)$qa['id'];
        $queuedUserId = (int)$qa['user_id'];

        $pdo->prepare("
            UPDATE subscriptions
            SET status = 'active', updated_at = NOW()
            WHERE id = ?
        ")->execute([$queuedId]);

        $pdo->prepare("
            UPDATE businesses
            SET status = 'active', updated_at = NOW()
            WHERE owner_id = ? AND status = 'suspended' AND onboarding_completed = 1
        ")->execute([$queuedUserId]);

        $mailStmt->execute([$queuedId]);
        $mailRow = $mailStmt->fetch(PDO::FETCH_ASSOC) ?: null;

        if ($mailRow && !empty($mailRow['user_email']) && !empty($mailRow['start_date']) && !empty($mailRow['end_date'])) {
            wb_queue_subscription_activation_email(
                $pdo,
                (string)$mailRow['user_email'],
                (string)($mailRow['user_name'] ?: 'Isletme Sahibi'),
                (string)($mailRow['biz_name'] ?: 'Isletmeniz'),
                $planLabels[(string)$mailRow['plan']] ?? (string)$mailRow['plan'],
                new DateTimeImmutable((string)$mailRow['start_date']),
                new DateTimeImmutable((string)$mailRow['end_date']),
                $profileUrl
            );
        }

        $activatedQueued++;
    }

    $log[] = "Kuyruktan aktiflestirilen abonelik: {$activatedQueued}";
} catch (Throwable $e) {
    $log[] = "HATA (activate_queued): " . $e->getMessage();
    $activatedQueued = 0;
}

try {
    $stmt = $pdo->prepare("
        UPDATE subscriptions
        SET status = 'cancelled', cancelled_at = NOW(), updated_at = NOW()
        WHERE status = 'active'
          AND cancel_at_period_end = 1
          AND end_date < NOW()
    ");
    $stmt->execute();
    $cancelledCount = $stmt->rowCount();
    $log[] = "Donem sonu iptal: {$cancelledCount}";
} catch (Throwable $e) {
    $log[] = "HATA (cancel): " . $e->getMessage();
    $cancelledCount = 0;
}

try {
    $stmt = $pdo->prepare("
        UPDATE businesses b
        JOIN users u ON u.id = b.owner_id
        SET b.status = 'suspended', b.updated_at = NOW()
        WHERE b.status = 'active'
          AND b.onboarding_completed = 1
          AND NOT EXISTS (
              SELECT 1 FROM subscriptions s
              WHERE s.user_id = b.owner_id
                AND s.status = 'active'
                AND s.end_date > NOW()
          )
          AND u.created_at < DATE_SUB(NOW(), INTERVAL 30 DAY)
    ");
    $stmt->execute();
    $suspendedCount = $stmt->rowCount();
    $log[] = "Suspend edilen dukkan: {$suspendedCount}";
} catch (Throwable $e) {
    $log[] = "HATA (suspend): " . $e->getMessage();
    $suspendedCount = 0;
}

try {
    $stmt = $pdo->prepare("
        UPDATE businesses b
        SET b.status = 'active', b.updated_at = NOW()
        WHERE b.status = 'suspended'
          AND b.onboarding_completed = 1
          AND EXISTS (
              SELECT 1 FROM subscriptions s
              WHERE s.user_id = b.owner_id
                AND s.status = 'active'
                AND s.end_date > NOW()
          )
    ");
    $stmt->execute();
    $reactivatedCount = $stmt->rowCount();
    $log[] = "Yeniden aktif edilen dukkan: {$reactivatedCount}";
} catch (Throwable $e) {
    $log[] = "HATA (reactivate): " . $e->getMessage();
    $reactivatedCount = 0;
}

$summary = [
    'ran_at' => $now,
    'expired' => $expiredCount,
    'activated_queued' => $activatedQueued,
    'cancelled' => $cancelledCount,
    'suspended' => $suspendedCount,
    'reactivated' => $reactivatedCount,
    'log' => $log,
];

$log[] = 'Tamamlandi: ' . json_encode(array_slice($summary, 0, -1));

if (PHP_SAPI === 'cli') {
    foreach ($log as $line) {
        echo $line . PHP_EOL;
    }
} else {
    wb_ok($summary);
}
