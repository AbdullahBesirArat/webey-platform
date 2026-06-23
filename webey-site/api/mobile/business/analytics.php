<?php
declare(strict_types=1);
/**
 * api/mobile/business/analytics.php
 * GET — Salonun gerçek randevu/hizmet verilerinden analitik özet.
 *
 * Query:
 *   range : 7d | 30d (varsayılan) | 90d | year
 *
 * Hesaplama özetleri:
 *   - revenue = completed randevuların services.price toplamı
 *   - appointments_count = period içinde cancelled/rejected hariç randevu sayısı
 *   - new_customers_count = period içinde ilk kez bu işletmeden randevu alan unique customer
 *   - occupancy_percent = (rezerve dakika / mevcut dakika) * 100
 *   - average_basket = revenue / completed adet
 *   - top_services = max 5 hizmet (revenue desc)
 *   - revenue_chart = period segmentlerinde günlük/haftalık revenue serisi
 *   - weekly_occupancy = Pzt..Paz doluluk oranları (son 4 hafta ortalama)
 *   - insights = gerçek koşullara dayalı öneri listesi (mock değil)
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';
require_once __DIR__ . '/_helpers.php';

wb_method('GET');

$auth = mobile_auth($pdo, ['business', 'admin']);
$ctx = mobile_business_context($pdo, $auth);
$businessId = (int)$ctx['business_id'];

$rangeIn = strtolower(trim((string)mobile_param('range', '30d')));
$allowedRanges = ['7d' => 7, '30d' => 30, '90d' => 90, 'year' => 365];
$range = isset($allowedRanges[$rangeIn]) ? $rangeIn : '30d';
$days = $allowedRanges[$range];

$tz = new DateTimeZone('Europe/Istanbul');
$now = new DateTimeImmutable('now', $tz);
$endDt = new DateTimeImmutable($now->format('Y-m-d 23:59:59'), $tz);
$startDt = $endDt->modify('-' . ($days - 1) . ' days')->modify('midnight');
$prevEndDt = $startDt->modify('-1 second');
$prevStartDt = $prevEndDt->modify('-' . ($days - 1) . ' days')->modify('midnight');

$start = $startDt->format('Y-m-d H:i:s');
$end = $endDt->format('Y-m-d H:i:s');
$prevStart = $prevStartDt->format('Y-m-d H:i:s');
$prevEnd = $prevEndDt->format('Y-m-d H:i:s');

$empty = [
    'range' => $range,
    'summary' => [
        'revenue' => 0.0,
        'revenue_change_percent' => null,
        'appointments_count' => 0,
        'appointments_change_percent' => null,
        'new_customers_count' => 0,
        'new_customers_change_percent' => null,
        'occupancy_percent' => 0.0,
        'occupancy_change_percent' => null,
        'average_basket' => 0.0,
        'average_basket_change_percent' => null,
    ],
    'revenue_chart' => [],
    'top_services' => [],
    'weekly_occupancy' => [],
    'insights' => [
        [
            'key' => 'data_warmup',
            'title' => 'Analitik için veri birikiyor',
            'description' => 'İlk randevular tamamlandıkça analiz sayfası dolar.',
        ],
    ],
];

try {
    // ── Revenue + completed count ────────────────────────────────────────────
    $revStmt = $pdo->prepare(
        "SELECT COALESCE(SUM(s.price), 0) AS revenue,
                COUNT(*) AS completed_count
           FROM appointments a
           LEFT JOIN services s ON s.id = a.service_id
          WHERE a.business_id = ?
            AND a.status = 'completed'
            AND a.start_at >= ?
            AND a.start_at <= ?"
    );
    $revStmt->execute([$businessId, $start, $end]);
    $revRow = $revStmt->fetch() ?: ['revenue' => 0, 'completed_count' => 0];
    $revenue = (float)$revRow['revenue'];
    $completedCount = (int)$revRow['completed_count'];

    $revStmt->execute([$businessId, $prevStart, $prevEnd]);
    $prevRevRow = $revStmt->fetch() ?: ['revenue' => 0, 'completed_count' => 0];
    $prevRevenue = (float)$prevRevRow['revenue'];
    $prevCompleted = (int)$prevRevRow['completed_count'];

    // ── Appointments count (cancelled/rejected hariç) ────────────────────────
    $apptSql = "SELECT COUNT(*) FROM appointments a
                WHERE a.business_id = ?
                  AND a.status NOT IN ('cancelled','rejected','declined','no_show')
                  AND a.start_at >= ?
                  AND a.start_at <= ?";
    $apptStmt = $pdo->prepare($apptSql);
    $apptStmt->execute([$businessId, $start, $end]);
    $appointmentsCount = (int)$apptStmt->fetchColumn();
    $apptStmt->execute([$businessId, $prevStart, $prevEnd]);
    $prevAppointmentsCount = (int)$apptStmt->fetchColumn();

    // ── New customers (period içinde ilk kez bu işletmeden randevu alan) ─────
    $newCustSql = "SELECT COUNT(*) FROM (
        SELECT a.customer_user_id, MIN(a.start_at) AS first_visit
          FROM appointments a
         WHERE a.business_id = ?
           AND a.customer_user_id IS NOT NULL
           AND a.status NOT IN ('cancelled','rejected','declined')
         GROUP BY a.customer_user_id
        HAVING first_visit >= ? AND first_visit <= ?
    ) t";
    $newCustStmt = $pdo->prepare($newCustSql);
    $newCustStmt->execute([$businessId, $start, $end]);
    $newCustomers = (int)$newCustStmt->fetchColumn();
    $newCustStmt->execute([$businessId, $prevStart, $prevEnd]);
    $prevNewCustomers = (int)$newCustStmt->fetchColumn();

    // ── Occupancy ───────────────────────────────────────────────────────────
    [$occupancy, $bookedMinutes, $availableMinutes] = _wb_compute_occupancy(
        $pdo, $businessId, $startDt, $endDt
    );
    [$prevOccupancy] = _wb_compute_occupancy(
        $pdo, $businessId, $prevStartDt, $prevEndDt
    );

    // ── Average basket ──────────────────────────────────────────────────────
    $avgBasket = $completedCount > 0 ? $revenue / $completedCount : 0.0;
    $prevAvgBasket = $prevCompleted > 0 ? $prevRevenue / $prevCompleted : 0.0;

    // ── Revenue chart ───────────────────────────────────────────────────────
    $revenueChart = _wb_revenue_chart($pdo, $businessId, $startDt, $endDt, $days);

    // ── Top services ────────────────────────────────────────────────────────
    $topSvcStmt = $pdo->prepare(
        "SELECT s.id, s.name,
                COUNT(*) AS cnt,
                COALESCE(SUM(s.price), 0) AS revenue
           FROM appointments a
           INNER JOIN services s ON s.id = a.service_id
          WHERE a.business_id = ?
            AND a.status = 'completed'
            AND a.start_at >= ?
            AND a.start_at <= ?
          GROUP BY s.id, s.name
          ORDER BY revenue DESC
          LIMIT 5"
    );
    $topSvcStmt->execute([$businessId, $start, $end]);
    $topServices = [];
    foreach ($topSvcStmt->fetchAll() ?: [] as $row) {
        $svcRev = (float)$row['revenue'];
        $topServices[] = [
            'id' => (int)$row['id'],
            'name' => (string)$row['name'],
            'appointments_count' => (int)$row['cnt'],
            'revenue' => $svcRev,
            'share_percent' => $revenue > 0 ? round(($svcRev / $revenue) * 100, 1) : 0.0,
        ];
    }

    // ── Weekly occupancy (Pzt..Paz, son N haftanın haftalık ortalaması) ─────
    $weeklyOccupancy = _wb_weekly_occupancy($pdo, $businessId, $startDt, $endDt);

    // ── Insights ─────────────────────────────────────────────────────────────
    $insights = _wb_insights(
        $appointmentsCount,
        $newCustomers,
        $occupancy,
        $weeklyOccupancy,
        $topServices
    );

    wb_ok([
        'range' => $range,
        'summary' => [
            'revenue' => $revenue,
            'revenue_change_percent' => _wb_pct_change($prevRevenue, $revenue),
            'appointments_count' => $appointmentsCount,
            'appointments_change_percent' => _wb_pct_change((float)$prevAppointmentsCount, (float)$appointmentsCount),
            'new_customers_count' => $newCustomers,
            'new_customers_change_percent' => _wb_pct_change((float)$prevNewCustomers, (float)$newCustomers),
            'occupancy_percent' => $occupancy,
            'occupancy_change_percent' => _wb_pct_change($prevOccupancy, $occupancy),
            'average_basket' => $avgBasket,
            'average_basket_change_percent' => _wb_pct_change($prevAvgBasket, $avgBasket),
        ],
        'revenue_chart' => $revenueChart,
        'top_services' => $topServices,
        'weekly_occupancy' => $weeklyOccupancy,
        'insights' => $insights,
    ]);
} catch (Throwable $e) {
    error_log('[mobile/business/analytics.php] ' . $e->getMessage());
    // Hata durumunda mock değil, güvenli empty döner.
    wb_ok($empty);
}

function _wb_pct_change(float $previous, float $current): ?float
{
    if ($previous <= 0) {
        return null;
    }
    return round((($current - $previous) / $previous) * 100, 1);
}

/**
 * Doluluk = rezerve dakika / mevcut dakika.
 * Mevcut dakika: business_hours toplamı × aktif staff sayısı × period gün katsayısı.
 *
 * @return array{0:float,1:int,2:int} [occupancyPercent, bookedMinutes, availableMinutes]
 */
