<?php
declare(strict_types=1);
/**
 * api/superadmin/app/businesses.php
 * GET — İşletme listesi (filtre + pagination). READ-ONLY.
 *
 * Filtreler: q, status, onboarding=completed|incomplete, missing_location=1,
 *            missing_cover=1, no_services=1, deposit_required=1, iban_missing=1,
 *            city, district, page, limit
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/_helpers.php';
require_once __DIR__ . '/../../mobile/_business_visibility.php';
wb_method('GET');

try {
    $pg     = sa_page_params(25);
    $where  = [];
    $params = [];

    $q = trim((string)($_GET['q'] ?? ''));
    if ($q !== '') {
        $where[]  = '(b.name LIKE ? OR b.owner_name LIKE ? OR b.city LIKE ? OR b.district LIKE ?)';
        $like     = sa_like($q);
        array_push($params, $like, $like, $like, $like);
    }

    $status = trim((string)($_GET['status'] ?? ''));
    if (in_array($status, ['draft', 'pending', 'active', 'rejected', 'suspended'], true)) {
        $where[]  = 'b.status = ?';
        $params[] = $status;
    }

    $onboarding = trim((string)($_GET['onboarding'] ?? ''));
    if ($onboarding === 'completed')  $where[] = 'b.onboarding_completed = 1';
    if ($onboarding === 'incomplete') $where[] = 'b.onboarding_completed = 0';

    if (($_GET['missing_location'] ?? '') === '1') $where[] = '(b.latitude IS NULL OR b.longitude IS NULL)';
    // Kapora aktifliği canlı şemada business_payment_settings.deposit_enabled'da tutuluyor
    // (businesses tablosunda deposit_* kolonu yok).
    if (($_GET['deposit_required'] ?? '') === '1') {
        $where[] = 'EXISTS (SELECT 1 FROM business_payment_settings ps
                     WHERE ps.business_id = b.id AND ps.deposit_enabled = 1)';
    }
    if (($_GET['missing_cover'] ?? '') === '1') {
        $where[] = "NOT EXISTS (SELECT 1 FROM business_photos p
                     WHERE p.business_id = b.id AND p.is_cover = 1 AND p.status = 'active')";
    }
    if (($_GET['no_services'] ?? '') === '1') {
        $where[] = 'NOT EXISTS (SELECT 1 FROM services s WHERE s.business_id = b.id)';
    }
    if (($_GET['iban_missing'] ?? '') === '1') {
        $where[] = "NOT EXISTS (SELECT 1 FROM business_payment_settings ps
                     WHERE ps.business_id = b.id AND ps.iban IS NOT NULL AND ps.iban <> '')";
    }

    $city = trim((string)($_GET['city'] ?? ''));
    if ($city !== '') { $where[] = 'b.city LIKE ?'; $params[] = sa_like($city); }

    $district = trim((string)($_GET['district'] ?? ''));
    if ($district !== '') { $where[] = 'b.district LIKE ?'; $params[] = sa_like($district); }

    $whereSql = $where ? ('WHERE ' . implode(' AND ', $where)) : '';
    $visibilityJoin = wb_business_visibility_join_sql($pdo);
    $visibilitySelect = wb_business_visibility_select_sql($pdo);

    $total = (int)sa_val($pdo, "SELECT COUNT(*) FROM businesses b $visibilityJoin $whereSql", $params);

    // NOT: IBAN düz SELECT edilmez — sadece has_iban boolean'ı hesaplanır.
    $rows = sa_rows($pdo, "
        SELECT
            b.id, b.name, b.owner_name, b.phone AS owner_phone,
            b.city, b.district, b.neighborhood, b.status, b.type,
            b.onboarding_completed, b.onboarding_step,
            (b.latitude IS NOT NULL AND b.longitude IS NOT NULL) AS has_location,
            EXISTS (SELECT 1 FROM business_payment_settings ps
                    WHERE ps.business_id=b.id AND ps.deposit_enabled=1)               AS deposit_required,
            b.created_at, b.updated_at,
            EXISTS (SELECT 1 FROM business_photos p
                    WHERE p.business_id=b.id AND p.is_cover=1 AND p.status='active') AS has_cover,
            (SELECT COUNT(*) FROM business_photos p
                    WHERE p.business_id=b.id AND p.status='active')                   AS photo_count,
            (SELECT COUNT(*) FROM services s WHERE s.business_id=b.id)               AS service_count,
            (SELECT COUNT(*) FROM staff st WHERE st.business_id=b.id AND st.is_active=1) AS staff_count,
            (SELECT COUNT(*) FROM appointments a WHERE a.business_id=b.id)           AS appointment_count,
            EXISTS (SELECT 1 FROM business_payment_settings ps
                    WHERE ps.business_id=b.id AND ps.iban IS NOT NULL AND ps.iban <> '') AS has_iban
            $visibilitySelect
        FROM businesses b
        $visibilityJoin
        $whereSql
        ORDER BY b.created_at DESC
        LIMIT {$pg['limit']} OFFSET {$pg['offset']}
    ", $params);

    $items = array_map(static function (array $r): array {
        $visibility = wb_business_visibility_from_row($r);
        return [
            'id'                    => (int)$r['id'],
            'name'                  => $r['name'],
            'owner_name'            => $r['owner_name'],
            'owner_phone_masked'    => sa_mask_phone($r['owner_phone']),
            'city'                  => $r['city'],
            'district'              => $r['district'],
            'neighborhood'          => $r['neighborhood'],
            'type'                  => $r['type'],
            'status'                => $r['status'],
            'onboarding_completed'  => (bool)$r['onboarding_completed'],
            'onboarding_step'       => (int)$r['onboarding_step'],
            'has_location'          => (bool)$r['has_location'],
            'has_cover'             => (bool)$r['has_cover'],
            'photo_count'           => (int)$r['photo_count'],
            'service_count'         => (int)$r['service_count'],
            'staff_count'           => (int)$r['staff_count'],
            'appointment_count'     => (int)$r['appointment_count'],
            'deposit_required'      => (bool)$r['deposit_required'],
            'deposit_amount'        => null, // canlı şemada işletme bazlı sabit kapora tutarı yok (randevu bazlı)
            'has_iban'              => (bool)$r['has_iban'],
            'subscription_status'   => $visibility['subscription_status'],
            'visibility_status'     => $visibility['visibility_status'],
            'customer_visible'      => $visibility['visibility_status'] !== 'hidden',
            'is_boosted'            => $visibility['is_boosted'],
            'boost_badge'           => $visibility['boost_badge'],
            'boost_ends_at'         => $visibility['boost_ends_at'],
            'profile_quality_score' => $visibility['profile_quality_score'],
            'created_at'            => $r['created_at'],
            'updated_at'            => $r['updated_at'],
        ];
    }, $rows);

    wb_ok(sa_list_payload($items, $total, $pg));

} catch (Throwable $e) {
    error_log('[superadmin/app/businesses] ' . $e->getMessage());
    wb_err('İşletme listesi yüklenemedi', 500, 'internal_error');
}
