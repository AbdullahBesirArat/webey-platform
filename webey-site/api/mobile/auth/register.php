<?php
declare(strict_types=1);

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';
require_once __DIR__ . '/../_email_otp.php';

wb_method('POST');

$body = wb_body();
$name = trim((string)($body['name'] ?? ''));
$email = strtolower(trim((string)($body['email'] ?? '')));
$phone = preg_replace('/\D+/', '', (string)($body['phone'] ?? ''));
$password = (string)($body['password'] ?? '');

if (str_starts_with($phone, '90') && strlen($phone) === 12) {
    $phone = substr($phone, 2);
}
if (str_starts_with($phone, '0')) {
    $phone = substr($phone, 1);
}

if ($name === '') {
    wb_err('Ad soyad zorunlu', 422, 'validation_error');
}
if ($email === '' || !filter_var($email, FILTER_VALIDATE_EMAIL)) {
    wb_err('Geçerli bir e-posta adresi girin', 422, 'validation_error');
}
if (mb_strlen($password) < 8) {
    wb_err('Şifre en az 8 karakter olmalı', 422, 'validation_error');
}
if ($phone !== '' && !preg_match('/^5\d{9}$/', $phone)) {
    wb_err('Geçerli bir telefon numarası girin', 422, 'validation_error');
}

// OTP-gated register: e-posta, hesap oluşturulmadan önce doğrulanmış olmalı.
if (!mobile_email_otp_recently_verified($pdo, $email, 'register')) {
    wb_err('E-posta adresinizi doğrulayın. Lütfen önce doğrulama kodunu girin.', 403, 'email_not_verified');
}

function wb_register_trim(mixed $value, int $max): ?string
{
    $text = mb_substr(trim((string)($value ?? '')), 0, $max);
    return $text !== '' ? $text : null;
}

function wb_register_coord(mixed $value, float $min, float $max, string $label): ?float
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

$city = wb_register_trim($body['city'] ?? null, 80);
$district = wb_register_trim($body['district'] ?? null, 80);
$neighborhood = wb_register_trim($body['neighborhood'] ?? null, 100);
$addressLine = wb_register_trim($body['address_line'] ?? null, 500);
$latProvided = array_key_exists('latitude', $body);
$lngProvided = array_key_exists('longitude', $body);
$latitude = $latProvided ? wb_register_coord($body['latitude'], -90, 90, 'Latitude') : null;
$longitude = $lngProvided ? wb_register_coord($body['longitude'], -180, 180, 'Longitude') : null;

if (($latProvided || $lngProvided) && ($latitude === null || $longitude === null)) {
    wb_err('Latitude ve longitude birlikte gönderilmelidir.', 422, 'invalid_location');
}
if ($latitude !== null && $longitude !== null && abs($latitude) < 0.0000001 && abs($longitude) < 0.0000001) {
    wb_err('Geçerli bir konum gönderin.', 422, 'invalid_location');
}

$hasAddressLine = mobile_table_has_column($pdo, 'customers', 'address_line');
$hasLatitude = mobile_table_has_column($pdo, 'customers', 'latitude');
$hasLongitude = mobile_table_has_column($pdo, 'customers', 'longitude');
$hasLocationUpdatedAt = mobile_table_has_column($pdo, 'customers', 'location_updated_at');

$parts = preg_split('/\s+/u', $name, 2) ?: [];
$firstName = trim((string)($parts[0] ?? ''));
$lastName = trim((string)($parts[1] ?? ''));

try {
    $pdo->beginTransaction();

    $emailStmt = $pdo->prepare("
        SELECT u.id
        FROM users u
        LEFT JOIN customers c ON c.user_id = u.id
        WHERE u.email = ? OR c.email = ?
        LIMIT 1
        FOR UPDATE
    ");
    $emailStmt->execute([$email, $email]);
    if ($emailStmt->fetchColumn()) {
        $pdo->rollBack();
        wb_err('Bu e-posta adresi zaten kayıtlı', 409, 'email_exists');
    }

    if ($phone !== '') {
        $phoneStmt = $pdo->prepare('SELECT user_id FROM customers WHERE phone = ? LIMIT 1 FOR UPDATE');
        $phoneStmt->execute([$phone]);
        if ($phoneStmt->fetchColumn()) {
            $pdo->rollBack();
            wb_err('Bu telefon numarası zaten kayıtlı', 409, 'phone_exists');
        }
    }

    $hash = password_hash($password, PASSWORD_BCRYPT, ['cost' => 11]);
    $pdo->prepare("
        INSERT INTO users (email, name, password_hash, role, email_verified_at, created_at)
        VALUES (?, ?, ?, 'user', NOW(), NOW())
    ")->execute([$email, $name, $hash]);
    $userId = (int)$pdo->lastInsertId();

    $columns = ['user_id', 'first_name', 'last_name', 'phone', 'email', 'city', 'district', 'neighborhood', 'email_ok', 'sms_ok', 'created_at'];
    $values = [$userId, $firstName ?: null, $lastName ?: null, $phone ?: null, $email, $city, $district, $neighborhood, 0, 1, date('Y-m-d H:i:s')];

    if ($hasAddressLine) {
        $columns[] = 'address_line';
        $values[] = $addressLine;
    }
    if ($hasLatitude) {
        $columns[] = 'latitude';
        $values[] = $latitude;
    }
    if ($hasLongitude) {
        $columns[] = 'longitude';
        $values[] = $longitude;
    }
    if (($latitude !== null || $longitude !== null) && $hasLocationUpdatedAt) {
        $columns[] = 'location_updated_at';
        $values[] = date('Y-m-d H:i:s');
    }

    $placeholders = implode(', ', array_fill(0, count($columns), '?'));
    $columnSql = implode(', ', $columns);
    $pdo->prepare("
        INSERT INTO customers ($columnSql)
        VALUES ($placeholders)
    ")->execute($values);

    $pdo->commit();

    // Kullanılan kayıt OTP'sini tüket (tekrar kullanılamasın).
    mobile_email_otp_consume($pdo, $email, 'register');

    $session = mobile_create_session($pdo, 'customer', $userId, $body);
    $payload = mobile_user_payload($pdo, 'customer', $userId);

    wb_ok([
        'token' => $session['token'],
        'token_type' => $session['token_type'],
        'expires_in' => $session['expires_in'],
        'user' => $payload,
    ], 201);
} catch (Throwable $e) {
    if (isset($pdo) && $pdo->inTransaction()) {
        $pdo->rollBack();
    }
    if ($e->getCode() === '23000' || str_contains($e->getMessage(), 'Duplicate entry')) {
        wb_err('Bu e-posta veya telefon zaten kayıtlı', 409, 'duplicate_account');
    }
    error_log('[mobile/auth/register.php] ' . $e->getMessage());
    wb_err('Kayıt başarısız. Lütfen tekrar deneyin.', 500, 'internal_error');
}
