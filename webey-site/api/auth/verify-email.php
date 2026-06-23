<?php
// api/auth/verify-email.php — Email doğrulama token kontrolü
declare(strict_types=1);

// BUG FIX: _public_bootstrap kullan — email doğrulama giriş gerektirmez.
// Eski kod _bootstrap.php kullanıyordu, bu yüzden email linki her zaman 401 döndürüyordu.
require_once __DIR__ . '/../_public_bootstrap.php';

wb_method('GET', 'POST');
// BUG FIX: wb_csrf_verify çağrısı kaldırıldı — _public_bootstrap zaten çağırıyor (strict=false).

$method = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');
$data  = $method === 'POST' ? wb_body() : $_GET;
$token = trim((string)($data['token'] ?? ''));

if (!$token || strlen($token) < 32) {
    wb_err('Geçersiz token', 400, 'invalid_token');
}

try {
    $stmt = $pdo->prepare("
        SELECT id, email, email_verified_at
        FROM users
        WHERE email_verify_token = ?
          AND email_verify_sent_at > DATE_SUB(NOW(), INTERVAL 24 HOUR)
        LIMIT 1
    ");
    $stmt->execute([$token]);
    $user = $stmt->fetch();

    if (!$user) {
        wb_err('Bu doğrulama linki geçersiz veya süresi dolmuş', 410, 'token_expired');
    }

    if ($user['email_verified_at']) {
        wb_ok(['already' => true]);
    }

    $pdo->prepare("
        UPDATE users
        SET email_verified_at    = NOW(),
            email_verify_token   = NULL,
            email_verify_sent_at = NULL
        WHERE id = ?
    ")->execute([(int)$user['id']]);

    // Eğer bu bir email değiştirme isteğiyse yeni emaili uygula
    $newEmail = trim(strtolower((string)($data['new_email'] ?? '')));
    if ($newEmail && filter_var($newEmail, FILTER_VALIDATE_EMAIL)) {
        // Başka biri almış mı kontrol et
        $taken = $pdo->prepare("SELECT id FROM users WHERE email=? AND id != ? LIMIT 1");
        $taken->execute([$newEmail, (int)$user['id']]);
        if (!$taken->fetch()) {
            $pdo->prepare("UPDATE users SET email=? WHERE id=?")
                ->execute([$newEmail, (int)$user['id']]);
            // Session'ı güncelle
            if (isset($_SESSION['user_id']) && (int)$_SESSION['user_id'] === (int)$user['id']) {
                $_SESSION['email'] = $newEmail;
                $_SESSION['pending_email'] = null;
            }
        }
    }

    // Aktif session varsa güncelle
    if (isset($_SESSION['user_id']) && (int)$_SESSION['user_id'] === (int)$user['id']) {
        $_SESSION['email_verified'] = true;
    }

    wb_ok(['already' => false]);

} catch (Throwable $e) {
    error_log('[verify-email] ' . $e->getMessage());
    wb_err('Sunucu hatası, lütfen tekrar deneyin', 500, 'internal_error');
}
