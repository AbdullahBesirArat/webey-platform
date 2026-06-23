<?php
declare(strict_types=1);
/**
 * api/mobile/booking/availability.php
 * GET — işletme/hizmet/tarih için müsait slot listesi.
 *
 * Params:
 *   business_id      : int         (zorunlu)
 *   service_id       : int         (zorunlu)
 *   date             : YYYY-MM-DD  (zorunlu)
 *   staff_id         : int         (opsiyonel)
 *   duration_minutes : int         (opsiyonel — yoksa services tablosundan)
 *
 * Faz 5A — Auth gerekmez (public endpoint).
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/_helpers.php';

wb_method('GET');

// ── Parametreler ──────────────────────────────────────────────────────────────
$businessId  = mobile_int_param('business_id');
$serviceId   = mobile_int_param('service_id');
$date        = trim((string)mobile_param('date', ''));
$staffId     = mobile_int_param('staff_id');

if (!$businessId || $businessId < 1) {
    wb_err('business_id zorunludur', 422, 'missing_business_id');
}
if (!$serviceId || $serviceId < 1) {
    wb_err('service_id zorunludur', 422, 'missing_service_id');
}
if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $date)) {
    wb_err('date geçersiz (YYYY-MM-DD bekleniyor)', 422, 'invalid_date');
}

$tz    = new DateTimeZone('Europe/Istanbul');
$today = (new DateTimeImmutable('now', $tz))->format('Y-m-d');
if ($date < $today) {
    wb_err('Geçmiş tarih için uygunluk sorgulanamaz', 422, 'date_in_past');
}

// ── Hizmet süresi ─────────────────────────────────────────────────────────────
$durationMin = mobile_int_param('duration_minutes');

if (!$durationMin || $durationMin < 1) {
    $svcStmt = $pdo->prepare(
        'SELECT duration_min FROM services WHERE id = ? AND business_id = ? LIMIT 1'
    );
    $svcStmt->execute([$serviceId, $businessId]);
    $svcRow = $svcStmt->fetch();
    if (!$svcRow) {
        wb_err('Hizmet bulunamadı', 404, 'service_not_found');
    }
    $durationMin = (int)$svcRow['duration_min'];
}

if ($durationMin < 1) {
    wb_err('Hizmet süresi geçersiz', 422, 'invalid_duration');
}

// ── Personel doğrulama (opsiyonel) ───────────────────────────────────────────
if ($staffId !== null) {
    $stfStmt = $pdo->prepare(
        'SELECT id FROM staff WHERE id = ? AND business_id = ? AND is_active = 1 LIMIT 1'
    );
    $stfStmt->execute([$staffId, $businessId]);
    if (!$stfStmt->fetch()) {
        wb_err('Personel bulunamadı', 404, 'staff_not_found');
    }
}

// ── Çalışma saatleri, randevular, kilitler ────────────────────────────────────
$workingRanges = wb_bk_get_working_ranges($pdo, $businessId, $staffId, $date);

if (!$workingRanges) {
    wb_ok([
        'date'             => $date,
        'business_id'      => $businessId,
        'service_id'       => $serviceId,
        'staff_id'         => $staffId,
        'duration_minutes' => $durationMin,
        'items'            => [],
    ]);
}

$bookedRanges = wb_bk_get_booked_ranges($pdo, $businessId, $staffId, $date);
$lockRanges   = wb_bk_get_lock_ranges($pdo, $businessId, $staffId, $date);

// ── Slot üretimi (15 dk aralıkları) ───────────────────────────────────────────
$nowIst  = new DateTimeImmutable('now', $tz);
$isToday = ($date === $today);
$nowMin  = $isToday ? ((int)$nowIst->format('G') * 60 + (int)$nowIst->format('i')) : 0;

$items = [];

foreach ($workingRanges as $range) {
    $slotStart = $range['start'];
    while ($slotStart + $durationMin <= $range['end']) {
        $slotEnd = $slotStart + $durationMin;

        if ($isToday && $slotStart <= $nowMin) {
            $slotStart += 15;
            continue;
        }

        $available = !wb_bk_ranges_overlap($bookedRanges, $slotStart, $slotEnd)
                  && !wb_bk_ranges_overlap($lockRanges, $slotStart, $slotEnd);

        $h  = intdiv($slotStart, 60);
        $m  = $slotStart % 60;
        $eh = intdiv($slotEnd, 60);
        $em = $slotEnd % 60;

        $items[] = [
            'time'      => sprintf('%02d:%02d', $h, $m),
            'starts_at' => sprintf('%s %02d:%02d:00', $date, $h, $m),
            'ends_at'   => sprintf('%s %02d:%02d:00', $date, $eh, $em),
            'available' => $available,
        ];

        $slotStart += 15;
    }
}

wb_ok([
    'date'             => $date,
    'business_id'      => $businessId,
    'service_id'       => $serviceId,
    'staff_id'         => $staffId,
    'duration_minutes' => $durationMin,
    'items'            => $items,
]);
