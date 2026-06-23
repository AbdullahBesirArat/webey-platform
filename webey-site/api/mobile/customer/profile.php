<?php
declare(strict_types=1);

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';

wb_method('GET');

$session = mobile_auth($pdo, 'customer');
$userId  = $session['user_id'];

try {
    $hasAddressLine = mobile_table_has_column($pdo, 'customers', 'address_line');
    $hasLatitude = mobile_table_has_column($pdo, 'customers', 'latitude');
    $hasLongitude = mobile_table_has_column($pdo, 'customers', 'longitude');

    $stmt = $pdo->prepare("
        SELECT
            u.id,
            u.email,
            u.name AS display_name,
            u.avatar_url,
            u.created_at,
            u.last_login_at,
            c.first_name,
            c.last_name,
            c.phone,
            c.birthday,
            c.city,
            c.district,
            c.neighborhood,
            " . ($hasAddressLine ? 'c.address_line' : 'NULL') . " AS address_line,
            " . ($hasLatitude ? 'c.latitude' : 'NULL') . " AS latitude,
            " . ($hasLongitude ? 'c.longitude' : 'NULL') . " AS longitude,
            c.sms_ok,
            c.email_ok
        FROM users u
        LEFT JOIN customers c ON c.user_id = u.id
        WHERE u.id = ? AND u.role = 'user'
        LIMIT 1
    ");
    $stmt->execute([$userId]);
    $row = $stmt->fetch();

    if (!$row) {
        wb_err('Kullanıcı bulunamadı', 404, 'user_not_found');
    }

    $firstName = trim((string)($row['first_name'] ?? ''));
    $lastName  = trim((string)($row['last_name'] ?? ''));
    $fullName  = trim("$firstName $lastName");
    if ($fullName === '') {
        $fullName = trim((string)($row['display_name'] ?? ''));
    }

    $statsStmt = $pdo->prepare("
        SELECT
            COUNT(*) AS total,
            SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) AS completed,
            SUM(CASE WHEN status IN ('cancelled','cancellation_requested','rejected','declined') THEN 1 ELSE 0 END) AS cancelled
        FROM appointments
        WHERE customer_user_id = ?
    ");
    $statsStmt->execute([$userId]);
    $stats = $statsStmt->fetch() ?: [];

    wb_ok([
        'profile' => [
            'id'            => (string)$row['id'],
            'email'         => (string)($row['email'] ?? ''),
            'full_name'     => $fullName !== '' ? $fullName : null,
            'first_name'    => $firstName !== '' ? $firstName : null,
            'last_name'     => $lastName !== '' ? $lastName : null,
            'phone'         => $row['phone'] ?? null,
            'birthday'      => $row['birthday'] ?? null,
            'city'          => $row['city'] ?? null,
            'district'      => $row['district'] ?? null,
            'neighborhood'  => $row['neighborhood'] ?? null,
            'address_line'  => $row['address_line'] ?? null,
            'latitude'      => $row['latitude'] !== null ? (float)$row['latitude'] : null,
            'longitude'     => $row['longitude'] !== null ? (float)$row['longitude'] : null,
            'avatar_url'    => $row['avatar_url'] ?? null,
            'sms_ok'        => (bool)($row['sms_ok'] ?? true),
            'email_ok'      => (bool)($row['email_ok'] ?? false),
            'created_at'    => $row['created_at'] ?? null,
            'last_login_at' => $row['last_login_at'] ?? null,
            'stats'         => [
                'appointments_count' => (int)($stats['total'] ?? 0),
                'completed_count'    => (int)($stats['completed'] ?? 0),
                'cancelled_count'    => (int)($stats['cancelled'] ?? 0),
            ],
        ],
    ]);
} catch (Throwable $e) {
    error_log('[mobile/customer/profile.php] ' . $e->getMessage());
    wb_err('Profil alınamadı', 500, 'internal_error');
}
