<?php
declare(strict_types=1);
/**
 * api/calendar/appointments.php
 * GET ?start=YYYY-MM-DD HH:MM:SS&end=YYYY-MM-DD HH:MM:SS
 */

require_once __DIR__ . '/../admin/_bootstrap.php';
wb_method('GET');

$bid = $user['business_id'];
if (!$bid) wb_err('İşletme bulunamadı', 404, 'business_not_found');

$start = $_GET['start'] ?? null;
$end   = $_GET['end']   ?? null;
if (!$start || !$end) wb_err('start ve end zorunlu', 400, 'missing_params');

try {
    $stmt = $pdo->prepare("
        SELECT
            a.id, a.start_at, a.end_at, a.status, a.attended, a.notes,
            a.staff_id,   st.name AS staff_name,
            a.service_id, sv.name AS service_name, sv.duration_min, sv.price,
            a.customer_name, a.customer_phone, a.customer_email
        FROM appointments a
        LEFT JOIN staff    st ON st.id = a.staff_id
        LEFT JOIN services sv ON sv.id = a.service_id
        WHERE a.business_id = ?
          AND a.start_at >= ?
          AND a.start_at <  ?
        ORDER BY a.start_at ASC
    ");
    $stmt->execute([$bid, $start, $end]);

    $appointments = array_map(fn($r) => [
        'id'          => (string)$r['id'],
        'businessId'  => (string)$bid,
        'startAt'     => $r['start_at'],
        'endAt'       => $r['end_at'],
        'status'      => $r['status'] ?: 'pending',
        'attended'    => $r['attended'] === null ? null : (bool)$r['attended'],
        'notes'       => $r['notes'] ?: null,
        'staffId'     => $r['staff_id'] ? (string)$r['staff_id'] : null,
        'staffName'   => $r['staff_name'] ?: null,
        'serviceId'   => $r['service_id'] ? (string)$r['service_id'] : null,
        'serviceName' => $r['service_name'] ?: null,
        'durationMin' => $r['duration_min'] ? (int)$r['duration_min'] : null,
        'total'       => $r['price'] !== null ? (float)$r['price'] : null,
        'customer'    => [
            'name'  => $r['customer_name']  ?: null,
            'phone' => $r['customer_phone'] ?: null,
            'email' => $r['customer_email'] ?: null,
        ],
    ], $stmt->fetchAll());

    wb_ok(['appointments' => $appointments]);

} catch (Throwable $e) {
    error_log('[calendar/appointments] ' . $e->getMessage());
    wb_err('Randevular yüklenemedi', 500, 'internal_error');
}
