<?php
declare(strict_types=1);
/**
 * api/mobile/business/notifications/read.php
 * POST — Bildirimi okundu olarak işaretler.
 *
 * Body (JSON):
 *   notification_id : int (opsiyonel)  — verilirse tek bildirimi okur
 *   mark_all        : bool (opsiyonel) — true ise tüm bildirimleri okur
 */

require_once __DIR__ . '/../../_bootstrap.php';
require_once __DIR__ . '/../../_auth.php';
require_once __DIR__ . '/../_helpers.php';

wb_method('POST');

$auth = mobile_auth($pdo, ['business', 'admin']);
$ctx = mobile_business_context($pdo, $auth);
$businessId = (int)$ctx['business_id'];

$body = wb_body();
$notifId = isset($body['notification_id']) ? (int)$body['notification_id'] : 0;
$markAll = !empty($body['mark_all']);

if ($notifId <= 0 && !$markAll) {
    wb_err('notification_id veya mark_all zorunlu', 400, 'missing_param');
}

try {
    if ($markAll) {
        $pdo->prepare(
            'UPDATE notifications SET is_read = 1, read_at = NOW()
             WHERE business_id = ? AND is_read = 0 AND is_deleted = 0'
        )->execute([$businessId]);
    } else {
        $pdo->prepare(
            'UPDATE notifications SET is_read = 1, read_at = NOW()
             WHERE id = ? AND business_id = ? AND is_deleted = 0'
        )->execute([$notifId, $businessId]);
    }

    $unreadStmt = $pdo->prepare(
        'SELECT COUNT(*) FROM notifications WHERE business_id = ? AND is_read = 0 AND is_deleted = 0'
    );
    $unreadStmt->execute([$businessId]);
    $unreadCount = (int)$unreadStmt->fetchColumn();

    wb_ok([
        'updated' => true,
        'unread_count' => $unreadCount,
    ]);
} catch (Throwable $e) {
    error_log('[mobile/business/notifications/read.php] ' . $e->getMessage());
    wb_err('Bildirim okunamadı', 500, 'internal_error');
}
