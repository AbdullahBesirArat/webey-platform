<?php
declare(strict_types=1);
/**
 * api/staff/list.php
 * GET — Personel listesi (çalışma saatleri + servis ID'leri dahil)
 */

require_once __DIR__ . '/../admin/_bootstrap.php';
wb_method('GET');

$bid = $user['business_id'];
if (!$bid) wb_err('İşletme bulunamadı', 404, 'business_not_found');

try {
    // photo_url/photo_opt kolonları bazı ortamlarda olmayabilir.
    try {
        $stmt = $pdo->prepare('SELECT id, name, phone, color, photo_url, photo_opt FROM staff WHERE business_id = ? ORDER BY id ASC');
        $stmt->execute([$bid]);
    } catch (PDOException) {
        $stmt = $pdo->prepare('SELECT id, name, phone, color FROM staff WHERE business_id = ? ORDER BY id ASC');
        $stmt->execute([$bid]);
    }
    $rows = $stmt->fetchAll();

    $bh = $pdo->prepare('
        SELECT day, is_open, open_time, close_time FROM business_hours
        WHERE business_id = ?
        ORDER BY FIELD(day,"mon","tue","wed","thu","fri","sat","sun")
    ');
    $bh->execute([$bid]);
    $defaultHours = [];
    foreach ($bh->fetchAll() as $h) {
        $isOpen = (bool)$h['is_open'];
        $from   = ($isOpen && $h['open_time'])  ? substr($h['open_time'],  0, 5) : null;
        $to     = ($isOpen && $h['close_time']) ? substr($h['close_time'], 0, 5) : null;
        $defaultHours[$h['day']] = [
            'open'  => $isOpen,
            'start' => $from, 'end' => $to,
            'from'  => $from, 'to'  => $to,
        ];
    }

    $staffIds = array_map(static fn(array $s): int => (int)$s['id'], $rows);
    $hoursByStaff = [];
    $servicesByStaff = [];

    if (!empty($staffIds)) {
        $in = implode(',', array_fill(0, count($staffIds), '?'));

        $sh = $pdo->prepare("
            SELECT staff_id, day, is_open, open_time, close_time
            FROM staff_hours
            WHERE business_id = ? AND staff_id IN ($in)
            ORDER BY FIELD(day,'mon','tue','wed','thu','fri','sat','sun')
        ");
        $sh->execute(array_merge([$bid], $staffIds));
        foreach ($sh->fetchAll() as $h) {
            $sid = (int)$h['staff_id'];
            $isOpen = (bool)$h['is_open'];
            $from   = ($isOpen && $h['open_time'])  ? substr($h['open_time'],  0, 5) : null;
            $to     = ($isOpen && $h['close_time']) ? substr($h['close_time'], 0, 5) : null;
            $hoursByStaff[$sid][$h['day']] = [
                'open'  => $isOpen,
                'start' => $from, 'end' => $to,
                'from'  => $from, 'to'  => $to,
            ];
        }

        $ss = $pdo->prepare("SELECT staff_id, service_id FROM staff_services WHERE staff_id IN ($in)");
        $ss->execute($staffIds);
        foreach ($ss->fetchAll() as $r) {
            $sid = (int)$r['staff_id'];
            $servicesByStaff[$sid][] = (int)$r['service_id'];
        }
    }

    $fallbackSvcStmt = $pdo->prepare('SELECT id FROM services WHERE business_id = ?');
    $fallbackSvcStmt->execute([$bid]);
    $fallbackAllServiceIds = array_map('strval', $fallbackSvcStmt->fetchAll(PDO::FETCH_COLUMN));
    $hasAnyExplicitStaffService = !empty($servicesByStaff);
    $staffList = [];
    foreach ($rows as $s) {
        $sid = (int)$s['id'];
        $hoursOverride = $hoursByStaff[$sid] ?? $defaultHours;
        $serviceIds = $servicesByStaff[$sid] ?? ($hasAnyExplicitStaffService ? [] : $fallbackAllServiceIds);

        $staffList[] = [
            'id'            => (string)$sid,
            'name'          => $s['name'],
            'position'      => null,
            'phone'         => $s['phone']     ?? null,
            'color'         => $s['color']     ?? null,
            'hoursOverride' => $hoursOverride,
            'serviceIds'    => array_map('strval', $serviceIds),
            'photoUrl'      => $s['photo_url'] ?? null,
            'photoOpt'      => $s['photo_opt'] ?? null,
        ];
    }

    wb_ok(['staff' => $staffList]);

} catch (Throwable $e) {
    error_log('[staff/list] ' . $e->getMessage());
    wb_err('Personel listesi alınamadı', 500, 'internal_error');
}
