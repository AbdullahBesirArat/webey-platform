<?php
declare(strict_types=1);
require_once __DIR__ . '/_bootstrap.php';
wb_method('POST');

$userId = $user['user_id'];
$in     = wb_body();

$firstName    = trim((string)($in['firstName']    ?? ''));
$lastName     = trim((string)($in['lastName']     ?? ''));
$birthday     = trim((string)($in['birthday']     ?? ''));
$city         = trim((string)($in['city']         ?? ''));
$district     = trim((string)($in['district']     ?? ''));
$neighborhood = trim((string)($in['neighborhood'] ?? ''));

try {
    $pdo->prepare("
        INSERT INTO customers (user_id, first_name, last_name, birthday, city, district, neighborhood)
        VALUES (?,?,?,?,?,?,?)
        ON DUPLICATE KEY UPDATE
            first_name    = VALUES(first_name),
            last_name     = VALUES(last_name),
            birthday      = VALUES(birthday),
            city          = VALUES(city),
            district      = VALUES(district),
            neighborhood  = VALUES(neighborhood),
            updated_at    = NOW()
    ")->execute([
        $userId,
        $firstName ?: null,
        $lastName  ?: null,
        ($birthday && preg_match('/^\d{4}-\d{2}-\d{2}$/', $birthday)) ? $birthday : null,
        $city ?: null, $district ?: null, $neighborhood ?: null,
    ]);

    wb_ok(['saved' => true]);

} catch (Throwable $e) {
    error_log('[user/update-profile.php] ' . $e->getMessage());
    wb_err('Profil güncellenemedi.', 500, 'internal_error');
}