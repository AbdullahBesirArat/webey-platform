<?php
declare(strict_types=1);
/**
 * api/auth/login.php — Admin / İşletme sahibi girişi
 * ────────────────────────────────────────────────────
 * POST JSON: { email, password }
 * Döner:     { ok, data: { user, hasBusiness, businessId } }
 */

require_once __DIR__ . '/../_public_bootstrap.php';

wb_method('POST');

// ══════════════════════════════════════════════
// BRUTE-FORCE KORUMASI — IP başına 5 dakikada 10 deneme
// BUG FIX: try-catch içine alındı — login_attempts tablosu yoksa (migration 002
//           henüz uygulanmamışsa) login tamamen kırılmasın diye.
// BUG FIX: IP extraction user/login.php ile tutarlı hale getirildi.
// ══════════════════════════════════════════════
$remoteIp = trim((string)($_SERVER['REMOTE_ADDR'] ?? '0.0.0.0'));
$ip       = filter_var($remoteIp, FILTER_VALIDATE_IP) ? $remoteIp : '0.0.0.0';
$window   = 300;  // 5 dakika (saniye)
$maxTries = 10;

try {
    // Süresi dolmuş denemeleri temizle
    $pdo->prepare('DELETE FROM login_attempts WHERE ip = ? AND attempted_at < DATE_SUB(NOW(), INTERVAL ? SECOND)')
        ->execute([$ip, $window]);

    // Mevcut deneme sayısını kontrol et
    $stmt = $pdo->prepare('SELECT COUNT(*) FROM login_attempts WHERE ip = ?');
    $stmt->execute([$ip]);
    if ((int)$stmt->fetchColumn() >= $maxTries) {
        wb_err('Çok fazla başarısız deneme. 5 dakika sonra tekrar dene.', 429, 'rate_limited');
    }
} catch (Throwable) { /* login_attempts tablosu yoksa devam et */ }
// ══════════════════════════════════════════════

$data     = wb_body();
$email    = strtolower(trim($data['email']    ?? ''));
$password = (string)($data['password'] ?? '');

if ($email === '' || !filter_var($email, FILTER_VALIDATE_EMAIL)) {
    wb_err('Geçerli bir email adresi girin', 400);
}
if ($password === '') {
    wb_err('Şifre zorunludur', 400);
}

try {
    $stmt = $pdo->prepare('
        SELECT id, email, password_hash, email_verified_at
        FROM   users
        WHERE  email = ?
        LIMIT  1
    ');
    $stmt->execute([$email]);
    $user = $stmt->fetch();

    if (!$user || !password_verify($password, $user['password_hash'])) {
        // Başarısız denemeyi kaydet
        try {
            $pdo->prepare('INSERT INTO login_attempts (ip, attempted_at) VALUES (?, NOW())')
                ->execute([$ip]);
        } catch (Throwable) {}
        wb_err('Email veya şifre hatalı', 401, 'invalid_credentials');
    }

    $userId = (int)$user['id'];

    // Başarılı girişte bu IP'nin geçmiş başarısız denemelerini temizle
    try {
        $pdo->prepare('DELETE FROM login_attempts WHERE ip = ?')->execute([$ip]);
    } catch (Throwable) {}

    // Admin kaydını al
    $stmt = $pdo->prepare('SELECT id FROM admin_users WHERE user_id = ? LIMIT 1');
    $stmt->execute([$userId]);
    $admin = $stmt->fetch();

    $stmt = $pdo->prepare('SELECT id, role FROM users WHERE id=? LIMIT 1');
    $stmt->execute([$userId]);
    $userRole = $stmt->fetch();
    $role = $userRole['role'] ?? 'admin';

    // Son giriş zamanını güncelle
    $pdo->prepare('UPDATE users SET last_login_at = NOW() WHERE id = ?')
        ->execute([$userId]);

    // Session
    session_regenerate_id(true);
    $_SESSION['user_id']    = $userId;
    $_SESSION['user_role']  = $role; // superadmin için de set et
    $_SESSION['admin_id']   = $admin ? (int)$admin['id'] : null;
    $_SESSION['email']      = $user['email'];

    // Superadmin ise direkt yönlendir
    if ($role === 'superadmin') {
        wb_ok([
            'user'       => ['id' => (string)$userId, 'email' => $user['email']],
            'role'       => 'superadmin',
            'redirect'   => 'superadmin.html',
        ]);
    }

    unset($_SESSION['user_role']); // Normal admin için müşteri session'ını temizle

    // İşletme var mı?
    $stmt = $pdo->prepare('SELECT id FROM businesses WHERE owner_id = ? LIMIT 1');
    $stmt->execute([$userId]);
    $business = $stmt->fetch();

    if ($business) {
        $_SESSION['business_id'] = (int)$business['id'];
    } else {
        unset($_SESSION['business_id']);
    }

    wb_ok([
        'user'        => ['id' => (string)$userId, 'email' => $user['email']],
        'hasBusiness' => (bool)$business,
        'businessId'  => $business ? (string)$business['id'] : null,
    ]);

} catch (Throwable $e) {
    error_log('[auth/login.php] ' . $e->getMessage());
    wb_err('Giriş yapılamadı. Lütfen tekrar deneyin.', 500);
}