function _wb_compute_occupancy(
    PDO $pdo,
    int $businessId,
    DateTimeImmutable $startDt,
    DateTimeImmutable $endDt
): array {
    $start = $startDt->format('Y-m-d H:i:s');
    $end = $endDt->format('Y-m-d H:i:s');

    // Booked minutes (cancelled hariç).
    $bookedStmt = $pdo->prepare(
        "SELECT COALESCE(SUM(
                  CASE WHEN s.duration_min IS NOT NULL AND s.duration_min > 0
                       THEN s.duration_min
                       WHEN a.end_at IS NOT NULL AND a.start_at IS NOT NULL
                       THEN TIMESTAMPDIFF(MINUTE, a.start_at, a.end_at)
                       ELSE 30 END
                ), 0) AS booked
           FROM appointments a
           LEFT JOIN services s ON s.id = a.service_id
          WHERE a.business_id = ?
            AND a.status NOT IN ('cancelled','rejected','declined')
            AND a.start_at >= ?
            AND a.start_at <= ?"
    );
    $bookedStmt->execute([$businessId, $start, $end]);
    $bookedMinutes = (int)$bookedStmt->fetchColumn();

    // Aktif staff sayısı (en az 1).
    $staffStmt = $pdo->prepare(
        "SELECT COUNT(*) FROM staff
          WHERE business_id = ? AND COALESCE(is_active, 1) = 1"
    );
    $staffStmt->execute([$businessId]);
    $staffCount = max(1, (int)$staffStmt->fetchColumn());

    // Haftalık çalışma dakikası — business_hours tablosundan (yoksa 0).
    $weeklyMinutes = 0;
    try {
        $hoursStmt = $pdo->prepare(
            "SELECT COALESCE(SUM(
                       CASE WHEN open_time IS NOT NULL AND close_time IS NOT NULL
                            AND COALESCE(is_closed, 0) = 0
                            THEN TIMESTAMPDIFF(MINUTE, open_time, close_time)
                            ELSE 0 END
                    ), 0) AS mins
               FROM business_hours
              WHERE business_id = ?"
        );
        $hoursStmt->execute([$businessId]);
        $weeklyMinutes = (int)$hoursStmt->fetchColumn();
    } catch (Throwable) {
        $weeklyMinutes = 0;
    }

    if ($weeklyMinutes <= 0) {
        return [0.0, $bookedMinutes, 0];
    }

    $periodDays = max(1, (int)round(($endDt->getTimestamp() - $startDt->getTimestamp()) / 86400) + 1);
    $availableMinutes = (int)round(($weeklyMinutes / 7) * $periodDays * $staffCount);
    if ($availableMinutes <= 0) {
        return [0.0, $bookedMinutes, 0];
    }
    $pct = min(100.0, round(($bookedMinutes / $availableMinutes) * 100, 1));
    return [$pct, $bookedMinutes, $availableMinutes];
}

