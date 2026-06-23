<?php
declare(strict_types=1);
/**
 * api/mobile/booking/lock.php
 * POST — slot kilit rezervasyonu (TTL: 5 dakika).
 *
 * Body (JSON):
 *   business_id      : int    (zorunlu)
 *   service_id       : int    (zorunlu)
 *   starts_at        : string (zorunlu) — "YYYY-MM-DD HH:MM" veya "YYYY-MM-DDTHH:MM:SS"
 *   staff_id         : int    (opsiyonel)
 *   duration_minutes : int    (opsiyonel — yoksa services tablosundan)
 *
 * Faz 5A — Bearer token zorunlu, customer tipi.
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';
require_once __DIR__ . '/_helpers.php';
require_once __DIR__ . '/../_campaigns.php';

wb_method('POST');

const MB_LOCK_TTL_SEC = 300; // 5 dakika

mobile_auth($pdo, 'customer');

$in = wb_body();

$businessId  = (int)($in['business_id'] ?? 0);
$serviceId   = (int)($in['service_id']  ?? 0);
$startsAtRaw = trim((string)($in['starts_at'] ?? ''));
$staffIdRaw  = isset($in['staff_id']) ? (int)$in['staff_id'] : null;
$staffId     = ($staffIdRaw !== null && $staffIdRaw > 0) ? $staffIdRaw : null;
$durationMin = isset($in['duration_minutes']) ? (int)$in['duration_minutes'] : null;

// ── Temel doğrulama ───────────────────────────────────────────────────────────
if ($businessId < 1) {
    wb_err('business_id zorunludur', 422, 'missing_business_id');
}
if ($serviceId < 1) {
    wb_err('service_id zorunludur', 422, 'missing_service_id');
}
if ($startsAtRaw === '') {
    wb_err('starts_at zorunludur', 422, 'missing_starts_at');
}

$parsed = wb_bk_validate_datetime($startsAtRaw);
if ($parsed === null) {
    wb_err('starts_at geçersiz format (YYYY-MM-DD HH:MM bekleniyor)', 422, 'invalid_starts_at');
}

$dayStr   = $parsed['day_str'];
$startMin = $parsed['start_min'];

$tz = new DateTimeZone('Europe/Istanbul');
if ($parsed['dt'] <= new DateTimeImmutable('now', $tz)) {
    wb_err('Geçmiş bir saate kilit alınamaz', 422, 'past_slot');
}

// ── İşletme doğrulama ─────────────────────────────────────────────────────────
$bizStmt = $pdo->prepare('SELECT id FROM businesses WHERE id = ? AND status = ? LIMIT 1');
$bizStmt->execute([$businessId, 'active']);
if (!$bizStmt->fetch()) {
    wb_err('İşletme bulunamadı veya aktif değil', 404, 'business_not_found');
}

// ── Hizmet süresi ─────────────────────────────────────────────────────────────
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

$endMin = $startMin + $durationMin;
if ($endMin > 1440) {
    wb_err('Randevu gece yarısını geçemez', 422, 'midnight_overflow');
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

$startsAt  = $parsed['str'];
$endH      = intdiv($endMin, 60);
$endM      = $endMin % 60;
$endsAt    = sprintf('%s %02d:%02d:00', $dayStr, $endH, $endM);
$dbStaffId = $staffId ?? 0; // slot_locks: 0 = işletme geneli kilit

// ── Transaction ───────────────────────────────────────────────────────────────
$lockToken = null;

try {
    $pdo->beginTransaction();

    // 1. Süresi dolan kilitleri temizle
    $pdo->prepare('DELETE FROM slot_locks WHERE expires_at < NOW()')->execute();

    // 2. Randevu çakışması kontrolü
    $apptSql    = "SELECT id FROM appointments
                   WHERE business_id = ?
                     AND status NOT IN ('cancelled','no_show','rejected','declined')
                     AND start_at < ? AND end_at > ?";
    $apptParams = [$businessId, $endsAt, $startsAt];
    if ($staffId !== null) {
        $apptSql   .= ' AND staff_id = ?';
        $apptParams[] = $staffId;
    }
    $apptStmt = $pdo->prepare($apptSql);
    $apptStmt->execute($apptParams);
    if ($apptStmt->fetch()) {
        $pdo->rollBack();
        wb_err('Bu saat zaten dolu', 409, 'conflict');
    }

    // 3. Slot kilit çakışması kontrolü
    if ($staffId !== null) {
        $lockSql    = "SELECT id FROM slot_locks
                       WHERE business_id = ? AND day_str = ?
                         AND start_min < ? AND (start_min + duration_min) > ?
                         AND (staff_id = ? OR staff_id = 0)
                         AND expires_at >= NOW()";
        $lockParams = [$businessId, $dayStr, $endMin, $startMin, $staffId];
    } else {
        $lockSql    = "SELECT id FROM slot_locks
                       WHERE business_id = ? AND day_str = ?
                         AND start_min < ? AND (start_min + duration_min) > ?
                         AND staff_id = 0
                         AND expires_at >= NOW()";
        $lockParams = [$businessId, $dayStr, $endMin, $startMin];
    }
    $lockStmt = $pdo->prepare($lockSql);
    $lockStmt->execute($lockParams);
    if ($lockStmt->fetch()) {
        $pdo->rollBack();
        wb_err('Bu saat şu an başka biri tarafından seçildi, lütfen farklı bir saat deneyin', 409, 'locked');
    }

    // 4. Yeni kilit oluştur
    $lockToken = bin2hex(random_bytes(24)); // 48 karakter hex
    $pdo->prepare(
        'INSERT INTO slot_locks
             (business_id, staff_id, day_str, start_min, duration_min, lock_token, expires_at)
         VALUES (?, ?, ?, ?, ?, ?, DATE_ADD(NOW(), INTERVAL ? SECOND))'
    )->execute([$businessId, $dbStaffId, $dayStr, $startMin, $durationMin, $lockToken, MB_LOCK_TTL_SEC]);

    $pdo->commit();

} catch (Throwable $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    error_log('[mobile/booking/lock.php] ' . $e->getMessage());
    wb_err('Slot kilitlenemedi, lütfen tekrar deneyin', 500, 'internal_error');
}

$expiresAt = (new DateTimeImmutable('now', $tz))->modify('+' . MB_LOCK_TTL_SEC . ' seconds');

// ── Kampanya ön-teklifi (bilgi amaçlı; book.php sunucuda yeniden hesaplar) ────
// İstemci özet ekranında indirimi gösterebilsin diye seçilen hizmet+slot için
// en avantajlı kampanya quote'u döndürülür. Fiyat/indirim DB'den hesaplanır.
$campaignQuote  = null;
$campaignReason = null;
try {
    $priceStmt = $pdo->prepare('SELECT price FROM services WHERE id = ? AND business_id = ? LIMIT 1');
    $priceStmt->execute([$serviceId, $businessId]);
    $svcPriceRaw = $priceStmt->fetchColumn();
    $svcPrice = ($svcPriceRaw !== false && $svcPriceRaw !== null) ? (float)$svcPriceRaw : 0.0;
    if ($svcPrice > 0) {
        $q = wb_campaign_quote_for_slot($pdo, $businessId, $serviceId, $svcPrice, $parsed['dt']);
        $campaignQuote = $q['campaign'];
        $campaignReason = $q['reason'];
    }
} catch (Throwable $cmpEx) {
    error_log('[mobile/booking/lock.php campaign] ' . $cmpEx->getMessage());
}

wb_ok([
    'locked'     => true,
    'lock_token' => $lockToken,
    'expires_at' => $expiresAt->format('Y-m-d H:i:s'),
    'expires_in' => MB_LOCK_TTL_SEC,
    'starts_at'  => $startsAt,
    'ends_at'    => $endsAt,
    'campaign'   => $campaignQuote,
    'campaign_reason' => $campaignReason,
]);
