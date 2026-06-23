<?php
/**
 * api/cron_send_emails.php
 * ─────────────────────────────────────────────────────────────────────
 * Crontab:  * * * * *  php /var/www/html/api/cron_send_emails.php >> /var/log/webey_emails.log 2>&1
 * (Her dakika çalışır — dakika başına max 50 email gönderir)
 *
 * Görevler:
 *   1. email_queue tablosundaki pending/başarısız emailları işler
 *   2. scheduled_at'i bekler (null = hemen gönder)
 *   3. Her email max 3 deneme hakkı alır, sonra 'failed' olarak işaretlenir
 *   4. Başarılı gönderimde status → 'sent', sent_at doldurulur
 * ─────────────────────────────────────────────────────────────────────
 */
declare(strict_types=1);

// Sadece CLI'den çalışsın (web'den erişimi engelle)
if (PHP_SAPI !== 'cli' && ($_SERVER['REMOTE_ADDR'] ?? '') !== '127.0.0.1') {
    http_response_code(403);
    exit('CLI only');
}

require_once __DIR__ . '/../db.php';
require_once __DIR__ . '/_mailer.php';

// ── Ayarlar ───────────────────────────────────────────────────────────
const MAX_ATTEMPTS   = 3;    // Kaç başarısız denemeden sonra 'failed' işaretle
const BATCH_SIZE     = 50;   // Tek çalışmada max kaç email gönderilsin
const RETRY_DELAY_S  = 300;  // Başarısız emailı kaç saniye sonra tekrar dene (5 dk)

$now     = date('Y-m-d H:i:s');
$sent    = 0;
$failed  = 0;
$skipped = 0;

echo "[{$now}] cron_send_emails başladı\n";

// ── Email kuyruğunu çek ───────────────────────────────────────────────
// Şartlar:
//   - status = 'pending'  VEYA  (status = 'failed' ve attempts < MAX ve son deneme üzerinden RETRY_DELAY geçti)
//   - scheduled_at IS NULL  VEYA  scheduled_at <= NOW()
try {
    $stmt = $pdo->prepare("
        SELECT id, to_email, to_name, subject, body_html, attempts
        FROM   email_queue
        WHERE  status != 'sent'
          AND  attempts < :max_attempts
          AND  (scheduled_at IS NULL OR scheduled_at <= NOW())
          AND  (
                  status = 'pending'
               OR (status = 'failed' AND created_at <= DATE_SUB(NOW(), INTERVAL :retry_delay SECOND))
               )
        ORDER BY created_at ASC
        LIMIT  :batch
    ");
    $stmt->bindValue(':max_attempts', MAX_ATTEMPTS, PDO::PARAM_INT);
    $stmt->bindValue(':retry_delay',  RETRY_DELAY_S, PDO::PARAM_INT);
    $stmt->bindValue(':batch',        BATCH_SIZE, PDO::PARAM_INT);
    $stmt->execute();
    $emails = $stmt->fetchAll(PDO::FETCH_ASSOC);
} catch (Throwable $e) {
    echo "[HATA] Email kuyruğu okunamadı: " . $e->getMessage() . "\n";
    exit(1);
}

if (empty($emails)) {
    echo "[{$now}] Gönderilecek email yok.\n";
    exit(0);
}

echo "  → " . count($emails) . " email işlenecek\n";

// ── Her emaili işle ───────────────────────────────────────────────────
foreach ($emails as $email) {
    $id      = (int)$email['id'];
    $attempt = (int)$email['attempts'] + 1;

    // Göndermeye çalış
    $ok = false;
    try {
        $ok = wbMail(
            $email['to_email'],
            $email['to_name'] ?? '',
            $email['subject'],
            $email['body_html']
        );
    } catch (Throwable $e) {
        $lastError = $e->getMessage();
        error_log("[cron_send_emails] #{$id} exception: " . $lastError);
    }

    if ($ok) {
        // ── Başarılı ──────────────────────────────────────────────────
        try {
            $pdo->prepare("
                UPDATE email_queue
                SET    status   = 'sent',
                       attempts = ?,
                       sent_at  = NOW(),
                       last_error = NULL
                WHERE  id = ?
            ")->execute([$attempt, $id]);
        } catch (Throwable $e) {
            error_log("[cron_send_emails] #{$id} DB güncelleme hatası (sent): " . $e->getMessage());
        }

        $sent++;
        echo "  [OK]  #{$id} → {$email['to_email']} | {$email['subject']}\n";

    } else {
        // ── Başarısız ─────────────────────────────────────────────────
        $newStatus = ($attempt >= MAX_ATTEMPTS) ? 'failed' : 'pending';
        $errMsg    = $lastError ?? 'wbMail false döndü';

        try {
            $pdo->prepare("
                UPDATE email_queue
                SET    status     = ?,
                       attempts   = ?,
                       last_error = ?
                WHERE  id = ?
            ")->execute([$newStatus, $attempt, $errMsg, $id]);
        } catch (Throwable $e) {
            error_log("[cron_send_emails] #{$id} DB güncelleme hatası (failed): " . $e->getMessage());
        }

        $failed++;
        $tag = ($newStatus === 'failed') ? '[FAIL]' : '[RETRY]';
        echo "  {$tag} #{$id} → {$email['to_email']} | Deneme: {$attempt}/" . MAX_ATTEMPTS . "\n";
    }

    // Her email arasında SMTP'yi bunaltmamak için kısa bekleme
    usleep(100_000); // 100ms
}

// ── Özet ──────────────────────────────────────────────────────────────
$end = date('Y-m-d H:i:s');
echo "[{$end}] Tamamlandı — Gönderildi: {$sent}, Başarısız: {$failed}\n\n";