function _wb_revenue_chart(
    PDO $pdo,
    int $businessId,
    DateTimeImmutable $startDt,
    DateTimeImmutable $endDt,
    int $days
): array {
    // 7-30 gün: günlük; 90 gün: haftalık; year: aylık.
    $mode = $days <= 30 ? 'daily' : ($days <= 90 ? 'weekly' : 'monthly');

    if ($mode === 'daily') {
        $sql = "SELECT DATE(a.start_at) AS bucket,
                       COALESCE(SUM(s.price), 0) AS revenue
                  FROM appointments a
                  LEFT JOIN services s ON s.id = a.service_id
                 WHERE a.business_id = ?
                   AND a.status = 'completed'
                   AND a.start_at >= ?
                   AND a.start_at <= ?
                 GROUP BY DATE(a.start_at)
                 ORDER BY bucket ASC";
    } elseif ($mode === 'weekly') {
        $sql = "SELECT YEARWEEK(a.start_at, 1) AS bucket,
                       MIN(DATE(a.start_at)) AS bucket_label,
                       COALESCE(SUM(s.price), 0) AS revenue
                  FROM appointments a
                  LEFT JOIN services s ON s.id = a.service_id
                 WHERE a.business_id = ?
                   AND a.status = 'completed'
                   AND a.start_at >= ?
                   AND a.start_at <= ?
                 GROUP BY YEARWEEK(a.start_at, 1)
                 ORDER BY bucket ASC";
    } else {
        $sql = "SELECT DATE_FORMAT(a.start_at, '%Y-%m') AS bucket,
                       COALESCE(SUM(s.price), 0) AS revenue
                  FROM appointments a
                  LEFT JOIN services s ON s.id = a.service_id
                 WHERE a.business_id = ?
                   AND a.status = 'completed'
                   AND a.start_at >= ?
                   AND a.start_at <= ?
                 GROUP BY DATE_FORMAT(a.start_at, '%Y-%m')
                 ORDER BY bucket ASC";
    }

    $stmt = $pdo->prepare($sql);
    $stmt->execute([$businessId, $startDt->format('Y-m-d H:i:s'), $endDt->format('Y-m-d H:i:s')]);
    $chart = [];
    foreach ($stmt->fetchAll() ?: [] as $row) {
        $chart[] = [
            'bucket' => (string)($row['bucket_label'] ?? $row['bucket']),
            'revenue' => (float)$row['revenue'],
        ];
    }
    return $chart;
}

