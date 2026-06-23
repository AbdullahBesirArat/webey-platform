<?php
declare(strict_types=1);
/**
 * api/superadmin/app/appointments.php
 * GET — Randevu listesi (filtre + pagination). READ-ONLY.
 * Provider raw_payload / checkout_token / provider_payment_id dönmez.
 *
 * Filtreler: date=today|week|custom(&from=&to=), status, deposit_status,
 *            business_id, q, page, limit
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/_helpers.php';
wb_method('GET');

try {
    $pg     = sa_page_params(25);
    $where  = [];
    $params = [];

    $date = trim((string)($_GET['date'] ?? ''));
    if ($date === 'today') {
        $where[] = 'DATE(a.start_at) = CURDATE()';
    } elseif ($date === 'week') {
        $where[] = 'YEARWEEK(a.start_at, 1) = YEARWEEK(CURDATE(), 1)';
    } elseif ($date === 'custom') {
        $from = trim((string)($_GET['from'] ?? ''));
        $to   = trim((string)($_GET['to'] ?? ''));
        if ($from !== '' && preg_match('/^\d{4}-\d{2}-\d{2}$/', $from)) {
            $where[] = 'DATE(a.start_at) >= ?';
            $params[] = $from;
        }
        if ($to !== '' && preg_match('/^\d{4}-\d{2}-\d{2}$/', $to)) {
            $where[] = 'DATE(a.start_at) <= ?';
            $params[] = $to;
        }
    }

    $status = trim((string)($_GET['status'] ?? ''));
    $validStatuses = ['pending','approved','cancelled','no_show','completed','rejected','declined','cancellation_requested'];
    if (in_array($status, $validStatuses, true)) {
        $where[] = 'a.status = ?';
        $params[] = $status;
    }

    $depositStatus = trim((string)($_GET['deposit_status'] ?? ''));
    if (in_array($depositStatus, ['pending','customer_marked_sent','paid','not_received'], true)) {
        $where[] = 'a.deposit_status = ?';
        $params[] = $depositStatus;
    }

    $businessId = (int)($_GET['business_id'] ?? 0);
    if ($businessId > 0) {
        $where[] = 'a.business_id = ?';
        $params[] = $businessId;
    }

    $q = trim((string)($_GET['q'] ?? ''));
    if ($q !== '') {
        $where[] = '(a.customer_name LIKE ? OR b.name LIKE ?)';
        $like    = sa_like($q);
        array_push($params, $like, $like);
    }

    $whereSql = $where ? ('WHERE ' . implode(' AND ', $where)) : '';
    $joinSql  = 'FROM appointments a JOIN businesses b ON b.id = a.business_id';

    $total = (int)sa_val($pdo, "SELECT COUNT(*) $joinSql $whereSql", $params);

    $rows = sa_rows($pdo, "
        SELECT
            a.id, a.business_id, b.name AS business_name,
            a.customer_name, a.customer_phone, a.customer_user_id,
            a.start_at, a.end_at, a.status, a.booking_source,
            a.deposit_required, a.deposit_amount, a.deposit_status,
            a.deposit_reference_code, a.deposit_paid_at,
            a.created_at,
            s.name AS service_name, st.name AS staff_name
        $joinSql
        LEFT JOIN services s ON s.id = a.service_id
        LEFT JOIN staff st ON st.id = a.staff_id
        $whereSql
        ORDER BY a.start_at DESC
        LIMIT {$pg['limit']} OFFSET {$pg['offset']}
    ", $params);

    $items = array_map(static function (array $r): array {
        return [
            'id'                     => (int)$r['id'],
            'business_id'            => (int)$r['business_id'],
            'business_name'          => $r['business_name'],
            'customer_name'          => $r['customer_name'],
            'customer_phone_masked'  => sa_mask_phone($r['customer_phone']),
            'customer_user_id'       => $r['customer_user_id'] !== null ? (int)$r['customer_user_id'] : null,
            'service_name'           => $r['service_name'],
            'staff_name'             => $r['staff_name'],
            'start_at'               => $r['start_at'],
            'end_at'                 => $r['end_at'],
            'status'                 => $r['status'],
            'booking_source'         => $r['booking_source'],
            'deposit_required'       => (bool)$r['deposit_required'],
            'deposit_amount'         => $r['deposit_amount'] !== null ? (float)$r['deposit_amount'] : null,
            'deposit_status'         => $r['deposit_status'],
            'deposit_reference_code' => $r['deposit_reference_code'],
            'deposit_paid_at'        => $r['deposit_paid_at'],
            'created_at'             => $r['created_at'],
        ];
    }, $rows);

    wb_ok(sa_list_payload($items, $total, $pg));

} catch (Throwable $e) {
    error_log('[superadmin/app/appointments] ' . $e->getMessage());
    wb_err('Randevu listesi yüklenemedi', 500, 'internal_error');
}
