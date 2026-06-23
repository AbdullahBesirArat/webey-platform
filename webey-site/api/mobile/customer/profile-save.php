<?php
declare(strict_types=1);

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';

wb_method('POST');

$session = mobile_auth($pdo, 'customer');
$userId  = $session['user_id'];
$in = wb_body();

function wb_customer_trim(?string $value, int $max): ?string
{
    $text = mb_substr(trim((string)$value), 0, $max);
    return $text !== '' ? $text : null;
}

function wb_customer_coord(mixed $value, float $min, float $max, string $label): ?float
{
    if ($value === null || $value === '') {
        return null;
    }
    if (!is_numeric($value)) {
        wb_err("$label geçersiz.", 422, 'invalid_location');
    }
    $coord = (float)$value;
    if ($coord < $min || $coord > $max) {
        wb_err("$label geçersiz.", 422, 'invalid_location');
    }
    return $coord;
}

$colMaxLen = [
    'first_name'   => 100,
    'last_name'    => 100,
    'phone'        => 30,
    'city'         => 80,
    'district'     => 80,
    'neighborhood' => 100,
    'address_line' => 500,
];

if (array_key_exists('phone', $in)) {
    $phoneRaw = wb_customer_trim((string)($in['phone'] ?? ''), 30);
    if ($phoneRaw !== null && !preg_match('/^[\+\d\s\-\(\)]{7,20}$/', $phoneRaw)) {
        wb_err('Telefon numarası geçersiz biçimde.', 422, 'invalid_phone');
    }
}

$hasAddressLine = mobile_table_has_column($pdo, 'customers', 'address_line');
$hasLatitude = mobile_table_has_column($pdo, 'customers', 'latitude');
$hasLongitude = mobile_table_has_column($pdo, 'customers', 'longitude');
$hasLocationUpdatedAt = mobile_table_has_column($pdo, 'customers', 'location_updated_at');

$fields = [];
foreach ($colMaxLen as $col => $max) {
    if (!array_key_exists($col, $in)) {
        continue;
    }
    if ($col === 'address_line' && !$hasAddressLine) {
        continue;
    }
    $fields[$col] = wb_customer_trim(isset($in[$col]) ? (string)$in[$col] : null, $max);
}

$latProvided = array_key_exists('latitude', $in);
$lngProvided = array_key_exists('longitude', $in);
$latitude = $latProvided ? wb_customer_coord($in['latitude'], -90, 90, 'Latitude') : null;
$longitude = $lngProvided ? wb_customer_coord($in['longitude'], -180, 180, 'Longitude') : null;

if (($latProvided || $lngProvided) && ($latitude === null || $longitude === null)) {
    wb_err('Latitude ve longitude birlikte gönderilmelidir.', 422, 'invalid_location');
}
if ($latitude !== null && $longitude !== null && abs($latitude) < 0.0000001 && abs($longitude) < 0.0000001) {
    wb_err('Geçerli bir konum gönderin.', 422, 'invalid_location');
}
if ($latitude !== null && $hasLatitude) {
    $fields['latitude'] = $latitude;
}
if ($longitude !== null && $hasLongitude) {
    $fields['longitude'] = $longitude;
}
if (($latitude !== null || $longitude !== null) && $hasLocationUpdatedAt) {
    $fields['location_updated_at'] = date('Y-m-d H:i:s');
}

try {
    $checkStmt = $pdo->prepare('SELECT id FROM customers WHERE user_id = ? LIMIT 1');
    $checkStmt->execute([$userId]);
    $existingId = $checkStmt->fetchColumn();

    if ($fields !== []) {
        if ($existingId !== false) {
            $setClauses = implode(', ', array_map(static fn($col) => "$col = ?", array_keys($fields)));
            $params = array_values($fields);
            $params[] = $userId;
            $pdo->prepare("UPDATE customers SET $setClauses WHERE user_id = ?")->execute($params);
        } else {
            $cols = implode(', ', array_keys($fields));
            $placeholders = implode(', ', array_fill(0, count($fields), '?'));
            $params = [$userId, ...array_values($fields)];
            $pdo->prepare("
                INSERT INTO customers (user_id, $cols)
                VALUES (?, $placeholders)
            ")->execute($params);
        }
    }

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
    $lastName = trim((string)($row['last_name'] ?? ''));
    $fullName = trim("$firstName $lastName");
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
    error_log('[mobile/customer/profile-save.php] ' . $e->getMessage());
    wb_err('Profil güncellenemedi', 500, 'internal_error');
}
