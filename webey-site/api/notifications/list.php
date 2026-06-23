<?php
declare(strict_types=1);
/**
 * api/notifications/list.php
 * GET ?limit=20&offset=0 — Admin bildirim listesi
 */

require_once __DIR__ . '/../admin/_bootstrap.php';
wb_method('GET');

$bid    = $user['business_id'];
if (!$bid) wb_err('İşletme bulunamadı', 404, 'business_not_found');
$limit  = min((int)($_GET['limit']  ?? 20), 100);
$offset = (int)($_GET['offset'] ?? 0);

try {
    $stmt = $pdo->prepare("
        SELECT id, type, customer_name, customer_phone, service_name, staff_name,
               appointment_start, result, is_read, created_at, appointment_id
        FROM notifications
        WHERE business_id = ? AND is_deleted = 0
        ORDER BY created_at DESC
        LIMIT ? OFFSET ?
    ");
    $stmt->execute([$bid, $limit, $offset]);
    $rows = $stmt->fetchAll();

    $items = array_map(function($r) {
        $startFmt = null;
        if (!empty($r['appointment_start'])) {
            try {
                $dt = new DateTimeImmutable($r['appointment_start']);
                $startFmt = $dt->format('d.m.Y H:i');
            } catch (Throwable) {}
        }
        $rawType = (string)($r['type'] ?? '');
        $isLegacyGuide = $rawType === ''
            && empty($r['appointment_id'])
            && !empty($r['staff_name'])
            && str_ends_with((string)$r['staff_name'], '.html')
            && !empty($r['customer_name'])
            && !empty($r['service_name']);
        $type = ($rawType === 'guide' || $isLegacyGuide) ? 'guide' : $rawType;
        $guideKey = null;
        if ($type === 'guide') {
            $guideKey = (string)($r['result'] ?? '');
            if ($guideKey === '') {
                $guideKey = basename((string)($r['staff_name'] ?? ''), '.html');
            }
        }
        return [
            'id'              => (string)$r['id'],
            'type'            => $type,
            'customerName'    => $r['customer_name']   ?? '',
            'customerPhone'   => $r['customer_phone']  ?? null,
            'serviceName'     => $r['service_name']    ?? null,
            'staffName'       => $r['staff_name']      ?? null,
            'appointmentStart'=> $r['appointment_start'] ?? null,
            'startFmt'        => $startFmt,
            'result'          => $r['result']          ?? 'pending',
            'isRead'          => (bool)$r['is_read'],
            'createdAt'       => $r['created_at'],
            'appointmentId'   => $r['appointment_id'] ? (string)$r['appointment_id'] : null,
            'title'           => $type === 'guide' ? ($r['customer_name'] ?? '') : null,
            'message'         => $type === 'guide' ? ($r['service_name'] ?? '') : null,
            'linkUrl'         => $type === 'guide' ? ($r['staff_name'] ?? '') : null,
            'guideKey'        => $type === 'guide' ? $guideKey : null,
            'category'        => in_array($type, ['booking', 'cancellation'], true) ? 'appointment' : 'system',
        ];
    }, $rows);

    $seenGuideKeys = [];
    $items = array_values(array_filter($items, static function(array $item) use (&$seenGuideKeys): bool {
        if (($item['type'] ?? '') !== 'guide') {
            return true;
        }
        $key = (string)($item['guideKey'] ?? $item['id'] ?? '');
        if ($key === '') {
            return true;
        }
        if (isset($seenGuideKeys[$key])) {
            return false;
        }
        $seenGuideKeys[$key] = true;
        return true;
    }));

    $cStmt = $pdo->prepare('SELECT COUNT(*) FROM notifications WHERE business_id = ? AND is_deleted = 0');
    $cStmt->execute([$bid]);
    $total = (int)$cStmt->fetchColumn();

    wb_ok(['items' => $items, 'total' => $total, 'notifications' => $items]);

} catch (Throwable $e) {
    error_log('[notifications/list] ' . $e->getMessage());
    wb_err('Bildirimler yüklenemedi', 500, 'internal_error');
}
