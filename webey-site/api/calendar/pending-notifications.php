<?php
declare(strict_types=1);
/**
 * api/calendar/pending-notifications.php
 * GET ?since=UNIX_TIMESTAMP — Son sorgudan bu yana gelen yeni randevular
 * wb-notifications.js tarafından tüm admin sayfalarında 30sn poll edilir
 */

require_once __DIR__ . '/../admin/_bootstrap.php';
wb_method('GET');

$bid   = $user['business_id'];
if (!$bid) wb_err('İşletme bulunamadı', 404, 'business_not_found');
$since = (int)($_GET['since'] ?? (time() - 60));

try {
    $sinceStr = date('Y-m-d H:i:s', $since);

    $stmt = $pdo->prepare("
        SELECT a.id, a.status, a.customer_name, a.customer_phone,
               a.start_at, a.end_at, a.created_at,
               s.name AS service_name, st.name AS staff_name,
               n.id AS notif_id
        FROM appointments a
        LEFT JOIN services s  ON s.id  = a.service_id
        LEFT JOIN staff    st ON st.id = a.staff_id
        LEFT JOIN notifications n ON n.appointment_id = a.id AND n.business_id = a.business_id AND n.type = 'booking'
        WHERE a.business_id = ? AND a.created_at > ? AND a.status = 'pending'
        ORDER BY a.created_at DESC
        LIMIT 20
    ");
    $stmt->execute([$bid, $sinceStr]);
    $rows = $stmt->fetchAll();

    $items = array_map(function($r) use ($pdo, $bid) {
        $start = new DateTime($r['start_at']);

        return [
            'id'            => (string)$r['id'],
            'notifId'       => $r['notif_id'] ? (string)$r['notif_id'] : null,
            'status'        => $r['status'],
            'customerName'  => $r['customer_name'],
            'customerPhone' => $r['customer_phone'],
            'serviceName'   => $r['service_name'] ?? 'Hizmet',
            'staffName'     => $r['staff_name'] ?? null,
            'startAt'       => $r['start_at'],
            'startFmt'      => $start->format('d.m.Y H:i'),
            'createdAt'     => $r['created_at'],
        ];
    }, $rows);

    wb_ok(['items' => $items, 'ts' => time()]);

} catch (Throwable $e) {
    error_log('[calendar/pending-notifications] ' . $e->getMessage());
    wb_err('Bildirimler yüklenemedi', 500, 'internal_error');
}