/**
 * Haftanın günlerine göre doluluk yüzdesi (period içindeki tüm haftaların ortalaması).
 *
 * @return array<int,array{day:string,occupancy_percent:float}>
 */
function _wb_weekly_occupancy(
    PDO $pdo,
    int $businessId,
    DateTimeImmutable $startDt,
    DateTimeImmutable $endDt
): array {
    // MySQL DAYOFWEEK: 1=Sun..7=Sat. ISO mapping: 1=Mon..7=Sun.
    $stmt = $pdo->prepare(
        "SELECT DAYOFWEEK(a.start_at) AS dow,
                COALESCE(SUM(
                  CASE WHEN s.duration_min IS NOT NULL AND s.duration_min > 0
                       THEN s.duration_min
                       WHEN a.end_at IS NOT NULL AND a.start_at IS NOT NULL
                       THEN TIMESTAMPDIFF(MINUTE, a.start_at, a.end_at)
                       ELSE 30 END
                ), 0) AS booked
           FROM appointments a
           LEFT JOIN services s ON s.id = a.service_id
          WHERE a.business_id = ?
            AND a.status NOT IN ('cancelled','rejected','declined')
            AND a.start_at >= ?
            AND a.start_at <= ?
          GROUP BY DAYOFWEEK(a.start_at)"
    );
    $stmt->execute([$businessId, $startDt->format('Y-m-d H:i:s'), $endDt->format('Y-m-d H:i:s')]);
    $bookedByDow = [];
    foreach ($stmt->fetchAll() ?: [] as $row) {
        $bookedByDow[(int)$row['dow']] = (int)$row['booked'];
    }

    // business_hours weekday alanı 0=Pzt veya 1=Pzt olabilir; iki şemayı da destekle.
    $hoursByDow = [];
    $weekdayCol = 'weekday';
    try {
        $hStmt = $pdo->prepare(
            "SELECT weekday, open_time, close_time, COALESCE(is_closed,0) AS closed
               FROM business_hours WHERE business_id = ?"
        );
        $hStmt->execute([$businessId]);
        $rows = $hStmt->fetchAll() ?: [];
        foreach ($rows as $r) {
            if ((int)$r['closed'] === 1 || $r['open_time'] === null || $r['close_time'] === null) continue;
            $wd = (int)$r['weekday'];
            $mins = (strtotime((string)$r['close_time']) - strtotime((string)$r['open_time'])) / 60;
            if ($mins <= 0) continue;
            $hoursByDow[$wd] = (int)$mins;
        }
        $weekdayCol = 'weekday';
    } catch (Throwable) {
        $hoursByDow = [];
    }

    $staffCount = 1;
    try {
        $st = $pdo->prepare("SELECT COUNT(*) FROM staff WHERE business_id = ? AND COALESCE(is_active,1)=1");
        $st->execute([$businessId]);
        $staffCount = max(1, (int)$st->fetchColumn());
    } catch (Throwable) {
        $staffCount = 1;
    }

    // Period içindeki haftaların gün-sayım (1=Mon..7=Sun).
    $periodDayCounts = [1=>0,2=>0,3=>0,4=>0,5=>0,6=>0,7=>0];
    $cur = $startDt;
    while ($cur <= $endDt) {
        $iso = (int)$cur->format('N'); // 1=Mon..7=Sun
        $periodDayCounts[$iso]++;
        $cur = $cur->modify('+1 day');
    }

    // Çıktı sırası Pzt..Paz.
    $labels = [1=>'Pzt',2=>'Sal',3=>'Çar',4=>'Per',5=>'Cum',6=>'Cmt',7=>'Paz'];
    $isoToMysqlDow = [1=>2,2=>3,3=>4,4=>5,5=>6,6=>7,7=>1];

    $result = [];
    foreach ([1,2,3,4,5,6,7] as $iso) {
        $mysqlDow = $isoToMysqlDow[$iso];
        $booked = $bookedByDow[$mysqlDow] ?? 0;
        // business_hours 0=Pzt veya 1=Pzt olabilir; iki olası index ile dene.
        $hours0 = $hoursByDow[$iso - 1] ?? null; // 0=Mon..6=Sun
        $hours1 = $hoursByDow[$iso] ?? null;     // 1=Mon..7=Sun
        $dailyMinutes = $hours1 ?? $hours0 ?? 0;
        $count = $periodDayCounts[$iso];
        $available = $dailyMinutes * $count * $staffCount;
        $pct = $available > 0 ? round(min(100.0, ($booked / $available) * 100), 1) : 0.0;
        $result[] = [
            'day' => $labels[$iso],
            'occupancy_percent' => $pct,
        ];
    }
    return $result;
}

