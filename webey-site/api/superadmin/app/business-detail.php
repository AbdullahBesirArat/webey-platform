<?php
declare(strict_types=1);
/**
 * api/superadmin/app/business-detail.php?id=...
 * GET — Tek işletme detayı. READ-ONLY.
 * IBAN düz dönmez (sadece var/yok + son 4 hane maskesi).
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/_helpers.php';
require_once __DIR__ . '/../../mobile/_business_visibility.php';
wb_method('GET');

$id = (int)($_GET['id'] ?? 0);
if ($id <= 0) {
    wb_err('Geçersiz işletme id', 400, 'invalid_id');
}

try {
    $visibilityJoin = wb_business_visibility_join_sql($pdo);
    $visibilitySelect = wb_business_visibility_select_sql($pdo);
    $biz = sa_row($pdo, "
        SELECT b.id, b.name, b.slug, b.type, b.status, b.owner_id, b.owner_name,
               b.phone, b.city, b.district, b.neighborhood, b.address_line,
               b.about, b.min_price, b.max_price,
               (b.latitude IS NOT NULL AND b.longitude IS NOT NULL) AS has_location,
               b.latitude, b.longitude,
               b.onboarding_completed, b.onboarding_step,
               b.approved_at, b.created_at, b.updated_at
               $visibilitySelect
        FROM businesses b
        $visibilityJoin
        WHERE b.id = ?", [$id]);

    if (!$biz) {
        wb_err('İşletme bulunamadı', 404, 'not_found');
    }

    // Sahip özeti — hassas kolonlar (password_hash, token'lar) SELECT edilmez.
    $visibility = wb_business_visibility_from_row($biz);

    $owner = sa_row($pdo, "
        SELECT u.id, u.name, u.email, u.created_at, u.last_login_at
        FROM users u WHERE u.id = ?", [(int)$biz['owner_id']]);

    $services = sa_rows($pdo, "
        SELECT s.id, s.name, s.price, s.duration_min, s.is_active,
               s.category AS category_text, sc.name AS category_name
        FROM services s
        LEFT JOIN service_categories sc ON sc.id = s.category_id
        WHERE s.business_id = ?
        ORDER BY s.sort_order, s.name", [$id]);

    $categorySummary = sa_rows($pdo, "
        SELECT sc.id, sc.name, sc.slug, (sc.business_id = 0) AS is_system,
               COUNT(s.id) AS service_count
        FROM service_categories sc
        LEFT JOIN services s ON s.category_id = sc.id AND s.business_id = ?
        WHERE sc.business_id IN (0, ?)
        GROUP BY sc.id, sc.name, sc.slug, sc.business_id
        HAVING service_count > 0 OR sc.business_id = ?
        ORDER BY sc.sort_order", [$id, $id, $id]);

    $staff = sa_rows($pdo, "
        SELECT id, name, phone, is_active, created_at
        FROM staff WHERE business_id = ? ORDER BY name", [$id]);
    foreach ($staff as &$st) {
        $st['phone_masked'] = sa_mask_phone($st['phone']);
        unset($st['phone']);
        $st['is_active'] = (bool)$st['is_active'];
    }
    unset($st);

    $photoTotals = sa_row($pdo, "
        SELECT COUNT(*) AS total,
               COALESCE(SUM(is_cover=1),0) AS cover_count,
               COALESCE(SUM(is_visible=1),0) AS visible_count
        FROM business_photos WHERE business_id = ? AND status='active'", [$id]) ?? [];
    $photoByCategory = sa_rows($pdo, "
        SELECT category, COUNT(*) AS cnt
        FROM business_photos WHERE business_id = ? AND status='active'
        GROUP BY category ORDER BY cnt DESC", [$id]);

    $appointments = sa_rows($pdo, "
        SELECT a.id, a.customer_name, a.customer_phone, a.start_at, a.status,
               a.booking_source, a.deposit_required, a.deposit_amount,
               a.deposit_status, a.created_at,
               s.name AS service_name, st.name AS staff_name
        FROM appointments a
        LEFT JOIN services s ON s.id = a.service_id
        LEFT JOIN staff st ON st.id = a.staff_id
        WHERE a.business_id = ?
        ORDER BY a.start_at DESC LIMIT 20", [$id]);
    foreach ($appointments as &$a) {
        $a['customer_phone_masked'] = sa_mask_phone($a['customer_phone']);
        unset($a['customer_phone']);
        $a['deposit_required'] = (bool)$a['deposit_required'];
    }
    unset($a);

    $reviews = sa_rows($pdo, "
        SELECT r.id, r.rating, r.comment, r.status, r.business_reply IS NOT NULL AS has_reply,
               r.created_at, u.name AS customer_name
        FROM reviews r
        LEFT JOIN users u ON u.id = r.customer_user_id
        WHERE r.business_id = ?
        ORDER BY r.created_at DESC LIMIT 10", [$id]);
    foreach ($reviews as &$rv) { $rv['has_reply'] = (bool)$rv['has_reply']; }
    unset($rv);

    $boost = sa_rows($pdo, "
        SELECT bs.id, bp.name AS package_name, bs.status, bs.payment_status,
               bs.starts_at, bs.ends_at, bs.paid_amount, bs.created_at
        FROM business_boost_subscriptions bs
        JOIN boost_packages bp ON bp.id = bs.package_id
        WHERE bs.business_id = ?
        ORDER BY bs.created_at DESC LIMIT 10", [$id]);

    // Kapora/ödeme ayarı — IBAN maskeli, account_holder/instructions dönmez.
    $pay = sa_row($pdo, "
        SELECT deposit_enabled, iban, bank_name
        FROM business_payment_settings WHERE business_id = ?", [$id]);
    $paymentSettings = [
        'deposit_enabled' => $pay ? (bool)$pay['deposit_enabled'] : false,
        'has_iban'        => (bool)($pay && $pay['iban'] !== null && $pay['iban'] !== ''),
        'iban_masked'     => $pay ? sa_mask_iban($pay['iban']) : null,
        'bank_name'       => $pay['bank_name'] ?? null,
    ];

    wb_ok([
        'business' => [
            'id'                   => (int)$biz['id'],
            'name'                 => $biz['name'],
            'slug'                 => $biz['slug'],
            'type'                 => $biz['type'],
            'status'               => $biz['status'],
            'city'                 => $biz['city'],
            'district'             => $biz['district'],
            'neighborhood'         => $biz['neighborhood'],
            'address_line'         => $biz['address_line'],
            'about'                => $biz['about'],
            'min_price'            => $biz['min_price'] !== null ? (int)$biz['min_price'] : null,
            'max_price'            => $biz['max_price'] !== null ? (int)$biz['max_price'] : null,
            'has_location'         => (bool)$biz['has_location'],
            'latitude'             => $biz['latitude'] !== null ? (float)$biz['latitude'] : null,
            'longitude'            => $biz['longitude'] !== null ? (float)$biz['longitude'] : null,
            'onboarding_completed' => (bool)$biz['onboarding_completed'],
            'onboarding_step'      => (int)$biz['onboarding_step'],
            // Kapora bilgisi canlı şemada business_payment_settings'te (businesses'ta deposit_* yok)
            'deposit_required'     => $paymentSettings['deposit_enabled'],
            'deposit_amount'       => null,
            'deposit_rate_pct'     => null,
            'deposit_per_service'  => null,
            'deposit_cancel_policy'=> null,
            'subscription_status'   => $visibility['subscription_status'],
            'visibility_status'     => $visibility['visibility_status'],
            'customer_visible'      => $visibility['visibility_status'] !== 'hidden',
            'is_boosted'            => $visibility['is_boosted'],
            'boost_badge'           => $visibility['boost_badge'],
            'boost_ends_at'         => $visibility['boost_ends_at'],
            'profile_quality_score' => $visibility['profile_quality_score'],
            'approved_at'          => $biz['approved_at'],
            'created_at'           => $biz['created_at'],
            'updated_at'           => $biz['updated_at'],
        ],
        'owner' => $owner ? [
            'id'            => (int)$owner['id'],
            'name'          => $owner['name'],
            'email_masked'  => sa_mask_email($owner['email']),
            'phone_masked'  => sa_mask_phone($biz['phone']),
            'created_at'    => $owner['created_at'],
            'last_login_at' => $owner['last_login_at'],
        ] : null,
        'services'           => $services,
        'category_summary'   => $categorySummary,
        'staff'              => $staff,
        'photos' => [
            'total'           => (int)($photoTotals['total'] ?? 0),
            'has_cover'       => (int)($photoTotals['cover_count'] ?? 0) > 0,
            'visible_count'   => (int)($photoTotals['visible_count'] ?? 0),
            'category_counts' => $photoByCategory,
        ],
        'latest_appointments' => $appointments,
        'latest_reviews'      => $reviews,
        'boost'               => $boost,
        'payment_settings'    => $paymentSettings,
    ]);

} catch (Throwable $e) {
    error_log('[superadmin/app/business-detail] ' . $e->getMessage());
    wb_err('İşletme detayı yüklenemedi', 500, 'internal_error');
}
