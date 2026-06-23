<?php
declare(strict_types=1);
/**
 * api/superadmin/app/dashboard.php
 * GET — App Verileri genel dashboard sayaçları. READ-ONLY.
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/_helpers.php';
wb_method('GET');

try {
    $i = static fn(mixed $v): int => (int)$v;

    // ── Müşteri / işletme sayıları ──
    $totalCustomers  = $i(sa_val($pdo, "SELECT COUNT(*) FROM users WHERE role='user'"));
    $totalBusinesses = $i(sa_val($pdo, "SELECT COUNT(*) FROM businesses"));
    $published       = $i(sa_val($pdo, "SELECT COUNT(*) FROM businesses WHERE status='active'"));
    $onbIncomplete   = $i(sa_val($pdo, "SELECT COUNT(*) FROM businesses WHERE onboarding_completed=0"));
    $noLocation      = $i(sa_val($pdo, "SELECT COUNT(*) FROM businesses WHERE latitude IS NULL OR longitude IS NULL"));
    $noCover         = $i(sa_val($pdo, "SELECT COUNT(*) FROM businesses b WHERE NOT EXISTS (
                            SELECT 1 FROM business_photos p
                            WHERE p.business_id=b.id AND p.is_cover=1 AND p.status='active')"));
    $noServices      = $i(sa_val($pdo, "SELECT COUNT(*) FROM businesses b WHERE NOT EXISTS (
                            SELECT 1 FROM services s WHERE s.business_id=b.id)"));
    $noPhotos        = $i(sa_val($pdo, "SELECT COUNT(*) FROM businesses b WHERE NOT EXISTS (
                            SELECT 1 FROM business_photos p
                            WHERE p.business_id=b.id AND p.status='active')"));

    // ── Randevular ──
    $appt = sa_row($pdo, "SELECT
            COUNT(*)                                            AS total,
            COALESCE(SUM(DATE(start_at)=CURDATE()),0)           AS today,
            COALESCE(SUM(status='pending'),0)                   AS pending,
            COALESCE(SUM(status='approved'),0)                  AS approved,
            COALESCE(SUM(status IN ('cancelled','rejected','declined','cancellation_requested')),0) AS cancelled,
            COALESCE(SUM(deposit_required=1 AND (deposit_status IS NULL OR deposit_status='pending')),0) AS deposit_pending,
            COALESCE(SUM(deposit_status='customer_marked_sent'),0) AS deposit_customer_marked_sent
        FROM appointments") ?? [];

    // ── Galeri / yorum / bildirim / boost ──
    $totalPhotos    = $i(sa_val($pdo, "SELECT COUNT(*) FROM business_photos WHERE status='active'"));
    $totalReviews   = $i(sa_val($pdo, "SELECT COUNT(*) FROM reviews"));
    $unreadNotifs   = $i(sa_val($pdo, "SELECT COUNT(*) FROM notifications WHERE is_read=0 AND is_deleted=0"))
                    + $i(sa_val($pdo, "SELECT COUNT(*) FROM user_notifications WHERE is_read=0"));
    $boostActive    = $i(sa_val($pdo, "SELECT COUNT(*) FROM business_boost_subscriptions
                                        WHERE status='active' AND (ends_at IS NULL OR ends_at >= NOW())"));
    $boostPending   = $i(sa_val($pdo, "SELECT COUNT(*) FROM business_boost_requests WHERE status='pending'"));

    // ── Son 7 gün ──
    $last7 = [
        'new_customers'    => $i(sa_val($pdo, "SELECT COUNT(*) FROM users
                                WHERE role='user' AND created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)")),
        'new_businesses'   => $i(sa_val($pdo, "SELECT COUNT(*) FROM businesses
                                WHERE created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)")),
        'new_appointments' => $i(sa_val($pdo, "SELECT COUNT(*) FROM appointments
                                WHERE created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)")),
    ];

    wb_ok([
        'total_customers'                    => $totalCustomers,
        'total_businesses'                   => $totalBusinesses,
        'published_businesses'               => $published,
        'onboarding_incomplete_businesses'   => $onbIncomplete,
        'businesses_missing_location'        => $noLocation,
        'businesses_missing_cover'           => $noCover,
        'businesses_without_services'        => $noServices,
        'businesses_without_photos'          => $noPhotos,
        'total_appointments'                 => $i($appt['total'] ?? 0),
        'today_appointments'                 => $i($appt['today'] ?? 0),
        'pending_appointments'               => $i($appt['pending'] ?? 0),
        'approved_appointments'              => $i($appt['approved'] ?? 0),
        'cancelled_appointments'             => $i($appt['cancelled'] ?? 0),
        'deposit_pending_appointments'       => $i($appt['deposit_pending'] ?? 0),
        'deposit_customer_marked_sent'       => $i($appt['deposit_customer_marked_sent'] ?? 0),
        'total_photos'                       => $totalPhotos,
        'total_reviews'                      => $totalReviews,
        'unread_notifications'               => $unreadNotifs,
        'boost_active_count'                 => $boostActive,
        'boost_pending_requests'             => $boostPending,
        'last_7_days'                        => $last7,
    ]);

} catch (Throwable $e) {
    error_log('[superadmin/app/dashboard] ' . $e->getMessage());
    wb_err('Dashboard verileri yüklenemedi', 500, 'internal_error');
}
