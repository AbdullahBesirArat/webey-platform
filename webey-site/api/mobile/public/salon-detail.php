<?php
declare(strict_types=1);

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../business/_gallery_helpers.php';
require_once __DIR__ . '/../_payment_settings.php';
require_once __DIR__ . '/../_category_helpers.php';
require_once __DIR__ . '/../_business_visibility.php';
require_once __DIR__ . '/../_campaigns.php';
require_once __DIR__ . '/../_cancellation.php';

wb_method('GET');

$id = mobile_int_param('id', 0) ?? 0;
$slug = (string)mobile_param('slug', '');

if ($id <= 0 && $slug === '') {
    wb_err('id veya slug zorunlu', 400, 'missing_param');
}

function mobile_public_review_name(?string $name): string {
    $clean = trim((string)$name);
    if ($clean === '') {
        return 'Webey müşterisi';
    }
    $parts = preg_split('/\s+/u', $clean) ?: [];
    if (count($parts) <= 1) {
        return $parts[0] ?? 'Webey müşterisi';
    }
    $first = $parts[0];
    $lastInitial = mb_strtoupper(mb_substr((string)end($parts), 0, 1, 'UTF-8'), 'UTF-8');
    return $first . ' ' . $lastInitial . '.';
}

$hasDepositRequired = mobile_table_has_column($pdo, 'businesses', 'deposit_required');
$hasDepositAmount   = mobile_table_has_column($pdo, 'businesses', 'deposit_amount');
$hasDepositPolicies = mobile_table_has_column($pdo, 'deposit_policies', 'business_id');
$depositColsSql     = ($hasDepositRequired ? ', b.deposit_required' : '')
                    . ($hasDepositAmount   ? ', b.deposit_amount'   : '');
$atelierColSql      = mobile_table_has_column($pdo, 'businesses', 'atelier_note')
                    ? ', b.atelier_note' : ', NULL AS atelier_note';
$visibilityJoinSql = wb_business_visibility_join_sql($pdo);
$visibilitySelectSql = wb_business_visibility_select_sql($pdo);
$visibilityWhereSql = wb_business_visibility_where_sql($pdo);

