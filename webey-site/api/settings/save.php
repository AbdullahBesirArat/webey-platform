<?php
declare(strict_types=1);
/**
 * api/settings/save.php
 * POST — İşletme ayarlarını kaydet (business info, hours, services, images)
 */

require_once __DIR__ . '/../admin/_bootstrap.php';
wb_method('POST');

$bid = $user['business_id'];
if (!$bid) wb_err('İşletme bulunamadı', 404, 'business_not_found');

$in = wb_body();

try {
    // ── İşletme bilgileri ────────────────────────────────────────────────────
    $name         = trim((string)($in['name']         ?? ''));
    $ownerName    = trim((string)($in['ownerName']    ?? ''));
    $about        = trim((string)($in['about']        ?? ''));
    $phone        = preg_replace('/\D+/', '', (string)($in['phone'] ?? ''));
    $city         = trim((string)($in['city']         ?? ''));
    $district     = trim((string)($in['district']     ?? ''));
    $neighborhood = trim((string)($in['neighborhood'] ?? ''));
    $buildingNo   = trim((string)($in['buildingNo']   ?? ''));
    $mapUrl       = trim((string)($in['mapUrl']       ?? ''));
    $addrLine     = trim("$neighborhood " . ($buildingNo ? "No:$buildingNo" : '') . ", $district/$city");

    $pdo->prepare('
        UPDATE businesses SET
            name         = COALESCE(NULLIF(?, ""), name),
            owner_name   = COALESCE(NULLIF(?, ""), owner_name),
            about        = ?,
            phone        = COALESCE(NULLIF(?, ""), phone),
            city         = COALESCE(NULLIF(?, ""), city),
            district     = COALESCE(NULLIF(?, ""), district),
            neighborhood = ?,
            building_no  = ?,
            map_url      = ?,
            address_line = COALESCE(NULLIF(?, ""), address_line),
            updated_at   = NOW()
        WHERE id = ?
    ')->execute([$name, $ownerName, $about, $phone, $city, $district, $neighborhood, $buildingNo, $mapUrl, $addrLine, $bid]);

    // ── Çalışma saatleri ─────────────────────────────────────────────────────
    $hours    = is_array($in['hours'] ?? null) ? $in['hours'] : [];
    $DAY_KEYS = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

    if (!empty($hours)) {
        $pdo->prepare('DELETE FROM business_hours WHERE business_id = ?')->execute([$bid]);
        $ins = $pdo->prepare('INSERT INTO business_hours (business_id, day, is_open, open_time, close_time) VALUES (?,?,?,?,?)');
        foreach ($DAY_KEYS as $day) {
            $h      = is_array($hours[$day] ?? null) ? $hours[$day] : [];
            $isOpen = !($h['closed'] ?? true);
            $from   = $isOpen ? ((string)($h['open']  ?? '10:00')) . ':00' : null;
            $to     = $isOpen ? ((string)($h['close'] ?? '19:00')) . ':00' : null;
            $ins->execute([$bid, $day, $isOpen ? 1 : 0, $from, $to]);
        }
    }

    // ── Hizmetler ────────────────────────────────────────────────────────────
    $services = is_array($in['services'] ?? null) ? $in['services'] : [];
    if (!empty($services)) {
        $pdo->prepare('DELETE FROM services WHERE business_id = ?')->execute([$bid]);
        $insSvc = $pdo->prepare('INSERT INTO services (business_id, name, duration_min, price) VALUES (?,?,?,?)');
        foreach ($services as $s) {
            $sName = trim((string)($s['name'] ?? ''));
            $min   = max(1, (int)($s['min'] ?? $s['duration_min'] ?? 30));
            $price = max(0, (float)($s['price'] ?? 0));
            if ($sName === '') continue;
            $insSvc->execute([$bid, $sName, $min, $price]);
        }
    }

    // ── Görseller ────────────────────────────────────────────────────────────
    $images = is_array($in['images'] ?? null) ? $in['images'] : null;
    if ($images !== null) {
        $pdo->prepare('UPDATE businesses SET images_json = ? WHERE id = ?')
            ->execute([json_encode($images), $bid]);
    }

    wb_ok(['saved' => true]);

} catch (Throwable $e) {
    error_log('[settings/save] ' . $e->getMessage());
    wb_err('Ayarlar kaydedilemedi', 500, 'internal_error');
}