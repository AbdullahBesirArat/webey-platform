<?php
/**
 * api/cron_cleanup.php
 * ─────────────────────────────────────────────────────────────
 * Crontab:  0 * * * *  php /var/www/html/api/cron_cleanup.php
 *
 * - Süresi dolmuş rate limit kayıtlarını siler
 * - Süresi dolmuş login_attempts temizler
 * - 30 günden eski csrf_tokens temizler (varsa)
 */
declare(strict_types=1);

// CLI'den çalışıyorsa define et
if (php_sapi_name() !== 'cli') {
    http_response_code(403);
    exit('CLI only');
}

require_once __DIR__ . '/../db.php';

$cleaned = [];

// Rate limits
try {
    $stmt = $pdo->prepare('DELETE FROM api_rate_limits WHERE expires_at < NOW()');
    $stmt->execute();
    $cleaned['api_rate_limits'] = $stmt->rowCount();
} catch (Throwable $e) {
    error_log('[cron_cleanup] api_rate_limits: ' . $e->getMessage());
}

// Login attempts (5 dakikadan eski)
try {
    $stmt = $pdo->prepare('DELETE FROM login_attempts WHERE attempted_at < DATE_SUB(NOW(), INTERVAL 5 MINUTE)');
    $stmt->execute();
    $cleaned['login_attempts'] = $stmt->rowCount();
} catch (Throwable $e) {
    error_log('[cron_cleanup] login_attempts: ' . $e->getMessage());
}

// CSRF tokens (varsa, 24 saatten eski)
try {
    $pdo->prepare("DELETE FROM csrf_tokens WHERE created_at < DATE_SUB(NOW(), INTERVAL 24 HOUR)")->execute();
} catch (Throwable) { /* Tablo yoksa atla */ }

$ts = date('Y-m-d H:i:s');
foreach ($cleaned as $table => $count) {
    echo "[$ts] Temizlendi: $table → $count satır\n";
}
echo "[$ts] Cron tamamlandı.\n";