/**
 * Gerçek koşullara dayalı insights. Mock metin döndürmez.
 */
function _wb_insights(
    int $appointmentsCount,
    int $newCustomers,
    float $occupancyPercent,
    array $weeklyOccupancy,
    array $topServices
): array {
    $insights = [];
    if ($appointmentsCount === 0) {
        $insights[] = [
            'key' => 'no_data',
            'title' => 'Analitik için veri birikiyor',
            'description' => 'Bu dönemde randevu yok. İlk randevular tamamlandıkça öneriler burada görünür.',
        ];
        return $insights;
    }

    if (!empty($weeklyOccupancy)) {
        $maxDay = null;
        $maxPct = 0.0;
        foreach ($weeklyOccupancy as $day) {
            if ($day['occupancy_percent'] > $maxPct) {
                $maxPct = (float)$day['occupancy_percent'];
                $maxDay = (string)$day['day'];
            }
        }
        if ($maxDay !== null && $maxPct >= 60.0) {
            $insights[] = [
                'key' => 'peak_day',
                'title' => $maxDay . ' günleri talep yüksek',
                'description' => $maxDay . ' günü doluluk %' . (int)$maxPct
                    . '. Bu gün için ek personel ve fiyatlama planı düşünülebilir.',
            ];
        }
    }

    if ($occupancyPercent > 0 && $occupancyPercent < 40.0) {
        $insights[] = [
            'key' => 'low_occupancy',
            'title' => 'Doluluğu artırma fırsatı',
            'description' => 'Genel doluluk %' . (int)$occupancyPercent
                . '. Boost paketleri veya kısa süreli teklifler değerlendirilebilir.',
        ];
    }

    if (!empty($topServices)) {
        $top = $topServices[0];
        $insights[] = [
            'key' => 'top_service',
            'title' => $top['name'] . ' öne çıkıyor',
            'description' => 'Bu dönem en çok gelir getiren hizmet: ' . $top['name']
                . ' (₺' . number_format((float)$top['revenue'], 0, ',', '.') . ').',
        ];
    }

    if ($newCustomers > 0) {
        $insights[] = [
            'key' => 'new_customers',
            'title' => $newCustomers . ' yeni müşteri kazanıldı',
            'description' => 'Bu dönemde ' . $newCustomers . ' müşteri ilk kez randevu aldı.',
        ];
    }

    if (empty($insights)) {
        $insights[] = [
            'key' => 'steady',
            'title' => 'Dönem dengeli ilerliyor',
            'description' => 'Belirgin bir uç değer yok. Mevcut tempoyu sürdürmek için yeterli.',
        ];
    }

    return $insights;
}
