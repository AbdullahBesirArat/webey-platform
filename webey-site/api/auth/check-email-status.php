<?php
// api/auth/check-email-status.php — Oturumun email doğrulama durumu
// Hem admin hem user session destekler
declare(strict_types=1);

require_once __DIR__ . '/../_bootstrap.php';

wb_method('GET');

$sess = wb_auth();   // user_id zorunlu, admin veya user fark yok

try {
    $stmt = $pdo->prepare("SELECT email, email_verified_at FROM users WHERE id = ? LIMIT 1");
    $stmt->execute([$sess['user_id']]);
    $row = $stmt->fetch();

    if (!$row) {
        wb_err('Kullanıcı bulunamadı', 404, 'not_found');
    }

    wb_ok([
        'email'         => $row['email'] ?? '',
        'emailVerified' => !empty($row['email_verified_at']),
    ]);

} catch (Throwable $e) {
    error_log('[check-email-status] ' . $e->getMessage());
    wb_err('Sunucu hatası', 500, 'internal_error');
}