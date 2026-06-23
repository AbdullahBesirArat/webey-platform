<?php
declare(strict_types=1);
/**
 * api/staff/save-hours.php
 * POST — Personel çalışma saatlerini kaydet
 */

require_once __DIR__ . '/../admin/_bootstrap.php';
wb_method('POST');

$bid = $user['business_id'];
if (!$bid) wb_err('İşletme bulunamadı', 404, 'business_not_found');

$in      = wb_body();
$staffId = (int)($in['staffId'] ?? 0);
$hours   = is_array($in['hours'] ?? null) ? $in['hours'] : null;

if (!$staffId || $hours === null) wb_err('staffId ve hours zorunlu', 400, 'missing_params');

try {
    $chk = $pdo->prepare('SELECT id FROM staff WHERE id=? AND business_id=?');
    $chk->execute([$staffId, $bid]);
    if (!$chk->fetch()) wb_err('Personel bulunamadı', 403, 'forbidden');

    $pdo->prepare('DELETE FROM staff_hours WHERE staff_id=? AND business_id=?')
        ->execute([$staffId, $bid]);

    $ins = $pdo->prepare('INSERT INTO staff_hours (staff_id, business_id, day, is_open, open_time, close_time) VALUES (?,?,?,?,?,?)');
    foreach (['mon','tue','wed','thu','fri','sat','sun'] as $day) {
        $h      = is_array($hours[$day] ?? null) ? $hours[$day] : [];
        $isOpen = (bool)($h['open'] ?? false);
        $from   = $isOpen ? (string)($h['start'] ?? $h['from'] ?? '09:00') : null;
        $to     = $isOpen ? (string)($h['end']   ?? $h['to']   ?? '18:00') : null;
        if ($from && strlen($from) === 5) $from .= ':00';
        if ($to   && strlen($to)   === 5) $to   .= ':00';
        $ins->execute([$staffId, $bid, $day, $isOpen ? 1 : 0, $from, $to]);
    }

    wb_ok(['saved' => true, 'staffId' => $staffId]);

} catch (Throwable $e) {
    error_log('[staff/save-hours] ' . $e->getMessage());
    wb_err('Saatler kaydedilemedi', 500, 'internal_error');
}