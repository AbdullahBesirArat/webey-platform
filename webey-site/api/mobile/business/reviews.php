<?php
declare(strict_types=1);
/**
 * api/mobile/business/reviews.php
 * GET — Business review summary and latest customer reviews.
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';
require_once __DIR__ . '/_helpers.php';

wb_method('GET');

$auth = mobile_auth($pdo, ['business', 'admin']);
$ctx = mobile_business_context($pdo, $auth);
$businessId = (int)$ctx['business_id'];
$limit = mobile_limit(mobile_param('limit', 30), 30, 100);

try {
    if (!mobile_table_has_column($pdo, 'reviews', 'id')) {
        wb_ok([
            'summary' => [
                'rating' => null,
                'review_count' => 0,
                'five_star_count' => 0,
                'latest_rating' => null,
            ],
            'items' => [],
        ]);
    }

    $hasStatusCol = mobile_table_has_column($pdo, 'reviews', 'status');
    $hasStaffCol = mobile_table_has_column($pdo, 'reviews', 'staff_id');
    $hasReplyCol = mobile_table_has_column($pdo, 'reviews', 'business_reply');
    $statusSql = $hasStatusCol ? " AND r.status = 'active'" : '';
    $businessReviewSql = $hasStaffCol ? ' AND (r.staff_id IS NULL OR r.staff_id = 0)' : '';
    $replySelect = $hasReplyCol
        ? 'r.business_reply, r.business_reply_at, r.business_liked, r.business_liked_at'
        : "NULL AS business_reply, NULL AS business_reply_at, 0 AS business_liked, NULL AS business_liked_at";

    $summaryStmt = $pdo->prepare("
        SELECT
            AVG(r.rating) AS avg_rating,
            COUNT(*) AS review_count,
            SUM(CASE WHEN r.rating = 5 THEN 1 ELSE 0 END) AS five_star_count
        FROM reviews r
        WHERE r.business_id = ? {$statusSql} {$businessReviewSql}
    ");
    $summaryStmt->execute([$businessId]);
    $summary = $summaryStmt->fetch() ?: [];

    $latestStmt = $pdo->prepare("
        SELECT r.rating
        FROM reviews r
        WHERE r.business_id = ? {$statusSql} {$businessReviewSql}
        ORDER BY r.created_at DESC, r.id DESC
        LIMIT 1
    ");
    $latestStmt->execute([$businessId]);
    $latestRating = $latestStmt->fetchColumn();

    $staffSelect = $hasStaffCol ? 'r.staff_id, st.name AS staff_name' : 'NULL AS staff_id, NULL AS staff_name';
    $staffJoin = $hasStaffCol ? 'LEFT JOIN staff st ON st.id = r.staff_id' : '';
    $itemsStmt = $pdo->prepare("
        SELECT r.id, r.appointment_id, r.customer_user_id, r.rating, r.comment, r.created_at,
               {$replySelect},
               COALESCE(NULLIF(a.customer_name, ''), NULLIF(u.name, ''), 'Müşteri') AS customer_name,
               s.name AS service_name,
               {$staffSelect}
        FROM reviews r
        LEFT JOIN appointments a ON a.id = r.appointment_id
        LEFT JOIN users u ON u.id = r.customer_user_id
        LEFT JOIN services s ON s.id = r.service_id
        {$staffJoin}
        WHERE r.business_id = ? {$statusSql}
        ORDER BY r.created_at DESC, r.id DESC
        LIMIT ?
    ");
    $itemsStmt->bindValue(1, $businessId, PDO::PARAM_INT);
    $itemsStmt->bindValue(2, $limit, PDO::PARAM_INT);
    $itemsStmt->execute();

    $items = array_map(static fn(array $row): array => [
        'id' => (string)$row['id'],
        'appointment_id' => $row['appointment_id'] !== null ? (string)$row['appointment_id'] : null,
        'customer_user_id' => $row['customer_user_id'] !== null ? (string)$row['customer_user_id'] : null,
        'customer_name' => (string)($row['customer_name'] ?? 'Müşteri'),
        'rating' => (int)$row['rating'],
        'comment' => $row['comment'] ?? null,
        'service_name' => $row['service_name'] ?? null,
        'staff_id' => $row['staff_id'] !== null ? (string)$row['staff_id'] : null,
        'staff_name' => $row['staff_name'] ?? null,
        'target_type' => !empty($row['staff_id']) ? 'staff' : 'business',
        'created_at' => $row['created_at'] ?? null,
        'business_reply' => $row['business_reply'] ?? null,
        'business_reply_at' => $row['business_reply_at'] ?? null,
        'business_liked' => (bool)($row['business_liked'] ?? false),
    ], $itemsStmt->fetchAll() ?: []);

    $reviewCount = (int)($summary['review_count'] ?? 0);
    wb_ok([
        'summary' => [
            'rating' => $reviewCount > 0 ? round((float)$summary['avg_rating'], 1) : null,
            'review_count' => $reviewCount,
            'five_star_count' => (int)($summary['five_star_count'] ?? 0),
            'latest_rating' => $latestRating !== false ? (int)$latestRating : null,
        ],
        'items' => $items,
    ]);
} catch (Throwable $e) {
    error_log('[mobile/business/reviews.php] ' . $e->getMessage());
    wb_err('Yorumlar alınamadı', 500, 'internal_error');
}
