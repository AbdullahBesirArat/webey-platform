<?php
declare(strict_types=1);
/**
 * api/appointments/booked-map.php
 * GET ?businessId=&date=YYYY-MM-DD&staffId=&lockToken=
 * PUBLIC — dolu slot haritasını döndürür
 */

require_once __DIR__ . '/../_public_bootstrap.php';
wb_method('GET');

$businessId = (int)($_GET['businessId'] ?? 0);
$date       = trim($_GET['date'] ?? '');
$staffId    = trim($_GET['staffId'] ?? '');
$ownToken   = trim($_GET['lockToken'] ?? '');

if (!$businessId || !$date || !preg_match('/^\d{4}-\d{2}-\d{2}$/', $date)) {
    wb_err('businessId ve date zorunlu', 400, 'missing_param');
}

try {
    $sql    = "SELECT start_at, end_at FROM appointments
               WHERE business_id = ? AND DATE(start_at) = ?
                 AND status NOT IN ('cancelled','no_show','rejected','declined')";
    $params = [$businessId, $date];

    if ($staffId && $staffId !== 'any') {
        $sql    .= ' AND staff_id = ?';
        $params[] = (int)$staffId;
    }

    $rows = $pdo->prepare($sql);
    $rows->execute($params);
    $rows = $rows->fetchAll();

    $map = [];
    $fillMap = function(int $s, int $e) use (&$map): void {
        $cur = $s;
        while ($cur < $e) {
            $h    = (int)floor($cur / 60);
            $m    = $cur % 60;
            $slot = (int)(floor($m / 15) * 15);
            if (!isset($map[$h])) $map[$h] = [];
            if (!in_array($slot, $map[$h], true)) $map[$h][] = $slot;
            $cur += 15;
        }
    };

    foreach ($rows as $r) {
        $start    = new DateTime($r['start_at']);
        $end      = new DateTime($r['end_at']);
        $startMin = (int)$start->format('G') * 60 + (int)$start->format('i');
        $endMin   = (int)$end->format('G')   * 60 + (int)$end->format('i');
        $fillMap($startMin, $endMin);
    }

    try {
        $lockSql    = "SELECT start_min, duration_min FROM slot_locks
                       WHERE business_id = ? AND day_str = ? AND expires_at >= NOW()";
        $lockParams = [$businessId, $date];
        if ($staffId && $staffId !== 'any') {
            // Sadece aynı personelin kilitleri
            $lockSql    .= ' AND staff_id = ?';
            $lockParams[] = (int)$staffId;
        }
        if ($ownToken !== '') { $lockSql .= ' AND lock_token != ?'; $lockParams[] = $ownToken; }

        $lockStmt = $pdo->prepare($lockSql);
        $lockStmt->execute($lockParams);
        foreach ($lockStmt->fetchAll() as $lk) {
            $fillMap((int)$lk['start_min'], (int)$lk['start_min'] + (int)$lk['duration_min']);
        }
    } catch (Throwable) {}

    wb_ok(['map' => $map, 'date' => $date, 'booked' => $map]);

} catch (Throwable $e) {
    error_log('[appointments/booked-map.php] ' . $e->getMessage());
    wb_err('Sunucu hatası.', 500, 'internal_error');
}