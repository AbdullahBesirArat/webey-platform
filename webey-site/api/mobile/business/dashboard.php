<?php
declare(strict_types=1);
/**
 * api/mobile/business/dashboard.php
 * GET - Token sahibi isletmenin mobil dashboard ozeti.
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';
require_once __DIR__ . '/_helpers.php';

wb_method('GET');

$auth = mobile_auth($pdo, ['business', 'admin']);
$ctx = mobile_business_context($pdo, $auth);
$businessId = (int)$ctx['business_id'];

try {
    $summaryStmt = $pdo->prepare("
        SELECT
            SUM(CASE WHEN DATE(a.start_at) = CURDATE() THEN 1 ELSE 0 END) AS today_appointments,
            SUM(CASE WHEN a.status IN ('pending','cancellation_requested') THEN 1 ELSE 0 END) AS pending_appointments,
            SUM(CASE
                    WHEN a.start_at >= NOW()
                     AND a.status NOT IN ('completed','cancelled','rejected','declined','no_show')
                    THEN 1 ELSE 0
                END) AS upcoming_appointments,
            SUM(CASE
                    WHEN a.status = 'completed'
                     AND a.start_at >= DATE_FORMAT(CURDATE(), '%Y-%m-01')
                     AND a.start_at < DATE_ADD(DATE_FORMAT(CURDATE(), '%Y-%m-01'), INTERVAL 1 MONTH)
                    THEN 1 ELSE 0
                END) AS completed_this_month,
            SUM(CASE
                    WHEN a.status IN ('cancelled','rejected','declined','no_show')
                     AND a.start_at >= DATE_FORMAT(CURDATE(), '%Y-%m-01')
                     AND a.start_at < DATE_ADD(DATE_FORMAT(CURDATE(), '%Y-%m-01'), INTERVAL 1 MONTH)
                    THEN 1 ELSE 0
                END) AS cancelled_this_month,
            COALESCE(SUM(CASE
                    WHEN a.status = 'completed'
                     AND a.start_at >= DATE_FORMAT(CURDATE(), '%Y-%m-01')
                     AND a.start_at < DATE_ADD(DATE_FORMAT(CURDATE(), '%Y-%m-01'), INTERVAL 1 MONTH)
                    THEN COALESCE(s.price, 0) ELSE 0
                END), 0) AS monthly_revenue_estimate
        FROM appointments a
        LEFT JOIN services s ON s.id = a.service_id AND s.business_id = a.business_id
        WHERE a.business_id = ?
    ");
    $summaryStmt->execute([$businessId]);
    $summaryRow = $summaryStmt->fetch() ?: [];

    $todayStmt = $pdo->prepare(
        mobile_business_appointment_select_sql()
        . " WHERE a.business_id = ?
              AND DATE(a.start_at) = CURDATE()
            ORDER BY a.start_at ASC
            LIMIT 10"
    );
    $todayStmt->execute([$businessId]);
    $todayItems = array_map('mobile_business_appointment_item', $todayStmt->fetchAll());

    $pendingStmt = $pdo->prepare(
        mobile_business_appointment_select_sql()
        . " WHERE a.business_id = ?
              AND a.status IN ('pending','cancellation_requested')
            ORDER BY a.start_at ASC
            LIMIT 10"
    );
    $pendingStmt->execute([$businessId]);
    $pendingItems = array_map('mobile_business_appointment_item', $pendingStmt->fetchAll());

    // Deposit bilgisi (migration çalışmamışsa [] döner, items değişmez)
    $_allDepIds    = array_unique(array_merge(
        array_column($todayItems, 'id'),
        array_column($pendingItems, 'id'),
    ));
    $_depositMap   = mobile_batch_deposit_info($pdo, $_allDepIds);
    $_emptyDeposit = ['required' => false, 'amount' => null, 'status' => null, 'paid_at' => null];
    foreach ($todayItems as &$_depItem) {
        $_depItem['deposit'] = $_depositMap[$_depItem['id']] ?? $_emptyDeposit;
    }
    unset($_depItem);
    foreach ($pendingItems as &$_depItem) {
        $_depItem['deposit'] = $_depositMap[$_depItem['id']] ?? $_emptyDeposit;
    }
    unset($_depItem);

    wb_ok([
        'summary' => [
            'today_appointments' => (int)($summaryRow['today_appointments'] ?? 0),
            'pending_appointments' => (int)($summaryRow['pending_appointments'] ?? 0),
            'upcoming_appointments' => (int)($summaryRow['upcoming_appointments'] ?? 0),
            'completed_this_month' => (int)($summaryRow['completed_this_month'] ?? 0),
            'cancelled_this_month' => (int)($summaryRow['cancelled_this_month'] ?? 0),
            'monthly_revenue_estimate' => (float)($summaryRow['monthly_revenue_estimate'] ?? 0),
        ],
        'today' => [
            'items' => $todayItems,
        ],
        'pending' => [
            'items' => $pendingItems,
        ],
    ]);
} catch (Throwable $e) {
    error_log('[mobile/business/dashboard.php] ' . $e->getMessage());
    wb_err('Dashboard bilgileri alinamadi', 500, 'internal_error');
}
