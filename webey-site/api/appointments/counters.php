<?php
declare(strict_types=1);
// PUBLIC — oturum gerektirmez
require_once __DIR__ . '/../_public_bootstrap.php';

wb_method('GET');

$businessId = (int)($_GET['businessId'] ?? 0);
$date       = trim($_GET['date'] ?? '');

if (!$businessId || !$date || !preg_match('/^\d{4}-\d{2}-\d{2}$/', $date)) {
    wb_err('businessId ve date zorunlu', 400, 'missing_param');
}

try {
    $stmt = $pdo->prepare("
        SELECT start_at, end_at FROM appointments
        WHERE business_id = ? AND DATE(start_at) = ?
          AND status NOT IN ('cancelled','no_show','rejected','declined')
    ");
    $stmt->execute([$businessId, $date]);

    $counters = [];
    foreach ($stmt->fetchAll() as $r) {
        $start = new DateTime($r['start_at']);
        $end   = new DateTime($r['end_at']);
        $cur   = clone $start;
        while ($cur < $end) {
            $h    = (int)$cur->format('G');
            $m    = (int)$cur->format('i');
            $slot = (string)(floor($m / 15) * 15);
            if (!isset($counters[$h])) $counters[$h] = ['0' => 0, '15' => 0, '30' => 0, '45' => 0];
            $counters[$h][$slot]++;
            $cur->modify('+15 minutes');
        }
    }

    wb_ok(['counters' => $counters]);

} catch (Throwable $e) {
    error_log('[appointments/counters.php] ' . $e->getMessage());
    wb_err('Sunucu hatası.', 500, 'internal_error');
}