try {
    if ($id > 0) {
        $stmt = $pdo->prepare("
            SELECT b.id, b.slug, b.name, b.about, b.city, b.district, b.address_line, b.phone,
                   b.images_json, b.min_price, b.max_price, b.type, b.latitude, b.longitude, b.map_url
                   {$depositColsSql}{$atelierColSql}{$visibilitySelectSql}
            FROM businesses b
            {$visibilityJoinSql}
            WHERE b.id = ? AND b.status = 'active' AND b.onboarding_completed = 1 {$visibilityWhereSql}
            LIMIT 1
        ");
        $stmt->execute([$id]);
    } else {
        $stmt = $pdo->prepare("
            SELECT b.id, b.slug, b.name, b.about, b.city, b.district, b.address_line, b.phone,
                   b.images_json, b.min_price, b.max_price, b.type, b.latitude, b.longitude, b.map_url
                   {$depositColsSql}{$atelierColSql}{$visibilitySelectSql}
            FROM businesses b
            {$visibilityJoinSql}
            WHERE b.slug = ? AND b.status = 'active' AND b.onboarding_completed = 1 {$visibilityWhereSql}
            LIMIT 1
        ");
        $stmt->execute([$slug]);
    }

    $biz = $stmt->fetch();
    if (!$biz) {
        wb_err('Salon bulunamadı', 404, 'not_found');
    }

    $businessId = (int)$biz['id'];
    $visibility = wb_business_visibility_from_row($biz);
    $policyRow = null;
    if ($hasDepositPolicies) {
        $policyStmt = $pdo->prepare('SELECT rate_pct, per_service, cancel_policy FROM deposit_policies WHERE business_id = ? LIMIT 1');
        $policyStmt->execute([$businessId]);
        $policyRow = $policyStmt->fetch() ?: null;
    }
    $policyRate = $policyRow !== null && ($policyRow['rate_pct'] ?? null) !== null ? (int)$policyRow['rate_pct'] : null;
    $fixedDepositAmount = ($hasDepositAmount && ($biz['deposit_amount'] ?? null) !== null)
        ? (float)$biz['deposit_amount']
        : null;
    $fixedDepositActive = $policyRate !== null
        && $policyRate <= 0
        && $hasDepositRequired
        && (bool)($biz['deposit_required'] ?? false)
        && $fixedDepositAmount !== null
        && $fixedDepositAmount > 0;
    $depositCalculationMode = $fixedDepositActive ? 'fixed' : 'percent';
    $policyRequired = $fixedDepositActive
        ? true
        : ($policyRate !== null ? $policyRate > 0 : ($hasDepositRequired ? (bool)($biz['deposit_required'] ?? false) : false));
    $depositLabel = $policyRequired
        ? ($fixedDepositActive
            ? number_format((float)$fixedDepositAmount, 0, ',', '.') . ' TL kapora'
            : ($policyRate !== null && $policyRate > 0 ? '%' . $policyRate . ' kapora' : 'Kapora var'))
        : 'Kapora yok';
    $depositDescription = $policyRequired
        ? ($policyRate !== null && $policyRate > 0
            ? 'Bu salon randevular için %' . $policyRate . ' kapora alır.'
            : 'Bu salon randevular için kapora alır.')
        : 'Bu salon kapora almadan randevu kabul ediyor.';
    $images = mobile_images($biz['images_json'] ?? null);
    $photoItems = mobile_gallery_public_items($pdo, $businessId);
    $coverItem = mobile_gallery_cover_from_table($pdo, $businessId);
    $galleryByCategory = [];
    $photoGallery = [];
    foreach ($photoItems as $item) {
        $url = $item['medium_url'] ?? $item['url'] ?? null;
        if (is_string($url) && $url !== '') {
            $photoGallery[] = $url;
            $galleryByCategory[$item['category']][] = $item;
        }
    }
    $gallery = $photoGallery !== [] ? array_values(array_unique($photoGallery)) : $images['gallery'];
    $coverUrl = $coverItem['large_url'] ?? $coverItem['medium_url'] ?? $coverItem['url'] ?? $images['cover_image_url'];

    // ── Tek kaynaklı galeri (yalnizca business_photos; legacy images_json
    //    fallback'i YOK). Business app'teki sayiyla birebir ayni olmasi icin
    //    customer app bu alanlari kullanir. Liste/strip icin lean payload:
    //    original donmez, yalnizca thumb/medium/large.
    $galleryLean = array_map(static fn(array $item): array => [
        'id' => $item['id'],
        'category' => $item['category'],
        'caption' => $item['title'] ?? null,
        'thumb_url' => $item['thumb_url'],
        'medium_url' => $item['medium_url'],
        'large_url' => $item['large_url'],
        'is_cover' => $item['is_cover'],
    ], $photoItems);
    $coverPhotoLean = $coverItem !== null ? [
        'id' => $coverItem['id'],
        'thumb_url' => $coverItem['thumb_url'],
        'medium_url' => $coverItem['medium_url'],
        'large_url' => $coverItem['large_url'],
    ] : null;

    // Hizmetler: kategori bilgisiyle (service_categories join feature-detect).
    $hasSvcActive = mobile_table_has_column($pdo, 'services', 'is_active');
    $hasSvcCatId = mobile_table_has_column($pdo, 'services', 'category_id')
        && mobile_category_table_exists($pdo);
    $hasSvcCatText = mobile_table_has_column($pdo, 'services', 'category');
    $hasSvcDesc = mobile_table_has_column($pdo, 'services', 'description');

    $svcCategoryJoin = $hasSvcCatId
        ? 'LEFT JOIN service_categories sc ON sc.id = s.category_id'
        : '';
    $svcCategorySelect = $hasSvcCatId
        ? 's.category_id, sc.name AS category_resolved_name, sc.slug AS category_slug, sc.business_id AS category_owner'
        : 'NULL AS category_id, NULL AS category_resolved_name, NULL AS category_slug, NULL AS category_owner';
    $svcActiveCond = $hasSvcActive ? ' AND s.is_active = 1' : '';

    $servicesStmt = $pdo->prepare("
        SELECT s.id, s.name, s.duration_min, s.price,
               " . ($hasSvcDesc ? 's.description' : 'NULL') . " AS description,
               " . ($hasSvcCatText ? 's.category' : 'NULL') . " AS category_text,
               $svcCategorySelect
        FROM services s
        $svcCategoryJoin
        WHERE s.business_id = ?$svcActiveCond
        ORDER BY s.id ASC
    ");
    $servicesStmt->execute([$businessId]);

    $services = [];
    $servicesByCategory = [];
    foreach ($servicesStmt->fetchAll() as $row) {
        $isCustom = ($row['category_owner'] ?? null) !== null && (int)$row['category_owner'] > 0;
        $categoryName = $row['category_resolved_name'] ?? $row['category_text'] ?? null;
        $categorySlug = $row['category_slug'] ?? null;
        $categoryKey = ($row['category_id'] ?? null) !== null
            ? ($isCustom ? 'business_' . (int)$row['category_id'] : 'system_' . (int)$row['category_id'])
            : 'uncategorized';

        $serviceItem = [
            'id' => (string)$row['id'],
            'name' => (string)$row['name'],
            'duration_min' => (int)$row['duration_min'],
            'price' => $row['price'] !== null ? (float)$row['price'] : null,
            'description' => $row['description'] ?? null,
            'category_id' => ($row['category_id'] ?? null) !== null ? (int)$row['category_id'] : null,
            'category_name' => $categoryName,
            'category_slug' => $categorySlug,
            'is_custom_category' => $isCustom,
        ];
        $services[] = $serviceItem;

        if (!isset($servicesByCategory[$categoryKey])) {
            $servicesByCategory[$categoryKey] = [
                'id' => $categoryKey,
                'name' => $categoryName ?? 'Diğer Hizmetler',
                'slug' => $categorySlug,
                'is_custom' => $isCustom,
                'services' => [],
            ];
        }
        $servicesByCategory[$categoryKey]['services'][] = $serviceItem;
    }

    // "Diğer Hizmetler" grubu en sona alinir.
    $servicesByCategory = array_values($servicesByCategory);
    usort($servicesByCategory, static function (array $a, array $b): int {
        $aLast = $a['id'] === 'uncategorized' ? 1 : 0;
        $bLast = $b['id'] === 'uncategorized' ? 1 : 0;
        return $aLast <=> $bLast;
    });

    $hasReviewsForStaff = mobile_table_has_column($pdo, 'reviews', 'id');
    $hasReviewStaffForStaff = $hasReviewsForStaff && mobile_table_has_column($pdo, 'reviews', 'staff_id');
    $hasReviewStatusForStaff = $hasReviewsForStaff && mobile_table_has_column($pdo, 'reviews', 'status');
    $staffReviewStatusSql = $hasReviewStatusForStaff ? " AND r.status = 'active'" : '';
    $staffRatingSelect = $hasReviewStaffForStaff
        ? ", (SELECT ROUND(AVG(r.rating), 1) FROM reviews r WHERE r.business_id = staff.business_id AND r.staff_id = staff.id{$staffReviewStatusSql}) AS staff_rating"
        . ", (SELECT COUNT(*) FROM reviews r WHERE r.business_id = staff.business_id AND r.staff_id = staff.id{$staffReviewStatusSql}) AS staff_review_count"
        : ', NULL AS staff_rating, 0 AS staff_review_count';

    $hasStaffPhoto = mobile_table_has_column($pdo, 'staff', 'profile_photo_url');
    $staffPhotoSelect = $hasStaffPhoto
        ? ', profile_photo_url, profile_photo_updated_at'
        : ', NULL AS profile_photo_url, NULL AS profile_photo_updated_at';
    $staffStmt = $pdo->prepare("
        SELECT id, name, phone, color, is_active
               {$staffPhotoSelect}
               {$staffRatingSelect}
        FROM staff
        WHERE business_id = ? AND is_active = 1
        ORDER BY name ASC, id ASC
    ");
    $staffStmt->execute([$businessId]);
    $staff = array_map(static function (array $row): array {
        $photo = ($row['profile_photo_url'] ?? '') !== '' ? (string)$row['profile_photo_url'] : null;
        $photoVer = ($photo !== null && ($row['profile_photo_updated_at'] ?? null) !== null)
            ? (string)strtotime((string)$row['profile_photo_updated_at'])
            : null;
        return [
            'id' => (string)$row['id'],
            'name' => (string)$row['name'],
            'phone' => $row['phone'] ?? null,
            'color' => $row['color'] ?? null,
            'is_active' => (bool)$row['is_active'],
            'profile_photo_url' => $photo,
            'profile_photo_version' => $photoVer,
            'rating' => ($row['staff_rating'] ?? null) !== null ? (float)$row['staff_rating'] : null,
            'review_count' => (int)($row['staff_review_count'] ?? 0),
        ];
    }, $staffStmt->fetchAll());

    $hoursStmt = $pdo->prepare("
        SELECT day, is_open, open_time, close_time
        FROM business_hours
        WHERE business_id = ?
        ORDER BY FIELD(day, 'mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun')
    ");
    $hoursStmt->execute([$businessId]);
    $businessHours = array_map(static fn(array $row): array => [
        'day' => (string)$row['day'],
        'is_open' => (bool)$row['is_open'],
        'open_time' => !empty($row['open_time']) ? substr((string)$row['open_time'], 0, 5) : null,
        'close_time' => !empty($row['close_time']) ? substr((string)$row['close_time'], 0, 5) : null,
    ], $hoursStmt->fetchAll());

    $reviewSummary = [
        'rating' => null,
        'review_count' => 0,
    ];
    $reviews = [];
    if (mobile_table_has_column($pdo, 'reviews', 'id')) {
        $hasReviewStatusCol = mobile_table_has_column($pdo, 'reviews', 'status');
        $hasReviewStaffCol = mobile_table_has_column($pdo, 'reviews', 'staff_id');
        $reviewStatusSql = $hasReviewStatusCol ? " AND r.status = 'active'" : '';
        $businessReviewSql = $hasReviewStaffCol ? ' AND (r.staff_id IS NULL OR r.staff_id = 0)' : '';

        $summaryStmt = $pdo->prepare("
            SELECT AVG(r.rating) AS avg_rating, COUNT(*) AS review_count
            FROM reviews r
            WHERE r.business_id = ? {$reviewStatusSql} {$businessReviewSql}
        ");
        $summaryStmt->execute([$businessId]);
        $summaryRow = $summaryStmt->fetch() ?: [];
        $reviewCount = (int)($summaryRow['review_count'] ?? 0);
        $reviewSummary = [
            'rating' => $reviewCount > 0 ? round((float)$summaryRow['avg_rating'], 1) : null,
            'review_count' => $reviewCount,
        ];

        $staffSelect = $hasReviewStaffCol ? 'st.name AS staff_name' : 'NULL AS staff_name';
        $staffJoin = $hasReviewStaffCol ? 'LEFT JOIN staff st ON st.id = r.staff_id' : '';
        $reviewsStmt = $pdo->prepare("
            SELECT r.id, r.rating, r.comment, r.created_at,
                   COALESCE(NULLIF(a.customer_name, ''), NULLIF(u.name, ''), '') AS customer_name,
                   s.name AS service_name,
                   {$staffSelect}
            FROM reviews r
            LEFT JOIN appointments a ON a.id = r.appointment_id
            LEFT JOIN users u ON u.id = r.customer_user_id
            LEFT JOIN services s ON s.id = r.service_id
            {$staffJoin}
            WHERE r.business_id = ? {$reviewStatusSql} {$businessReviewSql}
            ORDER BY r.created_at DESC, r.id DESC
            LIMIT 12
        ");
        $reviewsStmt->execute([$businessId]);
        $reviews = array_map(static fn(array $row): array => [
            'id' => (string)$row['id'],
            'customer_name' => mobile_public_review_name($row['customer_name'] ?? null),
            'rating' => (int)$row['rating'],
            'comment' => $row['comment'] ?? null,
            'service_name' => $row['service_name'] ?? null,
            'staff_name' => $row['staff_name'] ?? null,
            'created_at' => $row['created_at'] ?? null,
        ], $reviewsStmt->fetchAll());
    }

    $salon = [
        'id' => (string)$biz['id'],
        'slug' => (string)($biz['slug'] ?? ''),
        'name' => (string)($biz['name'] ?? ''),
        'description' => $biz['about'] ?? null,
        'atelier_note' => $biz['atelier_note'] ?? null,
        'city' => $biz['city'] ?? null,
        'district' => $biz['district'] ?? null,
        'address' => $biz['address_line'] ?? null,
        'phone' => $biz['phone'] ?? null,
        'cover_image_url' => $coverUrl,
        'logo_url' => $images['logo_url'],
        'rating' => $reviewSummary['rating'],
        'review_count' => $reviewSummary['review_count'],
        'deposit_required' => $policyRequired,
        'deposit_amount'   => $fixedDepositAmount,
        'deposit_rate_pct' => $policyRate,
        'deposit_per_service' => $policyRow !== null ? (bool)($policyRow['per_service'] ?? false) : false,
        'deposit_calculation_mode' => $depositCalculationMode,
        'cancel_policy' => $policyRow['cancel_policy'] ?? null,
        'deposit_label' => $depositLabel,
        'category_slugs' => mobile_category_slugs_from_type($biz['type'] ?? null),
        'is_boosted' => $visibility['is_boosted'],
        'boost_badge' => $visibility['boost_badge'],
        'boost_ends_at' => $visibility['boost_ends_at'],
        'subscription_status' => $visibility['subscription_status'],
        'visibility_status' => $visibility['visibility_status'],
        'profile_quality_score' => $visibility['profile_quality_score'],
        'badges' => $visibility['is_boosted'] && $visibility['boost_badge'] !== null
            ? [(string)$visibility['boost_badge']]
            : [],
    ];

    // Aktif (şu an geçerli) vitrin kampanyası — yoksa null (Flutter bandı gizler).
    $activeCampaign = wb_campaign_display_for_business($pdo, (int)$businessId);

    // İptal politikası kısa özeti (müşteriye gösterim). Kapora kapalıysa net mesaj.
    $cancelPolicy = wb_cancellation_policy($pdo, (int)$businessId);
    $cancellationBlock = [
        'summary_lines' => wb_cancellation_summary_lines($cancelPolicy),
        'free_cancel_hours' => (int)$cancelPolicy['free_cancel_hours'],
        'late_cancel_enabled' => (bool)$cancelPolicy['late_cancel_enabled'],
        'late_cancel_rate_pct' => (int)$cancelPolicy['late_cancel_rate_pct'],
        'no_show_refund_pct' => wb_cancellation_no_show_refund_pct((string)$cancelPolicy['no_show_policy']),
        'deposit_required' => $policyRequired,
        'deposit_message' => $policyRequired
            ? null
            : 'Bu salon kapora almadan randevu kabul ediyor.',
    ];

    wb_ok([
        'salon' => $salon,
        'campaign' => $activeCampaign,
        'cancellation_policy' => $cancellationBlock,
        'gallery' => $gallery,
        'gallery_by_category' => $galleryByCategory,
        // Tek kaynakli galeri alanlari (business_photos, active+visible).
        // gallery_items: lean payload (original_url public'te donmez);
        // canlidaki onceki full-sema gallery_items alaninin yerini alir.
        'cover_photo' => $coverPhotoLean,
        'gallery_total' => count($galleryLean),
        'gallery_items' => $galleryLean,
        'services' => $services,
        'services_by_category' => $servicesByCategory,
        'staff' => $staff,
        'business_hours' => $businessHours,
        'reviews' => $reviews,
        'review_summary' => $reviewSummary,
        'deposit_policy' => (static function () use ($pdo, $businessId, $policyRequired, $fixedDepositAmount, $policyRate, $policyRow, $depositLabel, $depositDescription, $depositCalculationMode): array {
            $block = [
                'required' => $policyRequired,
                'amount' => $fixedDepositAmount,
                'rate_pct' => $policyRate,
                'per_service' => $policyRow !== null ? (bool)($policyRow['per_service'] ?? false) : false,
                'calculation_mode' => $depositCalculationMode,
                'cancel_policy' => $policyRow['cancel_policy'] ?? null,
                'label' => $depositLabel,
                'description' => $depositDescription,
                // Manuel IBAN kapora bilgileri — kapora gerekiyorsa booking onay
                // ekranında IBAN kartını randevu oluşmadan gösterebilmek için.
                'mode' => $policyRequired ? 'manual_iban' : null,
                'has_iban' => false,
                'iban' => null,
                'iban_formatted' => null,
                'account_holder' => null,
                'bank_name' => null,
                'instructions' => null,
            ];
            if ($policyRequired) {
                $ps = wb_business_payment_settings($pdo, $businessId);
                $block['has_iban'] = (bool)$ps['has_iban'];
                $block['iban'] = $ps['iban'];
                $block['iban_formatted'] = $ps['iban_formatted'];
                $block['account_holder'] = $ps['account_holder'];
                $block['bank_name'] = $ps['bank_name'];
                $block['instructions'] = $ps['instructions'];
            }
            return $block;
        })(),
        'location' => [
            'city' => $biz['city'] ?? null,
            'district' => $biz['district'] ?? null,
            'address' => $biz['address_line'] ?? null,
            'latitude' => $biz['latitude'] !== null ? (float)$biz['latitude'] : null,
            'longitude' => $biz['longitude'] !== null ? (float)$biz['longitude'] : null,
            'map_url' => $biz['map_url'] ?? null,
        ],
    ]);
} catch (Throwable $e) {
    error_log('[mobile/public/salon-detail.php] ' . $e->getMessage());
    wb_err('Salon detayı alınamadı', 500, 'internal_error');
}
