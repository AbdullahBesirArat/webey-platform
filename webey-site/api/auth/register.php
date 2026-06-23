<?php
declare(strict_types=1);
/**
 * api/auth/register.php — Admin / İşletme sahibi kaydı
 * ──────────────────────────────────────────────────────
 * POST JSON: { email, password }
 * Döner:     { ok, data: { user_id, admin_id, email_sent } }
 */

require_once __DIR__ . '/../_public_bootstrap.php';
require_once __DIR__ . '/../_google_auth.php';
require_once __DIR__ . '/../_mailer.php';
require_once __DIR__ . '/../_email_templates.php';
require_once __DIR__ . '/../_email_templates_auth.php';

wb_method('POST');

$data     = wb_body();
$email    = strtolower(trim($data['email']    ?? ''));
$password = (string)($data['password'] ?? '');
$googleCredential = trim((string)($data['googleCredential'] ?? ''));
$googleIdentity = null;

if (!$email || !filter_var($email, FILTER_VALIDATE_EMAIL)) {
    wb_err('Geçerli bir email adresi girin', 400);
}
if (!$password || mb_strlen($password) < 8) {
    wb_err('Şifre en az 8 karakter olmalıdır', 400);
}
if ($googleCredential !== '') {
    $googleIdentity = wb_google_extract_identity($googleCredential);
    if (!$googleIdentity || (string)$googleIdentity['email'] !== $email) {
        wb_err('Google doğrulaması geçersiz. Lütfen tekrar deneyin.', 422, 'google_verification_required');
    }
}

try {
    $pdo->beginTransaction();

    // Email kontrolü
    $stmt = $pdo->prepare('SELECT id FROM users WHERE email = ? LIMIT 1');
    $stmt->execute([$email]);
    if ($stmt->fetchColumn()) {
        $pdo->rollBack();
        wb_err('Bu email adresi zaten kayıtlı', 409, 'email_taken');
    }

    $hash        = password_hash($password, PASSWORD_BCRYPT, ['cost' => 11]);
    $verifyToken = $googleIdentity ? null : bin2hex(random_bytes(32));

    // Kullanıcı kaydet
    $stmt = $pdo->prepare("
        INSERT INTO users (google_id, email, name, avatar_url, password_hash, role, email_verify_token, email_verify_sent_at, email_verified_at, created_at)
        VALUES (?, ?, ?, ?, ?, 'admin', ?, ?, ?, NOW())
    ");
    $stmt->execute([
        $googleIdentity['google_id'] ?? null,
        $email,
        $googleIdentity['full_name'] ?? null,
        $googleIdentity['avatar'] ?? null,
        $hash,
        $verifyToken,
        $googleIdentity ? null : date('Y-m-d H:i:s'),
        $googleIdentity ? date('Y-m-d H:i:s') : null,
    ]);
    $userId = (int)$pdo->lastInsertId();

    if (!$userId) {
        throw new Exception('User insert failed');
    }

    // Admin kaydı
    $stmt = $pdo->prepare('
        INSERT INTO admin_users (user_id, onboarding_completed, created_at)
        VALUES (?, 0, NOW())
    ');
    $stmt->execute([$userId]);
    $adminId = (int)$pdo->lastInsertId();

    if (!$adminId) {
        throw new Exception('Admin insert failed');
    }

    // ── Ücretsiz 1 Aylık Başlangıç Paketi ────────────────────────────────────
    // Yeni kaydolan her admin'e otomatik olarak 1 aylık ücretsiz abonelik ver.
    // Kart bilgisi gerekmez, ödeme yoktur.
    $pdo->prepare('
        INSERT INTO subscriptions (user_id, plan, status, price, start_date, end_date, created_at)
        VALUES (?, \'monthly_1\', \'active\', 0.00, NOW(), DATE_ADD(NOW(), INTERVAL 1 MONTH), NOW())
    ')->execute([$userId]);
    // ─────────────────────────────────────────────────────────────────────────

    $pdo->commit();

    // Session başlat
    session_regenerate_id(true);
    $_SESSION['user_id']        = $userId;
    $_SESSION['admin_id']       = $adminId;
    $_SESSION['email']          = $email;
    $_SESSION['email_verified'] = $googleIdentity !== null;

    // Doğrulama emaili gönder (hata olsa dahi kayıt tamamlandı)
    // BUG FIX: email_sent gerçek sonuca göre set ediliyor, her zaman true değil.
    $emailSent = false;
    if (!$googleIdentity && $verifyToken) {
        try {
            $cfg       = require __DIR__ . '/../_email_config.php';
            $verifyUrl = rtrim($cfg['site_url'], '/') . '/email-dogrulandi.html?token=' . $verifyToken;
            [$subject, $html] = wbEmailVerify(['name' => $email, 'verifyUrl' => $verifyUrl]);
            $emailSent = wbMail($email, $email, $subject, $html);
            if (!$emailSent) {
                error_log('[auth/register.php] wbMail false döndü - email: ' . $email);
            }
        } catch (Throwable $mailErr) {
            error_log('[auth/register.php mail] ' . $mailErr->getMessage());
        }
    }

    wb_ok([
        'user_id'    => $userId,
        'admin_id'   => $adminId,
        'email_sent' => $emailSent,
    ], 201);

} catch (Throwable $e) {
    if (isset($pdo) && $pdo->inTransaction()) {
        $pdo->rollBack();
    }
    error_log('[auth/register.php] ' . $e->getMessage());
    wb_err('Kayıt başarısız. Lütfen tekrar deneyin.', 500);
}
