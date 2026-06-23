<?php
declare(strict_types=1);
/**
 * api/notifications/welcome.php
 * POST — İlk giriş hoşgeldiniz bildirimi
 * Eğer bu işletme için daha önce welcome bildirimi oluşturulmadıysa oluşturur.
 * Frontend sessionStorage ile sadece bir kez çağırır.
 */

require_once __DIR__ . '/../admin/_bootstrap.php';
wb_method('POST');

$bid    = (int)($user['business_id'] ?? 0);
$userId = (int)($user['user_id']     ?? 0);
if (!$bid) wb_ok(['created' => false, 'reason' => 'no_business']);

try {
    // Daha önce welcome bildirimi var mı?
    $check = $pdo->prepare("
        SELECT id FROM notifications
        WHERE business_id = ? AND type = 'welcome'
        LIMIT 1
    ");
    $check->execute([$bid]);
    if ($check->fetch()) {
        wb_ok(['created' => false, 'reason' => 'already_exists']);
    }

    // İşletme adını çek
    $bizStmt = $pdo->prepare("SELECT name FROM businesses WHERE id = ? LIMIT 1");
    $bizStmt->execute([$bid]);
    $bizName = $bizStmt->fetchColumn() ?: 'İşletmeniz';

    // Welcome bildirimi ekle
    $pdo->prepare("
        INSERT INTO notifications
          (business_id, type, customer_name, result, is_read, created_at)
        VALUES (?, 'welcome', ?, 'info', 0, NOW())
    ")->execute([$bid, $bizName]);

    wb_ok(['created' => true]);

} catch (Throwable $e) {
    error_log('[notifications/welcome] ' . $e->getMessage());
    wb_ok(['created' => false, 'reason' => 'error']);
}