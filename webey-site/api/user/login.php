<?php
declare(strict_types=1);
/**
 * api/user/login.php — Müşteri (end-user) girişi
 * ─────────────────────────────────────────────────
 * POST JSON: { email, password }
 * Döner:     { ok, data: { userId, phone, firstName, lastName } }
 */

require_once __DIR__ . '/../_public_bootstrap.php';
wb_method('POST');

// ── Brute-force koruması: IP başına 5 dakikada 10 deneme ──────────────────────
$remoteIp = trim((string)($_SERVER['REMOTE_ADDR'] ?? '0.0.0.0'));
$ip       = filter_var($remoteIp, FILTER_VALIDATE_IP) ? $remoteIp : '0.0.0.0';
$window   = 300;  // 5 dakika
$maxTries = 10;

try {
    $pdo->prepare('DELETE FROM login_attempts WHERE ip = ? AND attempted_at < DATE_SUB(NOW(), INTERVAL ? SECOND)')
        ->execute([$ip, $window]);
    $triesStmt = $pdo->prepare('SELECT COUNT(*) FROM login_attempts WHERE ip = ?');
    $triesStmt->execute([$ip]);
    if ((int)$triesStmt->fetchColumn() >= $maxTries) {
        wb_err('Çok fazla başarısız deneme. 5 dakika sonra tekrar dene.', 429, 'rate_limited');
    }
} catch (Throwable) { /* login_attempts tablosu yoksa devam et */ }
// ══════════════════════════════════════════════

$in    = wb_body();
$email = strtolower(trim((string)($in['email'] ?? '')));
$pass  = (string)($in['password'] ?? '');

wb_validate(['email' => $email, 'password' => $pass], [
    'email'    => ['required', 'email'],
    'password' => ['required'],
]);

try {
    $stmt = $pdo->prepare("
        SELECT u.id, u.password_hash, c.phone, c.first_name, c.last_name
        FROM   users u
        LEFT JOIN customers c ON c.user_id = u.id
        WHERE  (u.email = ? OR c.email = ?) AND u.role = 'user'
        LIMIT  1
    ");
    $stmt->execute([$email, $email]);
    $user = $stmt->fetch();

    if (!$user || !password_verify($pass, $user['password_hash'])) {
        try {
            $pdo->prepare('INSERT INTO login_attempts (ip, attempted_at) VALUES (?, NOW())')
                ->execute([$ip]);
        } catch (Throwable) {}
        wb_err('E-posta veya şifre hatalı', 401, 'invalid_credentials');
    }

    $userId = (int)$user['id'];

    // BUG FIX: Başarılı girişte bu IP'nin geçmiş başarısız denemelerini temizle
    // (admin/login.php'de zaten vardı, user/login.php'de eksikti)
    try {
        $pdo->prepare('DELETE FROM login_attempts WHERE ip = ?')->execute([$ip]);
    } catch (Throwable) {}

    // Son giriş zamanını güncelle
    $pdo->prepare('UPDATE users SET last_login_at = NOW() WHERE id = ?')
        ->execute([$userId]);

    // Session
    session_regenerate_id(true);
    $_SESSION['user_id']    = $userId;
    $_SESSION['user_role']  = 'user';
    $_SESSION['user_phone'] = (string)($user['phone'] ?? '');
    unset($_SESSION['admin_id'], $_SESSION['business_id']); // Admin session temizle

    wb_ok([
        'userId'    => (string)$userId,
        'phone'     => (string)($user['phone'] ?? ''),
        'firstName' => (string)($user['first_name'] ?? ''),
        'lastName'  => (string)($user['last_name']  ?? ''),
    ]);

} catch (Throwable $e) {
    error_log('[user/login.php] ' . $e->getMessage());
    wb_err('Giriş yapılamadı. Lütfen tekrar deneyin.', 500);
}
