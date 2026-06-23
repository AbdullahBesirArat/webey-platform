<?php
declare(strict_types=1);
/**
 * api/mobile/business/revenue-report.php
 * GET — Token sahibi işletme için aylık gelir raporu döner.
 *
 * Query:
 *   month : "YYYY-MM" (opsiyonel; default mevcut ay, Europe/Istanbul)
 *
 * Hesaplama:
 *   - completed appointments * service.price = total_revenue
 *   - durumlara göre adetler
 *   - deposit (varsa) ve in-salon ayrı tutulur
 *   - service_breakdown: completed appointments * service.price gruplaması
 *   - monthly_trend: son 6 ayın completed revenue toplamı
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';
require_once __DIR__ . '/_helpers.php';

wb_method('GET');

$auth = mobile_auth($pdo, ['business', 'admin']);
$ctx = mobile_business_context($pdo, $auth);
$businessId = (int)$ctx['business_id'];

$monthInput = trim((string)mobile_param('month', ''));
if ($monthInput === '' || !preg_match('/^\d{4}-\d{2}$/', $monthInput)) {
    $monthInput = (new DateTimeImmutable('now', new DateTimeZone('Europe/Istanbul')))->format('Y-m');
}

try {
    $tz = new DateTimeZone('Europe/Istanbul');
    $monthStart = new DateTimeImmutable($monthInput . '-01 00:00:00', $tz);
    $monthEnd = $monthStart->modify('+1 month');

    $startStr = $monthStart->format('Y-m-d H:i:s');
    $endStr = $monthEnd->format('Y-m-d H:i:s');

    // Durum bazlı aggregate
    $aggStmt = $pdo->prepare(
        "SELECT a.status,
                COUNT(*) AS cnt,
                COALESCE(SUM(s.price), 0) AS revenue
         FROM appointments a
         LEFT JOIN services s ON s.id = a.service_id
         WHERE a.business_id = ?
           AND a.start_at >= ?
           AND a.start_at < ?
         GROUP BY a.status"
    );
    $aggStmt->execute([$businessId, $startStr, $endStr]);
    $statusAgg = [];
    foreach ($aggStmt->fetchAll() as $row) {
        $statusAgg[(string)$row['status']] = [
            'count' => (int)$row['cnt'],
            'revenue' => (float)$row['revenue'],
        ];
    }

    $completedCount = $statusAgg['completed']['count'] ?? 0;
    $totalRevenue = $statusAgg['completed']['revenue'] ?? 0.0;
    $cancelledCount = ($statusAgg['cancelled']['count'] ?? 0)
        + ($statusAgg['rejected']['count'] ?? 0)
        + ($statusAgg['declined']['count'] ?? 0);
    $noShowCount = $statusAgg['no_show']['count'] ?? 0;
    $pendingCount = ($statusAgg['pending']['count'] ?? 0)
        + ($statusAgg['cancellation_requested']['count'] ?? 0);
    $approvedCount = $statusAgg['approved']['count'] ?? 0;
    $appointmentCount = $completedCount + $cancelledCount + $noShowCount
        + $pendingCount + $approvedCount;

    // Deposit toplamları (deposit_payments tablosu varsa)
    $depositTotal = 0.0;
    $hasDepositPayments = false;
    try {
        $colCheck = $pdo->prepare(
            "SELECT COUNT(*) FROM information_schema.TABLES
             WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'deposit_payments'"
        );
        $colCheck->execute();
        $hasDepositPayments = (int)$colCheck->fetchColumn() > 0;
    } catch (Throwable) {
        $hasDepositPayments = false;
    }
    if ($hasDepositPayments) {
        try {
            $depStmt = $pdo->prepare(
                "SELECT COALESCE(SUM(dp.amount), 0) AS total
                 FROM deposit_payments dp
                 INNER JOIN appointments a ON a.id = dp.appointment_id
                 WHERE a.business_id = ?
                   AND dp.status IN ('paid','captured','succeeded','settled')
                   AND dp.created_at >= ?
                   AND dp.created_at < ?"
            );
            $depStmt->execute([$businessId, $startStr, $endStr]);
            $depositTotal = (float)($depStmt->fetchColumn() ?: 0);
        } catch (Throwable) {
            $depositTotal = 0.0;
        }
    }
    $inSalonTotal = max(0.0, $totalRevenue - $depositTotal);

    // Hizmet bazlı kırılım
    $svcStmt = $pdo->prepare(
        "SELECT s.id, s.name,
                COUNT(*) AS cnt,
                COALESCE(SUM(s.price), 0) AS revenue
         FROM appointments a
         INNER JOIN services s ON s.id = a.service_id
         WHERE a.business_id = ?
           AND a.status = 'completed'
           AND a.start_at >= ?
           AND a.start_at < ?
         GROUP BY s.id, s.name
         ORDER BY revenue DESC
         LIMIT 5"
    );
    $svcStmt->execute([$businessId, $startStr, $endStr]);
    $serviceBreakdown = array_map(static fn(array $row): array => [
        'service_id' => (string)$row['id'],
        'name' => (string)$row['name'],
        'count' => (int)$row['cnt'],
        'revenue' => (float)$row['revenue'],
    ], $svcStmt->fetchAll() ?: []);

    // Son 6 ay trend
    $trend = [];
    for ($i = 5; $i >= 0; $i--) {
        $mStart = $monthStart->modify("-$i month");
        $mEnd = $mStart->modify('+1 month');
        $trendStmt = $pdo->prepare(
            "SELECT COALESCE(SUM(s.price), 0) AS rev,
                    COUNT(*) AS cnt
             FROM appointments a
             LEFT JOIN services s ON s.id = a.service_id
             WHERE a.business_id = ?
               AND a.status = 'completed'
               AND a.start_at >= ?
               AND a.start_at < ?"
        );
        $trendStmt->execute([
            $businessId,
            $mStart->format('Y-m-d H:i:s'),
            $mEnd->format('Y-m-d H:i:s'),
        ]);
        $trendRow = $trendStmt->fetch() ?: ['rev' => 0, 'cnt' => 0];
        $trend[] = [
            'month' => $mStart->format('Y-m'),
            'label' => _wbRevenueMonthLabel($mStart),
            'revenue' => (float)$trendRow['rev'],
            'count' => (int)$trendRow['cnt'],
        ];
    }

    wb_ok([
        'month' => $monthInput,
        'total_revenue' => $totalRevenue,
        'appointment_count' => $appointmentCount,
        'completed_count' => $completedCount,
        'cancelled_count' => $cancelledCount,
        'no_show_count' => $noShowCount,
        'pending_count' => $pendingCount,
        'approved_count' => $approvedCount,
        'deposit_total' => $depositTotal,
        'in_salon_total' => $inSalonTotal,
        'service_breakdown' => $serviceBreakdown,
        'monthly_trend' => $trend,
        'has_data' => $completedCount > 0 || $appointmentCount > 0,
        'empty_message' => ($completedCount === 0 && $appointmentCount === 0)
            ? 'Bu ay henüz tamamlanan randevu yok.'
            : null,
    ]);
} catch (Throwable $e) {
    error_log('[mobile/business/revenue-report.php] ' . $e->getMessage());
    wb_err('Gelir raporu alınamadı.', 500, 'internal_error');
}

function _wbRevenueMonthLabel(DateTimeImmutable $dt): string
{
    static $names = [
        1 => 'Oca', 2 => 'Şub', 3 => 'Mar', 4 => 'Nis', 5 => 'May', 6 => 'Haz',
        7 => 'Tem', 8 => 'Ağu', 9 => 'Eyl', 10 => 'Eki', 11 => 'Kas', 12 => 'Ara',
    ];
    return $names[(int)$dt->format('n')] ?? $dt->format('M');
}
