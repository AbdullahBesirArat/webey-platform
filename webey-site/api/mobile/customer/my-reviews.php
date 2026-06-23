<?php
declare(strict_types=1);
/**
 * api/mobile/customer/my-reviews.php
 * GET - Token sahibi müşterinin kendi yorumları.
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';

wb_method('GET');

$session = mobile_auth($pdo, 'customer');
$userId = (int)$session['user_id'];

try {
    if (!mobile_table_has_column($pdo, 'reviews', 'id')) {
        wb_ok(['items' => []]);
    }

    $hasStatusCol = mobile_table_has_column($pdo, 'reviews', 'status');
    $hasStaffCol = mobile_table_has_column($pdo, 'reviews', 'staff_id');
    $statusSql = $hasStatusCol ? " AND r.status = 'active'" : '';
    $staffSelect = $hasStaffCol ? 'r.staff_id, st.name AS staff_name' : 'NULL AS staff_id, NULL AS staff_name';
    $staffJoin = $hasStaffCol ? 'LEFT JOIN staff st ON st.id = r.staff_id AND st.business_id = r.business_id' : '';

    $stmt = $pdo->prepare("
        SELECT r.id, r.appointment_id, r.business_id, r.service_id, r.rating,
               r.comment, r.created_at,
               b.slug AS business_slug,
               b.name AS business_name,
               b.city AS business_city,
               b.district AS business_district,
               s.name AS service_name,
               {$staffSelect}
        FROM reviews r
        INNER JOIN businesses b ON b.id = r.business_id
        LEFT JOIN services s ON s.id = r.service_id
        {$staffJoin}
        WHERE r.customer_user_id = ? {$statusSql}
        ORDER BY r.created_at DESC, r.id DESC
        LIMIT 100
    ");
    $stmt->execute([$userId]);

    $items = array_map(static fn(array $row): array => [
        'id' => (string)$row['id'],
        'appointment_id' => $row['appointment_id'] !== null ? (string)$row['appointment_id'] : null,
        'business_id' => (string)$row['business_id'],
        'business_slug' => (string)($row['business_slug'] ?? ''),
        'business_name' => (string)($row['business_name'] ?? ''),
        'business_city' => $row['business_city'] ?? null,
        'business_district' => $row['business_district'] ?? null,
        'service_id' => $row['service_id'] !== null ? (string)$row['service_id'] : null,
        'service_name' => $row['service_name'] ?? null,
        'staff_id' => $row['staff_id'] !== null ? (string)$row['staff_id'] : null,
        'staff_name' => $row['staff_name'] ?? null,
        'target_type' => !empty($row['staff_id']) ? 'staff' : 'business',
        'rating' => (int)$row['rating'],
        'comment' => $row['comment'] ?? null,
        'created_at' => $row['created_at'] ?? null,
    ], $stmt->fetchAll() ?: []);

    wb_ok(['items' => $items]);
} catch (Throwable $e) {
    error_log('[mobile/customer/my-reviews.php] ' . $e->getMessage());
    wb_err('Yorumlarınız alınamadı', 500, 'internal_error');
}
