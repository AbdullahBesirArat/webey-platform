<?php
declare(strict_types=1);
/**
 * api/mobile/business/appointment-create.php
 * POST - Token sahibi isletme manuel olarak randevu olusturur.
 *
 * Body (JSON):
 *   customer_name      : string  (zorunlu)
 *   customer_phone     : string  (opsiyonel)
 *   service_id         : int     (zorunlu)
 *   staff_id           : int     (opsiyonel)
 *   appointment_date   : string  (zorunlu) YYYY-MM-DD
 *   appointment_time   : string  (zorunlu) HH:mm
 *   notes              : string  (opsiyonel)
 *
 * Manuel olusturuldugu icin status default 'approved'.
 * Depozito zorunlu degil; payment akisi calismaz.
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';
require_once __DIR__ . '/_helpers.php';
require_once __DIR__ . '/../booking/_helpers.php';
require_once __DIR__ . '/../../_appointment_log.php';

wb_method('POST');

$auth = mobile_auth($pdo, ['business', 'admin']);
$ctx = mobile_business_context($pdo, $auth);
$businessId = (int)$ctx['business_id'];
$actorUserId = (int)$ctx['user_id'];

$body = wb_body();

$customerName  = trim((string)($body['customer_name'] ?? ''));
$customerPhone = trim((string)($body['customer_phone'] ?? ''));
$serviceId     = (int)($body['service_id'] ?? 0);
$staffIdRaw    = isset($body['staff_id'])
    ? (int)$body['staff_id']
    : (isset($body['specialist_id']) ? (int)$body['specialist_id'] : 0);
$staffId       = $staffIdRaw > 0 ? $staffIdRaw : null;
$startsAtRaw   = trim((string)($body['starts_at'] ?? ''));
$dateStr       = trim((string)($body['appointment_date'] ?? ''));
$timeStr       = trim((string)($body['appointment_time'] ?? ''));
$notes         = mb_substr(trim((string)($body['notes'] ?? '')), 0, 2000);

// ── Validasyon ───────────────────────────────────────────────────────────────
if ($customerName === '') {
    wb_err('Musteri adi zorunlu', 422, 'missing_customer_name');
}
if (mb_strlen($customerName) > 200) {
    $customerName = mb_substr($customerName, 0, 200);
}

if ($serviceId < 1) {
    wb_err('service_id zorunlu', 422, 'missing_service_id');
}

if ($startsAtRaw !== '') {
    $startsAtClean = str_replace('T', ' ', $startsAtRaw);
    if (preg_match('/^(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2})(?::\d{2})?$/', $startsAtClean, $m)) {
        $dateStr = $m[1];
        $timeStr = $m[2];
    }
}

if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $dateStr)) {
    wb_err('appointment_date YYYY-MM-DD formatinda olmali', 422, 'invalid_date');
}
if (!preg_match('/^\d{2}:\d{2}$/', $timeStr)) {
    wb_err('appointment_time HH:mm formatinda olmali', 422, 'invalid_time');
}
$minute = (int)substr($timeStr, 3, 2);
if (!in_array($minute, [0, 15, 30, 45], true)) {
    wb_err('Randevu dakikasi 00, 15, 30 veya 45 olmali', 422, 'invalid_time_minute');
}

$parsed = wb_bk_validate_datetime($dateStr . ' ' . $timeStr);
if ($parsed === null) {
    wb_err('Tarih veya saat gecersiz', 422, 'invalid_datetime');
}

$dayStr   = $parsed['day_str'];
$startMin = $parsed['start_min'];
$startsAt = $parsed['str'];

if ($customerPhone !== '') {
    $normalizedPhone = preg_replace('/\D+/', '', $customerPhone);
    if ($normalizedPhone === '') {
        $customerPhone = '';
    } else {
        if (strlen($normalizedPhone) === 12 && str_starts_with($normalizedPhone, '90')) {
            $normalizedPhone = substr($normalizedPhone, 2);
        } elseif (strlen($normalizedPhone) === 11 && str_starts_with($normalizedPhone, '0')) {
            $normalizedPhone = substr($normalizedPhone, 1);
        }
        if (strlen($normalizedPhone) < 10) {
            wb_err('Telefon en az 10 hane olmali', 422, 'invalid_phone');
        }
        $customerPhone = $normalizedPhone;
    }
}

// ── Hizmet dogrulama (business sahipligi; is_active kolonu varsa aktif) ──────
$svcHasActive = mobile_business_has_column($pdo, 'services', 'is_active');
$svcSelectCols = 'id, name, duration_min, price'
    . ($svcHasActive ? ', is_active' : '');
$svcStmt = $pdo->prepare(
    "SELECT {$svcSelectCols} FROM services WHERE id = ? AND business_id = ? LIMIT 1"
);
$svcStmt->execute([$serviceId, $businessId]);
$svcRow = $svcStmt->fetch();
if (!$svcRow) {
    wb_err('Hizmet bulunamadi', 404, 'service_not_found');
}
if ($svcHasActive && !((int)($svcRow['is_active'] ?? 1))) {
    wb_err('Hizmet aktif degil', 422, 'service_inactive');
}
$serviceName = (string)$svcRow['name'];

$durationMin = (int)($svcRow['duration_min'] ?? 0);
if ($durationMin < 1) {
    wb_err('Hizmet suresi gecersiz', 422, 'invalid_duration');
}

$endMin = $startMin + $durationMin;
if ($endMin > 1440) {
    wb_err('Randevu gece yarisini gecemez', 422, 'midnight_overflow');
}
$endsAt = sprintf('%s %02d:%02d:00', $dayStr, intdiv($endMin, 60), $endMin % 60);

// ── Personel dogrulama (opsiyonel) ──────────────────────────────────────────
if ($staffId !== null) {
    $stfStmt = $pdo->prepare(
        'SELECT id FROM staff WHERE id = ? AND business_id = ? AND is_active = 1 LIMIT 1'
    );
    $stfStmt->execute([$staffId, $businessId]);
    if (!$stfStmt->fetch()) {
        wb_err('Personel bulunamadi', 404, 'staff_not_found');
    }
}

// ── Insert (cakisma kontrolu ile transaction) ────────────────────────────────
$appointmentId = null;

try {
    $pdo->beginTransaction();

    if ($staffId !== null) {
        $conflictSql = "SELECT id FROM appointments
                        WHERE business_id = ? AND staff_id = ?
                          AND status NOT IN ('cancelled','no_show','rejected','declined','cancellation_requested')
                          AND start_at < ? AND end_at > ?
                        FOR UPDATE";
        $conflictParams = [$businessId, $staffId, $endsAt, $startsAt];
    } else {
        $conflictSql = "SELECT id FROM appointments
                        WHERE business_id = ?
                          AND status NOT IN ('cancelled','no_show','rejected','declined','cancellation_requested')
                          AND start_at < ? AND end_at > ?
                        FOR UPDATE";
        $conflictParams = [$businessId, $endsAt, $startsAt];
    }

    $conflictStmt = $pdo->prepare($conflictSql);
    $conflictStmt->execute($conflictParams);
    if ($conflictStmt->fetch()) {
        $pdo->rollBack();
        wb_err('Bu saatte cakisan bir randevu var', 409, 'conflict');
    }

    // Insert: kullanici girdisi yok, kolon listesi sabit
    $insertSql = "INSERT INTO appointments
        (business_id, staff_id, service_id, customer_user_id, customer_name,
         customer_phone, customer_email, start_at, end_at, status, booking_source, notes,
         created_at, updated_at)
        VALUES (?, ?, ?, NULL, ?, ?, NULL, ?, ?, 'approved', 'app', ?, NOW(), NOW())";

    $pdo->prepare($insertSql)->execute([
        $businessId,
        $staffId,
        $serviceId,
        $customerName,
        $customerPhone !== '' ? $customerPhone : null,
        $startsAt,
        $endsAt,
        $notes !== '' ? $notes : null,
    ]);

    $appointmentId = (int)$pdo->lastInsertId();

    $pdo->commit();
} catch (Throwable $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    error_log('[mobile/business/appointment-create.php] ' . $e->getMessage());
    wb_err('Randevu olusturulamadi', 500, 'internal_error');
}

try {
    wb_appt_log($pdo, $appointmentId, 'created', null, 'approved', $actorUserId);
} catch (Throwable $logEx) {
    error_log('[mobile/business/appointment-create.php audit_log] ' . $logEx->getMessage());
}

// ── Yeni satiri tek SELECT ile cek + listedeki format ile don ───────────────
try {
    $rowStmt = $pdo->prepare(
        mobile_business_appointment_select_sql() . ' WHERE a.id = ? AND a.business_id = ? LIMIT 1'
    );
    $rowStmt->execute([$appointmentId, $businessId]);
    $row = $rowStmt->fetch();
    if ($row) {
        $item = mobile_business_appointment_item($row);
        $item['deposit'] = ['required' => false, 'amount' => null, 'status' => null, 'paid_at' => null];
        wb_ok(['appointment' => $item]);
    }
} catch (Throwable $e) {
    error_log('[mobile/business/appointment-create.php select] ' . $e->getMessage());
}

// Fallback minimal payload (select fail durumunda)
wb_ok([
    'appointment' => [
        'id'              => (string)$appointmentId,
        'status'          => 'approved',
        'starts_at'       => $startsAt,
        'ends_at'         => $endsAt,
        'date'            => $dayStr,
        'time'            => substr($startsAt, 11, 5),
        'customer_name'   => $customerName,
        'customer_phone'  => $customerPhone !== '' ? $customerPhone : null,
        'service_name'    => $serviceName,
        'staff_name'      => null,
        'price'           => $svcRow['price'] !== null ? (float)$svcRow['price'] : null,
        'duration_minutes'=> $durationMin,
        'note'            => $notes !== '' ? $notes : null,
        'deposit'         => ['required' => false, 'amount' => null, 'status' => null, 'paid_at' => null],
    ],
]);
