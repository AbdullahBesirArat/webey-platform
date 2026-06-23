<?php
declare(strict_types=1);
/**
 * api/notifications/mark-read.php
 * POST { id } | { ids: [...] } | { appointmentId, type? }
 */

require_once __DIR__ . '/../admin/_bootstrap.php';
wb_method('POST');

$bid = $user['business_id'];
if (!$bid) wb_err('Isletme bulunamadi', 404, 'business_not_found');

$in = wb_body();

$ids = [];
if (!empty($in['ids']) && is_array($in['ids'])) {
    $ids = array_values(array_filter(array_map('intval', $in['ids'])));
} elseif (!empty($in['id'])) {
    $ids = [(int)$in['id']];
}

$appointmentId = (int)($in['appointmentId'] ?? $in['appointment_id'] ?? 0);
$type = trim((string)($in['type'] ?? ''));

if (empty($ids) && !$appointmentId) {
    wb_err('id, ids veya appointmentId zorunlu', 400, 'missing_id');
}

try {
    $markedIds = [];

    if (!empty($ids)) {
        $placeholders = implode(',', array_fill(0, count($ids), '?'));
        $params = array_merge($ids, [$bid]);
        $pdo->prepare("UPDATE notifications SET is_read = 1, read_at = NOW() WHERE id IN ($placeholders) AND business_id = ?")
            ->execute($params);
        $markedIds = array_map('intval', $ids);
    }

    if ($appointmentId > 0) {
        $sql = "SELECT id
                FROM notifications
                WHERE appointment_id = ? AND business_id = ?";
        $params = [$appointmentId, $bid];

        if ($type !== '') {
            $sql .= " AND type = ?";
            $params[] = $type;
        }

        $sql .= " ORDER BY created_at DESC";
        $stmt = $pdo->prepare($sql);
        $stmt->execute($params);
        $apptNotifIds = array_map('intval', array_column($stmt->fetchAll(), 'id'));

        if (!empty($apptNotifIds)) {
            $placeholders = implode(',', array_fill(0, count($apptNotifIds), '?'));
            $params = array_merge($apptNotifIds, [$bid]);
            $pdo->prepare("UPDATE notifications SET is_read = 1, read_at = NOW() WHERE id IN ($placeholders) AND business_id = ?")
                ->execute($params);
            $markedIds = array_values(array_unique(array_merge($markedIds, $apptNotifIds)));
        }
    }

    wb_ok([
        'marked' => true,
        'ids' => $markedIds,
        'appointmentId' => $appointmentId ?: null,
    ]);
} catch (Throwable $e) {
    error_log('[notifications/mark-read] ' . $e->getMessage());
    wb_err('Islem tamamlanamadi', 500, 'internal_error');
}
