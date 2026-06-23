<?php
declare(strict_types=1);
/**
 * api/staff/hours.php
 * GET ?staffId=X — Personel çalışma saatlerini getir
 */

require_once __DIR__ . '/../admin/_bootstrap.php';
wb_method('GET');

$bid     = $user['business_id'];
if (!$bid) wb_err('İşletme bulunamadı', 404, 'business_not_found');

$staffId = (int)($_GET['staffId'] ?? 0);
if (!$staffId) wb_err('staffId zorunlu', 400, 'missing_staff_id');

try {
    $chk = $pdo->prepare('SELECT id FROM staff WHERE id = ? AND business_id = ? LIMIT 1');
    $chk->execute([$staffId, $bid]);
    if (!$chk->fetch()) wb_err('Personel bulunamadı', 403, 'forbidden');

    // Personele özel saat yoksa işletme saatlerini döndür
    $sh = $pdo->prepare('
        SELECT day, is_open, open_time, close_time FROM staff_hours
        WHERE staff_id = ? AND business_id = ?
        ORDER BY FIELD(day,"mon","tue","wed","thu","fri","sat","sun")
    ');
    $sh->execute([$staffId, $bid]);
    $hourRows = $sh->fetchAll();

    if (empty($hourRows)) {
        $bh = $pdo->prepare('
            SELECT day, is_open, open_time, close_time FROM business_hours
            WHERE business_id = ?
            ORDER BY FIELD(day,"mon","tue","wed","thu","fri","sat","sun")
        ');
        $bh->execute([$bid]);
        $hourRows = $bh->fetchAll();
    }

    $hours = [];
    foreach ($hourRows as $h) {
        $isOpen = (bool)$h['is_open'];
        $start  = ($isOpen && $h['open_time'])  ? substr($h['open_time'],  0, 5) : null;
        $end    = ($isOpen && $h['close_time']) ? substr($h['close_time'], 0, 5) : null;
        $hours[$h['day']] = [
            'open'  => $isOpen,
            'start' => $start, 'end' => $end,
            'from'  => $start, 'to'  => $end,
        ];
    }

    // Hiç tanımlı saat yoksa varsayılan hafta
    if (empty($hours)) {
        foreach (['mon','tue','wed','thu','fri','sat','sun'] as $d) {
            $isWeekend  = in_array($d, ['sat','sun'], true);
            $hours[$d]  = [
                'open'  => !$isWeekend,
                'start' => '09:00', 'end' => '18:00',
                'from'  => '09:00', 'to'  => '18:00',
            ];
        }
    }

    wb_ok(['staffId' => $staffId, 'hours' => $hours]);

} catch (Throwable $e) {
    error_log('[staff/hours] ' . $e->getMessage());
    wb_err('Saatler alınamadı', 500, 'internal_error');
}