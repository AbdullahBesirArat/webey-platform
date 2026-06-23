<?php
/**
 * api/cron_send_sms.php
 * ─────────────────────────────────────────────────────────────────────
 * Crontab:  * * * * *  php /var/www/html/api/cron_send_sms.php >> /var/log/webey_sms.log 2>&1
 *
 * sms_queue tablosundaki bekleyen SMS'leri işler.
 * Her SMS max 3 deneme hakkı alır, sonra 'failed' olur.
 * ─────────────────────────────────────────────────────────────────────
 */
declare(strict_types=1);

if (PHP_SAPI !== 'cli' && ($_SERVER['REMOTE_ADDR'] ?? '') !== '127.0.0.1') {
    http_response_code(403);
    exit('CLI only');
}

require_once __DIR__ . '/../db.php';
require_once __DIR__ . '/_sms.php';

const SMS_MAX_ATTEMPTS  = 3;
const SMS_BATCH_SIZE    = 30;   // dakikada max 30 SMS (provider limitine göre ayarla)
const SMS_RETRY_DELAY_S = 300;  // başarısız SMS'i 5 dk sonra tekrar dene

$now    = date('Y-m-d H:i:s');
$sent   = 0;
$failed = 0;

echo "[{$now}] cron_send_sms başladı\n";

try {
    $stmt = $pdo->prepare("
        SELECT id, phone, message, attempts
        FROM   sms_queue
        WHERE  status != 'sent'
          AND  attempts < :max_attempts
          AND  (scheduled_at IS NULL OR scheduled_at <= NOW())
          AND  (
                  status = 'pending'
               OR (status = 'failed' AND created_at <= DATE_SUB(NOW(), INTERVAL :retry_delay SECOND))
               )
        ORDER BY created_at ASC
        LIMIT :batch
    ");
    $stmt->bindValue(':max_attempts', SMS_MAX_ATTEMPTS, PDO::PARAM_INT);
    $stmt->bindValue(':retry_delay',  SMS_RETRY_DELAY_S, PDO::PARAM_INT);
    $stmt->bindValue(':batch',        SMS_BATCH_SIZE, PDO::PARAM_INT);
    $stmt->execute();
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
} catch (Throwable $e) {
    echo "[HATA] sms_queue okunamadı: " . $e->getMessage() . "\n";
    exit(1);
}

if (empty($rows)) {
    echo "[{$now}] Gönderilecek SMS yok.\n";
    exit(0);
}

echo "  → " . count($rows) . " SMS işlenecek\n";

foreach ($rows as $row) {
    $id      = (int)$row['id'];
    $attempt = (int)$row['attempts'] + 1;
    $lastErr = null;

    $ok = false;
    try {
        $ok = wbSms($row['phone'], $row['message']);
    } catch (Throwable $e) {
        $lastErr = $e->getMessage();
        error_log("[cron_send_sms] #{$id} exception: " . $lastErr);
    }

    if ($ok) {
        $pdo->prepare("
            UPDATE sms_queue
            SET status='sent', attempts=?, sent_at=NOW(), last_error=NULL
            WHERE id=?
        ")->execute([$attempt, $id]);

        $sent++;
        echo "  [OK]    #{$id} → {$row['phone']}\n";
    } else {
        $newStatus = ($attempt >= SMS_MAX_ATTEMPTS) ? 'failed' : 'pending';
        $errMsg    = $lastErr ?? 'wbSms false döndü';

        $pdo->prepare("
            UPDATE sms_queue
            SET status=?, attempts=?, last_error=?
            WHERE id=?
        ")->execute([$newStatus, $attempt, $errMsg, $id]);

        $failed++;
        $tag = ($newStatus === 'failed') ? '[FAIL]' : '[RETRY]';
        echo "  {$tag} #{$id} → {$row['phone']} | Deneme: {$attempt}/" . SMS_MAX_ATTEMPTS . "\n";
    }

    usleep(200_000); // 200ms — provider rate-limit koruması
}

$end = date('Y-m-d H:i:s');
echo "[{$end}] Tamamlandı — Gönderildi: {$sent}, Başarısız: {$failed}\n\n";