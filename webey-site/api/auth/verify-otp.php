<?php
// api/auth/verify-otp.php
// SMS kodunu doğrular, telefonu onaylanmış olarak işaretler
// POST { phone: "5321234567", code: "123456", purpose: "register" }
declare(strict_types=1);

require_once __DIR__ . '/../_public_bootstrap.php';

wb_method('POST');

$in      = wb_body();
$phone   = preg_replace('/\D/', '', (string)($in['phone'] ?? ''));
$code    = trim((string)($in['code'] ?? ''));
$purpose = in_array($in['purpose'] ?? '', ['register','login','phone_change'], true)
         ? $in['purpose'] : 'register';

if (!preg_match('/^5\d{9}$/', $phone)) {
    wb_err('Geçersiz telefon numarası', 400, 'invalid_phone');
}
if (!preg_match('/^\d{6}$/', $code)) {
    wb_err('Geçersiz kod formatı', 400, 'invalid_code');
}

// ── Debug modu: sabit 123456 ile doğrula, DB'ye bakma ───────────────
$cfg_sms = require __DIR__ . '/../_sms_config.php';
if (!empty($cfg_sms['debug'])) {
    if ($code !== '123456') {
        wb_err('Yanlış kod', 400, 'wrong_code');
    }
    // Debug'da token kontrolü yok, direkt purpose işlemine geç
} else {
    // ── Token'ı bul ──────────────────────────────────────────────────
    try {
        $stmt = $pdo->prepare("
            SELECT id, code AS hashed_code, attempts, expires_at
            FROM otp_tokens
            WHERE phone=? AND purpose=? AND used_at IS NULL AND expires_at > NOW()
            ORDER BY id DESC LIMIT 1
        ");
        $stmt->execute([$phone, $purpose]);
        $token = $stmt->fetch(PDO::FETCH_ASSOC);
    } catch (Throwable $e) {
        error_log('[verify-otp] DB: ' . $e->getMessage());
        wb_err('Doğrulama yapılamadı', 500);
    }

    if (!$token) {
        wb_err('Kod süresi dolmuş veya geçersiz. Yeni kod isteyin.', 400, 'expired');
    }

    // ── Çok fazla yanlış deneme (max 5) ──────────────────────────────
    if ((int)$token['attempts'] >= 5) {
        $pdo->prepare("UPDATE otp_tokens SET used_at=NOW() WHERE id=?")->execute([$token['id']]);
        wb_err('Çok fazla hatalı deneme. Yeni kod isteyin.', 429, 'too_many_attempts');
    }

    // ── Kodu doğrula ─────────────────────────────────────────────────
    if (!password_verify($code, $token['hashed_code'])) {
        $pdo->prepare("UPDATE otp_tokens SET attempts=attempts+1 WHERE id=?")->execute([$token['id']]);
        $remaining = 4 - (int)$token['attempts'];
        wb_err('Yanlış kod. ' . max(0, $remaining) . ' deneme hakkınız kaldı.', 400, 'wrong_code');
    }

    // ── Başarılı — token'ı kullanıldı olarak işaretle ────────────────
    $pdo->prepare("UPDATE otp_tokens SET used_at=NOW() WHERE id=?")->execute([$token['id']]);
}

// ── Purpose'a göre işlem yap ─────────────────────────────────────────
$result = ['verified' => true, 'phone' => $phone];

if ($purpose === 'register' || $purpose === 'login') {
    // Kullanıcıyı session'a al + phone_verified_at güncelle
    $userEmail = $phone . '@phone.user';
    $userStmt  = $pdo->prepare("SELECT id, role FROM users WHERE email=? LIMIT 1");
    $userStmt->execute([$userEmail]);
    $user = $userStmt->fetch(PDO::FETCH_ASSOC);

    if ($user) {
        // phone_verified_at güncelle
        $pdo->prepare("UPDATE users SET phone_verified_at=NOW() WHERE id=?")->execute([$user['id']]);

        // Session başlat
        $_SESSION['user_id']    = $user['id'];
        $_SESSION['user_role']  = $user['role'];
        $_SESSION['user_phone'] = $phone;

        $result['userId'] = $user['id'];
        $result['role']   = $user['role'];
        $result['message'] = 'Telefon doğrulandı, giriş yapıldı.';
    } else {
        // Kullanıcı yok — kayıt sırasında doğrulama (session'a telefonu koy)
        $_SESSION['otp_verified_phone'] = $phone;
        $result['message'] = 'Telefon doğrulandı. Kayıt tamamlanabilir.';
    }
}

if ($purpose === 'phone_change') {
    // Oturumdaki kullanıcının telefonunu güncelle
    $loggedUserId = $_SESSION['user_id'] ?? null;
    if (!$loggedUserId) wb_err('Oturum gerekli', 401);

    $pdo->prepare("UPDATE customers SET phone=? WHERE user_id=?")->execute([$phone, $loggedUserId]);
    $pdo->prepare("UPDATE users SET phone_verified_at=NOW() WHERE id=?")->execute([$loggedUserId]);
    $_SESSION['user_phone'] = $phone;
    $result['message'] = 'Telefon numaranız güncellendi.';
}

wb_ok($result);
