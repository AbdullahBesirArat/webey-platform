<?php
declare(strict_types=1);
/**
 * api/calendar/cancellation-requests.php
 * GET - 'cancellation_requested' durumundaki randevular
 */

require_once __DIR__ . '/../admin/_bootstrap.php';
wb_method('GET');

$bid = $user['business_id'];
if (!$bid) wb_err('Isletme bulunamadi', 404, 'business_not_found');

try {
    $stmt = $pdo->prepare("
        SELECT a.id, a.status, a.customer_name, a.customer_phone,
               a.start_at, a.end_at, a.created_at,
               s.name AS service_name, st.name AS staff_name,
               n.id AS notif_id,
               n.created_at AS notif_created_at
        FROM appointments a
        LEFT JOIN services s  ON s.id  = a.service_id
        LEFT JOIN staff    st ON st.id = a.staff_id
        LEFT JOIN notifications n
               ON n.appointment_id = a.id
              AND n.business_id = a.business_id
              AND n.type = 'cancellation'
              AND n.is_deleted = 0
        WHERE a.business_id = ? AND a.status = 'cancellation_requested'
        ORDER BY a.start_at DESC
        LIMIT 50
    ");
    $stmt->execute([$bid]);

    $items = array_map(function ($r) {
        $start = new DateTime($r['start_at']);
        return [
            'id'            => (string)$r['id'],
            'notifId'       => !empty($r['notif_id']) ? (string)$r['notif_id'] : null,
            'status'        => $r['status'],
            'customerName'  => $r['customer_name'] ?? null,
            'customerPhone' => $r['customer_phone'] ?? null,
            'serviceName'   => $r['service_name'] ?? 'Hizmet',
            'staffName'     => $r['staff_name'] ?? null,
            'startAt'       => $r['start_at'],
            'startFmt'      => $start->format('d.m.Y H:i'),
            'cancelledAt'   => $r['notif_created_at'] ?? $r['created_at'],
        ];
    }, $stmt->fetchAll());

    wb_ok(['items' => $items, 'ts' => time()]);
} catch (Throwable $e) {
    error_log('[calendar/cancellation-requests] ' . $e->getMessage());
    wb_err('Iptal talepleri yuklenemedi', 500, 'internal_error');
}
