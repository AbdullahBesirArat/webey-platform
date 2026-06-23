<?php
declare(strict_types=1);
/**
 * api/notifications/summary.php
 * GET ?since=UNIX_TIMESTAMP
 */

require_once __DIR__ . '/../admin/_bootstrap.php';
wb_method('GET');

$bid = $user['business_id'];
if (!$bid) {
    wb_err('Isletme bulunamadi', 404, 'business_not_found');
}

$since = max(0, (int)($_GET['since'] ?? (time() - 300)));
$sinceStr = date('Y-m-d H:i:s', $since);

$formatStart = static function (?string $value): ?string {
    if (!$value) {
        return null;
    }
    try {
        return (new DateTimeImmutable($value))->format('d.m.Y H:i');
    } catch (Throwable) {
        return null;
    }
};

try {
    $countStmt = $pdo->prepare('
        SELECT COUNT(*)
        FROM notifications
        WHERE business_id = ? AND is_deleted = 0 AND is_read = 0
    ');
    $countStmt->execute([$bid]);
    $unreadCount = (int)$countStmt->fetchColumn();

    $apptStmt = $pdo->prepare("
        SELECT a.id, a.status, a.customer_name, a.customer_phone,
               a.start_at, a.created_at,
               s.name AS service_name,
               st.name AS staff_name,
               n.id AS notif_id
        FROM appointments a
        LEFT JOIN services s ON s.id = a.service_id
        LEFT JOIN staff st ON st.id = a.staff_id
        LEFT JOIN notifications n
               ON n.appointment_id = a.id
              AND n.business_id = a.business_id
              AND n.type = 'booking'
              AND n.is_deleted = 0
        WHERE a.business_id = ?
          AND a.created_at > ?
          AND a.status = 'pending'
        ORDER BY a.created_at DESC
        LIMIT 20
    ");
    $apptStmt->execute([$bid, $sinceStr]);
    $appointments = array_map(static function (array $row) use ($formatStart): array {
        return [
            'id' => (string)$row['id'],
            'notifId' => !empty($row['notif_id']) ? (string)$row['notif_id'] : null,
            'status' => (string)$row['status'],
            'customerName' => (string)($row['customer_name'] ?? ''),
            'customerPhone' => $row['customer_phone'] ?? null,
            'serviceName' => $row['service_name'] ?? 'Hizmet',
            'staffName' => $row['staff_name'] ?? null,
            'startAt' => $row['start_at'],
            'startFmt' => $formatStart($row['start_at']),
            'createdAt' => $row['created_at'],
        ];
    }, $apptStmt->fetchAll());

    $cancelStmt = $pdo->prepare("
        SELECT a.id, a.status, a.customer_name, a.customer_phone,
               a.start_at, a.created_at,
               s.name AS service_name,
               st.name AS staff_name,
               n.id AS notif_id,
               n.created_at AS notif_created_at
        FROM appointments a
        LEFT JOIN services s ON s.id = a.service_id
        LEFT JOIN staff st ON st.id = a.staff_id
        LEFT JOIN notifications n
               ON n.appointment_id = a.id
              AND n.business_id = a.business_id
              AND n.type = 'cancellation'
              AND n.is_deleted = 0
        WHERE a.business_id = ?
          AND a.status = 'cancellation_requested'
        ORDER BY a.start_at DESC
        LIMIT 50
    ");
    $cancelStmt->execute([$bid]);
    $cancellations = array_map(static function (array $row) use ($formatStart): array {
        return [
            'id' => (string)$row['id'],
            'notifId' => !empty($row['notif_id']) ? (string)$row['notif_id'] : null,
            'status' => (string)$row['status'],
            'customerName' => $row['customer_name'] ?? null,
            'customerPhone' => $row['customer_phone'] ?? null,
            'serviceName' => $row['service_name'] ?? 'Hizmet',
            'staffName' => $row['staff_name'] ?? null,
            'startAt' => $row['start_at'],
            'startFmt' => $formatStart($row['start_at']),
            'cancelledAt' => $row['notif_created_at'] ?? $row['created_at'],
        ];
    }, $cancelStmt->fetchAll());

    $systemStmt = $pdo->prepare("
        SELECT id, type, customer_name, customer_phone, service_name, staff_name,
               appointment_start, result, is_read, created_at, appointment_id
        FROM notifications
        WHERE business_id = ?
          AND is_deleted = 0
          AND is_read = 0
        ORDER BY created_at DESC
        LIMIT 50
    ");
    $systemStmt->execute([$bid]);
    $systemRows = $systemStmt->fetchAll();

    $systemItems = [];
    $seenGuideKeys = [];
    foreach ($systemRows as $row) {
        $rawType = (string)($row['type'] ?? '');
        $isLegacyGuide = $rawType === ''
            && empty($row['appointment_id'])
            && !empty($row['staff_name'])
            && str_ends_with((string)$row['staff_name'], '.html')
            && !empty($row['customer_name'])
            && !empty($row['service_name']);
        $type = ($rawType === 'guide' || $isLegacyGuide) ? 'guide' : $rawType;
        $isSystemType = in_array($type, ['subscription_expiry_3d', 'subscription_expiry_2d', 'subscription_expiry_1d', 'subscription_expired', 'guide'], true);
        if (!$isSystemType) {
            continue;
        }

        $guideKey = null;
        if ($type === 'guide') {
            $guideKey = (string)($row['result'] ?? '');
            if ($guideKey === '') {
                $guideKey = basename((string)($row['staff_name'] ?? ''), '.html');
            }
            if ($guideKey !== '') {
                if (isset($seenGuideKeys[$guideKey])) {
                    continue;
                }
                $seenGuideKeys[$guideKey] = true;
            }
        }

        $systemItems[] = [
            'id' => (string)$row['id'],
            'type' => $type,
            'customerName' => $row['customer_name'] ?? '',
            'customerPhone' => $row['customer_phone'] ?? null,
            'serviceName' => $row['service_name'] ?? null,
            'staffName' => $row['staff_name'] ?? null,
            'appointmentStart' => $row['appointment_start'] ?? null,
            'startFmt' => $formatStart($row['appointment_start'] ?? null),
            'result' => $row['result'] ?? 'pending',
            'isRead' => (bool)$row['is_read'],
            'createdAt' => $row['created_at'],
            'appointmentId' => !empty($row['appointment_id']) ? (string)$row['appointment_id'] : null,
            'title' => $type === 'guide' ? ($row['customer_name'] ?? '') : null,
            'message' => $type === 'guide' ? ($row['service_name'] ?? '') : null,
            'linkUrl' => $type === 'guide' ? ($row['staff_name'] ?? '') : null,
            'guideKey' => $type === 'guide' ? $guideKey : null,
        ];
    }

    wb_ok([
        'ts' => time(),
        'counts' => ['unread' => $unreadCount],
        'appointments' => $appointments,
        'cancellations' => $cancellations,
        'system' => $systemItems,
    ]);
} catch (Throwable $e) {
    error_log('[notifications/summary] ' . $e->getMessage());
    wb_err('Bildirim ozetleri yuklenemedi', 500, 'internal_error');
}
