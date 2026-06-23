<?php
declare(strict_types=1);
/**
 * api/calendar/block-time.php
 * POST { staffId, date, startTime, endTime, note }
 */

require_once __DIR__ . '/../admin/_bootstrap.php';
wb_method('POST');

$bid = $user['business_id'];
if (!$bid) wb_err('İşletme bulunamadı', 404, 'business_not_found');

$in = wb_body();
$staffId   = isset($in['staffId']) ? (int)$in['staffId'] : 0;
$date      = trim($in['date']      ?? '');
$startTime = trim($in['startTime'] ?? '');
$endTime   = trim($in['endTime']   ?? '');
$note      = trim($in['note']      ?? 'Dolu');

if (!$staffId || !$date || !$startTime || !$endTime) {
    wb_err('staffId, date, startTime, endTime zorunlu', 400, 'missing_params');
}
if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $date)) wb_err('Geçersiz tarih formatı', 400, 'invalid_date');
if (!preg_match('/^\d{2}:\d{2}$/', $startTime) || !preg_match('/^\d{2}:\d{2}$/', $endTime)) {
    wb_err('Geçersiz saat formatı (HH:MM bekleniyor)', 400, 'invalid_time');
}
if ($startTime >= $endTime) wb_err('Bitiş saati başlangıçtan sonra olmalı', 400, 'invalid_range');

function wb_time_to_minutes(string $hhmm): int {
    [$h, $m] = array_map('intval', explode(':', $hhmm));
    return ($h * 60) + $m;
}

function wb_day_key_from_date(string $date): string {
    $map = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];
    $idx = (int)(new DateTimeImmutable($date, new DateTimeZone('Europe/Istanbul')))->format('w');
    return $map[$idx] ?? 'sun';
}

function wb_extract_ranges(array $rows): array {
    $ranges = [];
    foreach ($rows as $row) {
        if ((int)($row['is_open'] ?? 0) !== 1) {
            continue;
        }
        $open  = substr((string)($row['open_time'] ?? ''), 0, 5);
        $close = substr((string)($row['close_time'] ?? ''), 0, 5);
        if (!preg_match('/^\d{2}:\d{2}$/', $open) || !preg_match('/^\d{2}:\d{2}$/', $close)) {
            continue;
        }
        $startMin = wb_time_to_minutes($open);
        $endMin   = wb_time_to_minutes($close);
        if ($endMin > $startMin) {
            $ranges[] = ['start' => $startMin, 'end' => $endMin];
        }
    }
    return $ranges;
}

try {
    $chk = $pdo->prepare('SELECT id FROM staff WHERE id = ? AND business_id = ? LIMIT 1');
    $chk->execute([$staffId, $bid]);
    if (!$chk->fetch()) wb_err('Personel bulunamadı', 403, 'forbidden');

    $tz       = new DateTimeZone('Europe/Istanbul');
    $startAt  = DateTimeImmutable::createFromFormat('Y-m-d H:i:s', "$date $startTime:00", $tz);
    $endAt    = DateTimeImmutable::createFromFormat('Y-m-d H:i:s', "$date $endTime:00", $tz);
    $now      = new DateTimeImmutable('now', $tz);
    if (!$startAt || !$endAt) {
        wb_err('Geçersiz tarih/saat seçimi', 400, 'invalid_datetime');
    }
    if ($startAt < $now) {
        wb_err('Geçmiş zaman dilimi dolu gösterilemez', 400, 'past_time');
    }

    $dayKey   = wb_day_key_from_date($date);
    $startMin = wb_time_to_minutes($startTime);
    $endMin   = wb_time_to_minutes($endTime);

    $bizHoursStmt = $pdo->prepare('SELECT is_open, open_time, close_time FROM business_hours WHERE business_id = ? AND day = ?');
    $bizHoursStmt->execute([$bid, $dayKey]);
    $bizRows = $bizHoursStmt->fetchAll();
    $bizRanges = wb_extract_ranges($bizRows);

    $staffHoursStmt = $pdo->prepare('SELECT is_open, open_time, close_time FROM staff_hours WHERE business_id = ? AND staff_id = ? AND day = ?');
    $staffHoursStmt->execute([$bid, $staffId, $dayKey]);
    $staffRows = $staffHoursStmt->fetchAll();
    $effectiveRanges = $staffRows ? wb_extract_ranges($staffRows) : $bizRanges;

    if (!$effectiveRanges) {
        wb_err('Seçilen gün ve saatte dükkan veya personel kapalı olduğu için dolu gösterilemez', 400, 'outside_working_hours');
    }

    $insideWorkingHours = false;
    foreach ($effectiveRanges as $range) {
        if ($startMin >= $range['start'] && $endMin <= $range['end']) {
            $insideWorkingHours = true;
            break;
        }
    }
    if (!$insideWorkingHours) {
        wb_err('Seçilen saat aralığı çalışma saatleri dışında olduğu için dolu gösterilemez', 400, 'outside_working_hours');
    }

    $overlapStmt = $pdo->prepare("
        SELECT id, status, customer_name
        FROM appointments
        WHERE business_id = ?
          AND staff_id = ?
          AND status NOT IN ('cancelled', 'canceled', 'rejected', 'declined', 'no_show')
          AND start_at < ?
          AND end_at   > ?
        ORDER BY start_at ASC
        LIMIT 1
    ");
    $overlapStmt->execute([$bid, $staffId, $endAt->format('Y-m-d H:i:s'), $startAt->format('Y-m-d H:i:s')]);
    $overlap = $overlapStmt->fetch();
    if ($overlap) {
        $isBlocked = (($overlap['status'] ?? '') === 'blocked') || (($overlap['customer_name'] ?? '') === '[DOLU]');
        if ($isBlocked) {
            wb_err('Bu saat aralığı zaten dolu gösterilmiş.', 409, 'blocked_conflict');
        }
        wb_err('Bu saat aralığında randevunuz var, önce randevuyu iptal etmelisiniz.', 409, 'appointment_conflict');
    }

    $pdo->prepare("
        INSERT INTO appointments (business_id, staff_id, start_at, end_at, status, customer_name, notes, booking_source, created_at)
        VALUES (?, ?, ?, ?, 'pending', '[DOLU]', ?, 'admin', NOW())
    ")->execute([$bid, $staffId, $startAt->format('Y-m-d H:i:s'), $endAt->format('Y-m-d H:i:s'), $note]);

    $newId = $pdo->lastInsertId();
    wb_ok(['id' => (string)$newId, 'startAt' => $startAt->format('Y-m-d H:i:s'), 'endAt' => $endAt->format('Y-m-d H:i:s'), 'status' => 'blocked']);

} catch (Throwable $e) {
    error_log('[calendar/block-time] ' . $e->getMessage());
    wb_err('Zaman bloke edilemedi', 500, 'internal_error');
}
