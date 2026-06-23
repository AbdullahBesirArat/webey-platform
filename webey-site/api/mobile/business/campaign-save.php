<?php
declare(strict_types=1);
/**
 * api/mobile/business/campaign-save.php
 * POST - Kampanya oluşturur (id yoksa) veya günceller (id varsa).
 * Yalnız token sahibi işletme kendi kampanyasını/hizmetini kullanabilir.
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';
require_once __DIR__ . '/_helpers.php';
require_once __DIR__ . '/../_campaigns.php';

wb_method('POST');

$auth = mobile_auth($pdo, ['business', 'admin']);
$ctx = mobile_business_context($pdo, $auth);
$businessId = (int)$ctx['business_id'];

if (!wb_campaign_tables_ready($pdo)) {
    wb_err('Kampanya altyapısı henüz hazır değil', 503, 'campaigns_unavailable');
}

$body = wb_body();

$id            = (int)($body['id'] ?? 0);
$title         = mb_substr(trim((string)($body['title'] ?? '')), 0, 120);
$description   = mb_substr(trim((string)($body['description'] ?? '')), 0, 500);
$conditionType = (string)($body['condition_type'] ?? 'general');
$discountKind  = (string)($body['discount_kind'] ?? 'percent');
$discountValue = (float)($body['discount_value'] ?? 0);
$scopeType     = (string)($body['scope_type'] ?? 'all_services');
$startDate     = trim((string)($body['start_date'] ?? ''));
$endDate       = trim((string)($body['end_date'] ?? ''));
$startTime     = trim((string)($body['start_time'] ?? ''));
$endTime       = trim((string)($body['end_time'] ?? ''));
$status        = (string)($body['status'] ?? 'active');

// days_of_week: dizi veya CSV kabul et
$rawDays = $body['days_of_week'] ?? [];
if (is_string($rawDays)) {
    $rawDays = $rawDays === '' ? [] : explode(',', $rawDays);
}
$days = [];
if (is_array($rawDays)) {
    foreach ($rawDays as $d) {
        $n = (int)$d;
        if ($n >= 1 && $n <= 7) {
            $days[$n] = $n;
        }
    }
}
ksort($days);
$daysCsv = $days === [] ? null : implode(',', array_values($days));

// service_ids
$rawServiceIds = $body['service_ids'] ?? [];
if (is_string($rawServiceIds)) {
    $rawServiceIds = $rawServiceIds === '' ? [] : explode(',', $rawServiceIds);
}
$serviceIds = [];
if (is_array($rawServiceIds)) {
    foreach ($rawServiceIds as $sid) {
        $n = (int)$sid;
        if ($n > 0) {
            $serviceIds[$n] = $n;
        }
    }
}
$serviceIds = array_values($serviceIds);

// ── Doğrulama ────────────────────────────────────────────────────────────────
if ($title === '') {
    wb_err('Kampanya adı zorunlu', 422, 'missing_title');
}
if (!in_array($conditionType, ['general', 'weekday', 'hourly'], true)) {
    wb_err('Geçersiz kampanya biçimi', 422, 'invalid_condition_type');
}
if (!in_array($discountKind, ['percent', 'fixed'], true)) {
    wb_err('Geçersiz indirim türü', 422, 'invalid_discount_kind');
}
if (!in_array($scopeType, ['all_services', 'selected_services'], true)) {
    wb_err('Geçersiz kapsam', 422, 'invalid_scope');
}
if (!in_array($status, ['active', 'paused'], true)) {
    wb_err('Geçersiz durum', 422, 'invalid_status');
}
if ($discountValue <= 0) {
    wb_err('İndirim değeri 0\'dan büyük olmalı', 422, 'invalid_discount_value');
}
if ($discountKind === 'percent' && ($discountValue < 1 || $discountValue > 100)) {
    wb_err('Yüzde indirim 1–100 arasında olmalı', 422, 'invalid_percent');
}
if ($discountKind === 'fixed' && $discountValue < 1) {
    wb_err('Sabit indirim en az 1 TL olmalı', 422, 'invalid_fixed');
}

// Tarih doğrulama
$dateRe = '/^\d{4}-\d{2}-\d{2}$/';
if ($startDate !== '' && !preg_match($dateRe, $startDate)) {
    wb_err('Başlangıç tarihi geçersiz', 422, 'invalid_start_date');
}
if ($endDate !== '' && !preg_match($dateRe, $endDate)) {
    wb_err('Bitiş tarihi geçersiz', 422, 'invalid_end_date');
}
if ($startDate !== '' && $endDate !== '' && $endDate < $startDate) {
    wb_err('Bitiş tarihi başlangıçtan önce olamaz', 422, 'date_range_invalid');
}

// Saat doğrulama
$timeRe = '/^\d{2}:\d{2}(:\d{2})?$/';
$normTime = static function (string $t): ?string {
    if ($t === '') return null;
    return substr($t, 0, 5) . ':00';
};
if ($startTime !== '' && !preg_match($timeRe, $startTime)) {
    wb_err('Başlangıç saati geçersiz', 422, 'invalid_start_time');
}
if ($endTime !== '' && !preg_match($timeRe, $endTime)) {
    wb_err('Bitiş saati geçersiz', 422, 'invalid_end_time');
}
if ($conditionType === 'hourly') {
    if ($startTime === '' || $endTime === '') {
        wb_err('Saat bazlı kampanyada başlangıç ve bitiş saati zorunlu', 422, 'hourly_times_required');
    }
}
if ($startTime !== '' && $endTime !== '' && substr($endTime, 0, 5) <= substr($startTime, 0, 5)) {
    wb_err('Bitiş saati başlangıçtan sonra olmalı', 422, 'time_range_invalid');
}
if ($conditionType === 'weekday' && $daysCsv === null) {
    wb_err('Hafta içi kampanyasında en az bir gün seçilmeli', 422, 'days_required');
}

// Kapsam doğrulama
if ($scopeType === 'selected_services' && $serviceIds === []) {
    wb_err('Seçili hizmet kapsamında en az bir hizmet seçin', 422, 'services_required');
}

try {
    // service_ids işletmeye ait mi
    if ($scopeType === 'selected_services') {
        $ph = implode(',', array_fill(0, count($serviceIds), '?'));
        $chk = $pdo->prepare("SELECT id FROM services WHERE business_id = ? AND id IN ($ph)");
        $chk->execute(array_merge([$businessId], $serviceIds));
        $owned = array_map('intval', $chk->fetchAll(PDO::FETCH_COLUMN));
        if (count($owned) !== count($serviceIds)) {
            wb_err('Seçili hizmetlerden biri bu işletmeye ait değil', 422, 'invalid_service');
        }
    }

    // Sabit indirim, kapsamdaki hizmetlerden EN AZ BİRİNİN fiyatını aşmamalı
    // (aksi halde hiçbir hizmete uygulanabilir indirim kalmaz).
    if ($discountKind === 'fixed') {
        if ($scopeType === 'selected_services') {
            $ph = implode(',', array_fill(0, count($serviceIds), '?'));
            $priceStmt = $pdo->prepare(
                "SELECT MAX(price) FROM services WHERE business_id = ? AND id IN ($ph) AND price IS NOT NULL"
            );
            $priceStmt->execute(array_merge([$businessId], $serviceIds));
        } else {
            $priceStmt = $pdo->prepare(
                "SELECT MAX(price) FROM services WHERE business_id = ? AND price IS NOT NULL"
            );
            $priceStmt->execute([$businessId]);
        }
        $maxPrice = $priceStmt->fetchColumn();
        if ($maxPrice !== false && $maxPrice !== null && (float)$maxPrice > 0
            && $discountValue > (float)$maxPrice) {
            $pdo->inTransaction() && $pdo->rollBack();
            wb_err(
                'Sabit indirim, kapsamdaki hizmetlerden en az birinin fiyatını aşmamalıdır.',
                422,
                'fixed_exceeds_price'
            );
        }
    }

    $startDateVal = $startDate !== '' ? $startDate : null;
    $endDateVal   = $endDate !== '' ? $endDate : null;
    $startTimeVal = $normTime($startTime);
    $endTimeVal   = $normTime($endTime);

    $pdo->beginTransaction();

    if ($id > 0) {
        $check = $pdo->prepare("SELECT id FROM business_campaigns WHERE id = ? AND business_id = ? AND status <> 'archived' LIMIT 1 FOR UPDATE");
        $check->execute([$id, $businessId]);
        if (!$check->fetch()) {
            $pdo->rollBack();
            wb_err('Kampanya bulunamadı', 404, 'campaign_not_found');
        }
        $pdo->prepare(
            "UPDATE business_campaigns SET
                title = ?, description = ?, condition_type = ?, discount_kind = ?,
                discount_value = ?, scope_type = ?, start_date = ?, end_date = ?,
                start_time = ?, end_time = ?, days_of_week = ?, status = ?
             WHERE id = ? AND business_id = ?"
        )->execute([
            $title, $description !== '' ? $description : null, $conditionType, $discountKind,
            $discountValue, $scopeType, $startDateVal, $endDateVal,
            $startTimeVal, $endTimeVal, $daysCsv, $status,
            $id, $businessId,
        ]);
    } else {
        $pdo->prepare(
            "INSERT INTO business_campaigns
                (business_id, title, description, condition_type, discount_kind,
                 discount_value, scope_type, start_date, end_date, start_time, end_time,
                 days_of_week, status, created_at, updated_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW(), NOW())"
        )->execute([
            $businessId, $title, $description !== '' ? $description : null, $conditionType, $discountKind,
            $discountValue, $scopeType, $startDateVal, $endDateVal, $startTimeVal, $endTimeVal,
            $daysCsv, $status,
        ]);
        $id = (int)$pdo->lastInsertId();
    }

    // Hizmet bağ tablosunu senkronla
    $pdo->prepare('DELETE FROM campaign_services WHERE campaign_id = ?')->execute([$id]);
    if ($scopeType === 'selected_services' && $serviceIds !== []) {
        $ins = $pdo->prepare('INSERT IGNORE INTO campaign_services (campaign_id, service_id) VALUES (?, ?)');
        foreach ($serviceIds as $sid) {
            $ins->execute([$id, $sid]);
        }
    }

    $pdo->commit();

    // Çakışan AKTİF kampanyalar (uyarı; engel değil — müşteriye en avantajlısı uygulanır).
    $conflictTitles = $status === 'active'
        ? wb_campaign_conflicts($pdo, $businessId, $scopeType === 'all_services', $serviceIds, $id, $startDateVal, $endDateVal)
        : [];
    $conflictWarning = null;
    if ($conflictTitles !== []) {
        $first = $conflictTitles[0];
        $conflictWarning = count($conflictTitles) === 1
            ? ('Bu kampanya, "' . $first . '" kampanyasıyla bazı koşullarda çakışıyor. Müşteriye en avantajlı indirim otomatik uygulanır.')
            : ('Bu kampanya, ' . count($conflictTitles) . ' kampanyayla bazı koşullarda çakışıyor. Müşteriye en avantajlı indirim otomatik uygulanır.');
    }

    // Geri dön: kaydedilen kampanya
    $row = $pdo->prepare('SELECT * FROM business_campaigns WHERE id = ? LIMIT 1');
    $row->execute([$id]);
    $c = $row->fetch();

    wb_ok([
        'saved' => true,
        'conflicts' => $conflictTitles,
        'conflict_warning' => $conflictWarning,
        'campaign' => [
            'id'             => (string)$c['id'],
            'title'          => (string)$c['title'],
            'condition_type' => (string)$c['condition_type'],
            'discount_kind'  => (string)$c['discount_kind'],
            'discount_value' => (float)$c['discount_value'],
            'scope_type'     => (string)$c['scope_type'],
            'service_ids'    => array_map('strval', $serviceIds),
            'start_date'     => $c['start_date'] !== null ? (string)$c['start_date'] : null,
            'end_date'       => $c['end_date'] !== null ? (string)$c['end_date'] : null,
            'start_time'     => wb_campaign_hm($c['start_time'] ?? null),
            'end_time'       => wb_campaign_hm($c['end_time'] ?? null),
            'days_of_week'   => wb_campaign_days($c['days_of_week'] ?? null),
            'status'         => (string)$c['status'],
            'is_active'      => (string)$c['status'] === 'active',
            'badge'          => wb_campaign_badge($c),
            'summary'        => wb_campaign_summary($c),
        ],
    ]);
} catch (Throwable $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    error_log('[mobile/business/campaign-save.php] ' . $e->getMessage());
    wb_err('Kampanya kaydedilemedi', 500, 'internal_error');
}
