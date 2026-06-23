<?php
// api/admin/completeOnboarding.php — Onboarding tamamla (tek seferlik büyük kayıt)
declare(strict_types=1);

require_once __DIR__ . '/_bootstrap.php';

wb_method('POST');

$sess = wb_auth_admin();
$in   = wb_body();

/* PAYLOAD PARSE */
$profile       = is_array($in['profile'])       ? $in['profile']       : [];
$workingHours  = is_array($in['workingHours'])  ? $in['workingHours']  : [];
$services      = is_array($in['services'])      ? $in['services']      : [];
$staff         = is_array($in['staff'])         ? $in['staff']         : [];

$locationDraft = is_array($in['locationDraft']) ? $in['locationDraft'] : [];
$rawOnboarding = is_array($in['rawOnboarding']) ? $in['rawOnboarding'] : [];

$addressObj = null;
foreach ([$locationDraft['address'] ?? null, $rawOnboarding['address'] ?? null, $locationDraft] as $candidate) {
    if (is_array($candidate) && !empty($candidate)) {
        $addressObj = $candidate;
        break;
    }
}

try {
    $stmt = $pdo->prepare("SELECT id FROM businesses WHERE owner_id = ? LIMIT 1");
    $stmt->execute([$sess['user_id']]);
    $business = $stmt->fetch();

    if (!$business) {
        // İlk kayıtta business satırı henüz oluşmamış olabilir — upsert
        $businessName = trim((string)($profile['businessName'] ?? 'İşletme'));
        $ownerName    = trim((string)($profile['adminName'] ?? $profile['ownerName'] ?? ''));
        $phone        = preg_replace('/\D+/', '', (string)($profile['adminPhone'] ?? $profile['phone'] ?? ''));
        $pdo->prepare("
            INSERT INTO businesses (owner_id, name, owner_name, phone, type, status, onboarding_step)
            VALUES (?, ?, ?, ?, 'kuafor', 'draft', 2)
        ")->execute([$sess['user_id'], $businessName ?: 'İşletme', $ownerName ?: null, $phone ?: null]);
        $businessId = (int)$pdo->lastInsertId();
    } else {
        $businessId = (int)$business['id'];
    }
    $pdo->beginTransaction();

    /* 1) BUSİNESS — temel bilgiler + aktif et */
    $businessName = trim((string)($profile['businessName'] ?? ''));
    $ownerName    = trim((string)($profile['adminName']    ?? $profile['ownerName'] ?? ''));
    $phone        = preg_replace('/\D+/', '', (string)($profile['adminPhone'] ?? $profile['phone'] ?? ''));

    $city         = trim((string)($addressObj['cityName']         ?? $addressObj['city']         ?? ''));
    $district     = trim((string)($addressObj['districtName']     ?? $addressObj['district']     ?? ''));
    $addrLine     = trim((string)($addressObj['addressLine']      ?? ''));
    $neighborhood = trim((string)($addressObj['neighborhoodName'] ?? ''));
    $street       = trim((string)($addressObj['street']           ?? ''));
    $buildingNo   = trim((string)($addressObj['buildingNo']       ?? ''));

    if ($addrLine === '' && ($street !== '' || $district !== '')) {
        $addrLine = trim("{$neighborhood} {$street}" . ($buildingNo ? " No:{$buildingNo}" : '') . ", {$district}/{$city}");
    }

    $pdo->prepare("
        UPDATE businesses
        SET name                 = CASE WHEN ? != '' THEN ? ELSE name END,
            owner_name           = CASE WHEN ? != '' THEN ? ELSE owner_name END,
            phone                = CASE WHEN ? != '' THEN ? ELSE phone END,
            city                 = CASE WHEN ? != '' THEN ? ELSE city END,
            district             = CASE WHEN ? != '' THEN ? ELSE district END,
            neighborhood         = CASE WHEN ? != '' THEN ? ELSE neighborhood END,
            building_no          = CASE WHEN ? != '' THEN ? ELSE building_no END,
            address_line         = CASE WHEN ? != '' THEN ? ELSE address_line END,
            status               = 'active',
            onboarding_completed = 1,
            onboarding_step      = 7,
            updated_at           = NOW()
        WHERE id = ?
    ")->execute([
        $businessName, $businessName,
        $ownerName,    $ownerName,
        $phone,        $phone,
        $city,         $city,
        $district,     $district,
        $neighborhood, $neighborhood,
        $buildingNo,   $buildingNo,
        $addrLine,     $addrLine,
        $businessId,
    ]);

    /* 2) ADMIN_USERS — tamamlandı */
    $pdo->prepare("UPDATE admin_users SET onboarding_completed = 1 WHERE user_id = ?")
        ->execute([$sess['user_id']]);

    /* 3) ÇALIŞMA SAATLERİ */
    $DAY_KEYS = ['mon','tue','wed','thu','fri','sat','sun'];
    if (!empty($workingHours)) {
        $pdo->prepare("DELETE FROM business_hours WHERE business_id = ?")->execute([$businessId]);
        $insertHours = $pdo->prepare("
            INSERT INTO business_hours (business_id, day, is_open, open_time, close_time)
            VALUES (?, ?, ?, ?, ?)
        ");
        foreach ($DAY_KEYS as $day) {
            $h      = is_array($workingHours[$day] ?? null) ? $workingHours[$day] : [];
            $isOpen = (bool)($h['open'] ?? false);
            $from   = $isOpen ? (string)($h['from'] ?? '09:00') : null;
            $to     = $isOpen ? (string)($h['to']   ?? '18:00') : null;
            if ($from && strlen($from) === 5) $from .= ':00';
            if ($to   && strlen($to)   === 5) $to   .= ':00';
            $insertHours->execute([$businessId, $day, $isOpen ? 1 : 0, $from, $to]);
        }
    }

    /* 4) HİZMETLER */
    $insertedServiceIds = [];
    if (!empty($services)) {
        $pdo->prepare("DELETE FROM services WHERE business_id = ?")->execute([$businessId]);
        $insertSvc = $pdo->prepare("INSERT INTO services (business_id, name, price, duration_min) VALUES (?, ?, ?, ?)");
        foreach ($services as $svc) {
            if (!is_array($svc)) continue;
            $name  = trim((string)($svc['name'] ?? ''));
            $min   = (int)($svc['min'] ?? $svc['minutes'] ?? $svc['duration_min'] ?? 0);
            $price = (float)($svc['price'] ?? 0);
            if ($name === '' || $min <= 0) continue;
            $insertSvc->execute([$businessId, $name, $price, $min]);
            $insertedServiceIds[] = (int)$pdo->lastInsertId();
        }
    }

    if (empty($insertedServiceIds)) {
        $fallback = $pdo->prepare("SELECT id FROM services WHERE business_id = ?");
        $fallback->execute([$businessId]);
        $insertedServiceIds = array_map('intval', $fallback->fetchAll(PDO::FETCH_COLUMN));
    }

    /* 5) PERSONEL + OTOMATİK SERVİS ATAMA */
    if (!empty($staff)) {
        $pdo->prepare("DELETE FROM staff WHERE business_id = ?")->execute([$businessId]);
        $insertStaff    = $pdo->prepare("INSERT INTO staff (business_id, name, phone, color) VALUES (?, ?, ?, ?)");
        $insertStaffSvc = $pdo->prepare("INSERT IGNORE INTO staff_services (staff_id, service_id) VALUES (?, ?)");
        $insertedStaffIds = [];

        $seen = [];
        foreach ($staff as $s) {
            if (!is_array($s)) continue;
            $name     = trim((string)($s['name'] ?? ''));
            $sPhone   = preg_replace('/\D+/', '', (string)($s['phoneNational'] ?? $s['phone'] ?? ''));
            $color    = trim((string)($s['color'] ?? ''));

            if (mb_strlen($name) < 2) continue;
            $key = $sPhone ?: mb_strtolower($name);
            if (isset($seen[$key])) continue;
            $seen[$key] = true;

            $insertStaff->execute([$businessId, $name, $sPhone ?: null, $color ?: null]);
            $newStaffId = (int)$pdo->lastInsertId();
            $insertedStaffIds[] = $newStaffId;

            foreach ($insertedServiceIds as $svcId) {
                $insertStaffSvc->execute([$newStaffId, (int)$svcId]);
            }
        }

        // Onboarding akışı tüm personellere tüm hizmetleri atamayı garanti eder.
        // Bazı kurulumlarda ara payload sorunları yaşanırsa finalde bir kez daha tamamla.
        if (!empty($insertedStaffIds) && !empty($insertedServiceIds)) {
            foreach ($insertedStaffIds as $staffId) {
                foreach ($insertedServiceIds as $svcId) {
                    $insertStaffSvc->execute([(int)$staffId, (int)$svcId]);
                }
            }
        }
    }

    $pdo->commit();

    wb_ok([
        'barberId'      => (string)$businessId,
        'step'          => 7,
        'status'        => 'active',
        'savedServices' => count($services),
        'savedStaff'    => count($staff),
        'savedHours'    => count($workingHours),
    ]);

} catch (Throwable $e) {
    if (isset($pdo) && $pdo->inTransaction()) $pdo->rollBack();
    error_log('[completeOnboarding] ' . $e->getMessage());
    wb_err('Onboarding tamamlanamadı', 500, 'internal_error');
}
