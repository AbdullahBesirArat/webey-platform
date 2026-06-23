<?php
declare(strict_types=1);

if (PHP_SAPI !== 'cli') {
    fwrite(STDERR, "This script is CLI only.\n");
    exit(1);
}

if ((getenv('DB_NAME') === false || getenv('DB_NAME') === '')
    && str_starts_with(str_replace('\\', '/', __DIR__), '/var/www/webey/tools')) {
    putenv('DB_NAME=webey_prod');
}

require_once __DIR__ . '/../api/mobile/_bootstrap.php';
require_once __DIR__ . '/../api/_appointment_push.php';

$dryRun = in_array('--dry-run', $argv, true);
$force = in_array('--force', $argv, true);
$tz = new DateTimeZone('Europe/Istanbul');
$now = new DateTimeImmutable('now', $tz);
$summaryDate = $now->format('Y-m-d');

if (!wb_daily_summary_table_ready($pdo)) {
    fwrite(STDERR, "business_daily_summary_log table is missing.\n");
    exit(2);
}

function wb_daily_summary_table_ready(PDO $pdo): bool
{
    $stmt = $pdo->prepare(
        "SELECT COUNT(*)
           FROM INFORMATION_SCHEMA.COLUMNS
          WHERE TABLE_SCHEMA = DATABASE()
            AND TABLE_NAME = 'business_daily_summary_log'
            AND COLUMN_NAME = 'summary_date'"
    );
    $stmt->execute();
    return (int)$stmt->fetchColumn() > 0;
}

$businessStmt = $pdo->query("
    SELECT b.id, b.name, b.owner_id
      FROM businesses b
     WHERE b.status = 'active'
       AND b.onboarding_completed = 1
     ORDER BY b.id ASC
");
$businesses = $businessStmt->fetchAll(PDO::FETCH_ASSOC);

$sent = 0;
$skipped = 0;
$attempted = 0;

foreach ($businesses as $business) {
    $businessId = (int)$business['id'];
    $prefs = wb_push_preferences($pdo, 'business', null, $businessId);
    if (!wb_push_enabled($prefs, 'daily_summary')) {
        $skipped++;
        continue;
    }

    $dedupe = $pdo->prepare(
        'SELECT id FROM business_daily_summary_log WHERE business_id = ? AND summary_date = ? LIMIT 1'
    );
    $dedupe->execute([$businessId, $summaryDate]);
    if (!$force && $dedupe->fetch()) {
        $skipped++;
        continue;
    }

    $stats = $pdo->prepare("
        SELECT
            COUNT(*) AS appointment_count,
            SUM(CASE WHEN status = 'pending' THEN 1 ELSE 0 END) AS pending_count,
            SUM(CASE WHEN deposit_required = 1 AND COALESCE(deposit_status, 'pending') NOT IN ('paid','confirmed','waived') THEN 1 ELSE 0 END) AS deposit_pending_count
          FROM appointments
         WHERE business_id = ?
           AND DATE(start_at) = ?
           AND status NOT IN ('cancelled','rejected','declined','no_show')
    ");
    $stats->execute([$businessId, $summaryDate]);
    $row = $stats->fetch(PDO::FETCH_ASSOC) ?: [];
    $appointmentCount = (int)($row['appointment_count'] ?? 0);
    $pendingCount = (int)($row['pending_count'] ?? 0);
    $depositPendingCount = (int)($row['deposit_pending_count'] ?? 0);

    $title = 'Günlük Webey özeti';
    $body = 'Bugün ' . $appointmentCount . ' randevu';
    if ($pendingCount > 0) {
        $body .= ', ' . $pendingCount . ' onay bekleyen';
    }
    if ($depositPendingCount > 0) {
        $body .= ', ' . $depositPendingCount . ' kapora bekleyen';
    }
    $body .= ' var.';

    $channelId = wb_push_channel_id('system', $prefs);
    $tokenStmt = $pdo->prepare(
        'SELECT DISTINCT token
           FROM mobile_device_tokens
          WHERE is_active = 1
            AND (business_id = ? OR user_id = ?)'
    );
    $tokenStmt->execute([$businessId, (int)($business['owner_id'] ?? 0)]);
    $tokens = array_filter(array_map('trim', $tokenStmt->fetchAll(PDO::FETCH_COLUMN) ?: []));

    if ($dryRun) {
        echo '[dry-run] business_id=' . $businessId . ' tokens=' . count($tokens) . ' body="' . $body . '"' . PHP_EOL;
        $attempted++;
        continue;
    }

    $pdo->beginTransaction();
    try {
        $insert = $pdo->prepare(
            'INSERT IGNORE INTO business_daily_summary_log
                (business_id, summary_date, sent_at, appointment_count)
             VALUES (?, ?, NOW(), ?)'
        );
        $insert->execute([$businessId, $summaryDate, $appointmentCount]);
        if (!$force && $insert->rowCount() === 0) {
            $pdo->commit();
            $skipped++;
            continue;
        }
        $pdo->commit();
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        fwrite(STDERR, '[dedupe] business_id=' . $businessId . ' ' . $e->getMessage() . PHP_EOL);
        continue;
    }

    foreach ($tokens as $token) {
        $attempted++;
        $result = wb_fcm_send_to_token(
            $token,
            $title,
            $body,
            [
                'type' => 'daily_summary',
                'business_id' => (string)$businessId,
                'summary_date' => $summaryDate,
                'route' => '/business/dashboard',
                'channel_id' => $channelId,
            ],
            ['android_channel_id' => $channelId]
        );
        if (!empty($result['ok'])) {
            $sent++;
        } elseif (!empty($result['invalid_token'])) {
            wb_appt_deactivate_invalid_token($pdo, $token, '[daily_summary]');
        }
    }
}

echo 'daily_summary businesses=' . count($businesses)
    . ' attempted=' . $attempted
    . ' sent=' . $sent
    . ' skipped=' . $skipped
    . ' dry_run=' . ($dryRun ? '1' : '0')
    . PHP_EOL;
