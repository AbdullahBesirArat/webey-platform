<?php
declare(strict_types=1);
require_once __DIR__ . '/_bootstrap.php';
wb_method('POST');

$userId = $user['user_id'];
$in     = wb_body();

$profile   = $in['profile']   ?? [];
$address   = $in['address']   ?? [];
$marketing = $in['marketing'] ?? [];

$firstName    = trim((string)($profile['firstName'] ?? ''));
$lastName     = trim((string)($profile['lastName']  ?? ''));
$birthday     = trim((string)($profile['birthday']  ?? ''));
$city         = trim((string)($address['city']         ?? ''));
$district     = trim((string)($address['district']     ?? ''));
$neighborhood = trim((string)($address['neighborhood'] ?? ''));
$smsOk        = (bool)($marketing['sms']   ?? true);
$emailOk      = (bool)($marketing['email'] ?? false);

try {
    $stmt = $pdo->prepare("SELECT id FROM customers WHERE user_id = ? LIMIT 1");
    $stmt->execute([$userId]);
    $existing = $stmt->fetchColumn();

    if ($existing) {
        $pdo->prepare("
            UPDATE customers SET
                first_name    = ?,
                last_name     = ?,
                birthday      = ?,
                city          = ?,
                district      = ?,
                neighborhood  = ?,
                sms_ok        = ?,
                email_ok      = ?
            WHERE user_id = ?
        ")->execute([
            $firstName ?: null,
            $lastName  ?: null,
            ($birthday && preg_match('/^\d{4}-\d{2}-\d{2}$/', $birthday)) ? $birthday : null,
            $city ?: null, $district ?: null, $neighborhood ?: null,
            $smsOk ? 1 : 0, $emailOk ? 1 : 0,
            $userId,
        ]);
        $mode = 'updated';
    } else {
        $pdo->prepare("
            INSERT INTO customers (user_id, first_name, last_name, birthday, city, district, neighborhood, sms_ok, email_ok)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ")->execute([
            $userId,
            $firstName ?: null,
            $lastName  ?: null,
            ($birthday && preg_match('/^\d{4}-\d{2}-\d{2}$/', $birthday)) ? $birthday : null,
            $city ?: null, $district ?: null, $neighborhood ?: null,
            $smsOk ? 1 : 0, $emailOk ? 1 : 0,
        ]);
        $mode = 'created';
    }

    wb_ok(['mode' => $mode]);

} catch (Throwable $e) {
    error_log('[user/completeSignup.php] ' . $e->getMessage());
    wb_err('Profil güncellenemedi. Lütfen tekrar deneyin.', 500, 'internal_error');
}