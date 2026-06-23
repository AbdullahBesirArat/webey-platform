<?php
// api/auth/check-email.php — Email kullanımda mı?
declare(strict_types=1);

require_once __DIR__ . '/../_public_bootstrap.php';

wb_method('POST');

$data  = wb_body();
$email = strtolower(trim((string)($data['email'] ?? '')));

if (!$email || !filter_var($email, FILTER_VALIDATE_EMAIL)) {
    wb_err('Geçerli bir email adresi girin', 400, 'invalid_email');
}

try {
    $stmt = $pdo->prepare("
        SELECT u.id
        FROM users u
        LEFT JOIN customers c ON c.user_id = u.id
        WHERE u.email = ? OR c.email = ?
        LIMIT 1
    ");
    $stmt->execute([$email, $email]);
    $exists = (bool)$stmt->fetchColumn();

    wb_ok([
        'available' => !$exists,
        'exists'    => $exists,
    ]);

} catch (Throwable $e) {
    error_log('[check-email] ' . $e->getMessage());
    wb_err('Sunucu hatası', 500, 'internal_error');
}
