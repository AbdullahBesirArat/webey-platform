<?php
declare(strict_types=1);
/**
 * api/mobile/business/appointments.php
 * GET - Token sahibi isletmenin randevulari.
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';
require_once __DIR__ . '/_helpers.php';

wb_method('GET');

$auth = mobile_auth($pdo, ['business', 'admin']);
$ctx = mobile_business_context($pdo, $auth);
$businessId = (int)$ctx['business_id'];

$rawStatus = strtolower((string)mobile_param('status', 'all'));
$status = in_array($rawStatus, ['today', 'upcoming', 'pending', 'completed', 'cancelled', 'all'], true)
    ? $rawStatus
    : 'all';

$date = (string)mobile_param('date', '');
if ($date !== '' && !preg_match('/^\d{4}-\d{2}-\d{2}$/', $date)) {
    wb_err('date YYYY-MM-DD formatinda olmali', 400, 'invalid_date');
}

// Opsiyonel tarih araligi (takvim hafta seridi nokta gostergeleri icin).
// 'date' verilmisse oncelik onda; aralik yalnizca 'date' bossa uygulanir.
$from = (string)mobile_param('from', '');
$to   = (string)mobile_param('to', '');
foreach (['from' => $from, 'to' => $to] as $rangeKey => $rangeVal) {
    if ($rangeVal !== '' && !preg_match('/^\d{4}-\d{2}-\d{2}$/', $rangeVal)) {
        wb_err($rangeKey . ' YYYY-MM-DD formatinda olmali', 400, 'invalid_range');
    }
}

$page = max(1, (int)(mobile_int_param('page', 1) ?? 1));
$limit = mobile_limit(mobile_param('limit', 20), 20, 50);
$offset = ($page - 1) * $limit;

try {
    $filter = mobile_business_status_filter_sql($status);
    $whereSql = ' WHERE a.business_id = ?' . $filter['sql'];
    $params = array_merge([$businessId], $filter['params']);

    if ($date !== '') {
        $whereSql .= ' AND DATE(a.start_at) = ?';
        $params[] = $date;
    } elseif ($from !== '' && $to !== '') {
        $whereSql .= ' AND DATE(a.start_at) BETWEEN ? AND ?';
        $params[] = $from;
        $params[] = $to;
    }

    $countStmt = $pdo->prepare('SELECT COUNT(*) FROM appointments a' . $whereSql);
    $countStmt->execute($params);
    $total = (int)$countStmt->fetchColumn();

    $orderSql = $status === 'completed' || $status === 'cancelled'
        ? ' ORDER BY a.start_at DESC'
        : ' ORDER BY a.start_at ASC';

    $stmt = $pdo->prepare(
        mobile_business_appointment_select_sql()
        . $whereSql
        . $orderSql
        . ' LIMIT ' . (int)$limit . ' OFFSET ' . (int)$offset
    );
    $stmt->execute($params);
    $items = array_map('mobile_business_appointment_item', $stmt->fetchAll());

    // Deposit bilgisi (migration çalışmamışsa [] döner, items değişmez)
    $_depositMap   = mobile_batch_deposit_info($pdo, array_column($items, 'id'));
    $_emptyDeposit = ['required' => false, 'amount' => null, 'status' => null, 'paid_at' => null];
    foreach ($items as &$_depItem) {
        $_depItem['deposit'] = $_depositMap[$_depItem['id']] ?? $_emptyDeposit;
    }
    unset($_depItem);

    if ($items !== [] && mobile_table_has_column($pdo, 'appointments', 'cancel_refund_amount')) {
        $ids = array_map(static fn(array $item): int => (int)$item['id'], $items);
        $placeholders = implode(',', array_fill(0, count($ids), '?'));
        $finStmt = $pdo->prepare("
            SELECT id, paid_deposit_amount_snapshot, cancel_refund_amount,
                   cancel_retained_amount, cancel_rule_result
            FROM appointments
            WHERE business_id = ? AND id IN ($placeholders)
        ");
        $finStmt->execute(array_merge([$businessId], $ids));
        $financialById = [];
        foreach ($finStmt->fetchAll() as $finRow) {
            if (($finRow['cancel_rule_result'] ?? null) === null) {
                continue;
            }
            $financialById[(string)$finRow['id']] = [
                'paid_deposit'    => ($finRow['paid_deposit_amount_snapshot'] ?? null) !== null ? (float)$finRow['paid_deposit_amount_snapshot'] : 0.0,
                'refund_amount'   => ($finRow['cancel_refund_amount'] ?? null) !== null ? (float)$finRow['cancel_refund_amount'] : 0.0,
                'retained_amount' => ($finRow['cancel_retained_amount'] ?? null) !== null ? (float)$finRow['cancel_retained_amount'] : 0.0,
                'rule_result'     => (string)$finRow['cancel_rule_result'],
                'manual_refund'   => (($finRow['cancel_refund_amount'] ?? 0) > 0),
            ];
        }
        foreach ($items as &$finItem) {
            $finItem['cancellation'] = $financialById[(string)$finItem['id']] ?? null;
        }
        unset($finItem);
    }

    wb_ok([
        'items' => $items,
        'pagination' => [
            'page' => $page,
            'limit' => $limit,
            'total' => $total,
            'has_more' => ($offset + count($items)) < $total,
        ],
    ]);
} catch (Throwable $e) {
    error_log('[mobile/business/appointments.php] ' . $e->getMessage());
    wb_err('Randevular alinamadi', 500, 'internal_error');
}
