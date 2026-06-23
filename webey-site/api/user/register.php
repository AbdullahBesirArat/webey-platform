<?php
declare(strict_types=1);
/**
 * api/user/register.php — Müşteri (end-user) kaydı
 * POST JSON: { phone, password, firstName?, lastName?, birthday?, city?, district?, neighborhood? }
 *
 * BUG FIX: Duplicate telefon kontrolü transaction dışındaydı.
 * SELECT → beginTransaction → INSERT arasında iki eş zamanlı istek aynı telefonu geçebiliyordu.
 * Çözüm: beginTransaction → SELECT FOR UPDATE → INSERT (transaction içinde)
 * + users.email üzerindeki UNIQUE KEY zaten DB seviyesinde de koruyor (son savunma).
 */

require_once __DIR__ . '/../_public_bootstrap.php';
require_once __DIR__ . '/../_google_auth.php';
wb_method('POST');

$in = wb_body();

$phone    = preg_replace('/\D+/', '', (string)($in['phone']    ?? ''));
$password = (string)($in['password'] ?? '');

if (str_starts_with($phone, '90') && strlen($phone) === 12) $phone = substr($phone, 2);
if (str_starts_with($phone, '0')) $phone = substr($phone, 1);

$firstName    = trim((string)($in['firstName']    ?? ''));
$lastName     = trim((string)($in['lastName']     ?? ''));
$emailReal    = strtolower(trim((string)($in['email'] ?? '')));
$emailOk      = (bool)($in['emailOk'] ?? false);
$googleCredential = trim((string)($in['googleCredential'] ?? ''));
$googleIdentity = null;
if (!$emailReal || !filter_var($emailReal, FILTER_VALIDATE_EMAIL)) {
    wb_err('Geçerli bir e-posta adresi zorunludur.', 422, 'email_required');
}
if (!$emailOk) {
    wb_err('E-posta doğrulaması zorunludur.', 422, 'email_verification_required');
}
$emailVerifiedByGoogle = false;
if ($googleCredential !== '') {
    $googleIdentity = wb_google_extract_identity($googleCredential);
    if (!$googleIdentity || (string)$googleIdentity['email'] !== $emailReal) {
        wb_err('Google doğrulaması geçersiz. Lütfen tekrar deneyin.', 422, 'google_verification_required');
    }
    $emailVerifiedByGoogle = true;
}
$emailVerifiedUntil = (int)($_SESSION['email_otp_verified']['email_verify'][$emailReal] ?? 0);
if (!$emailVerifiedByGoogle && $emailVerifiedUntil < time()) {
    wb_err('E-posta doğrulaması süresi dolmuş. Lütfen yeni kod isteyin.', 422, 'email_verification_required');
}
$birthday     = trim((string)($in['birthday']     ?? ''));
$city         = trim((string)($in['city']         ?? ''));
$district     = trim((string)($in['district']     ?? ''));
$neighborhood = trim((string)($in['neighborhood'] ?? ''));
$smsOk        = (bool)($in['smsOk']   ?? true);
$email        = $emailReal;

wb_validate([
    'password' => $password,
    'phone' => $phone,
    'firstName' => $firstName,
    'lastName' => $lastName,
    'birthday' => $birthday,
    'city' => $city,
    'district' => $district,
    'neighborhood' => $neighborhood,
], [
    'password' => ['required', 'min:8'],
    'phone' => $phone === '' ? [] : ['regex:/^5\d{9}$/'],
    'firstName' => ['required', 'min:2'],
    'lastName' => ['required', 'min:2'],
    'birthday' => ['required', 'regex:/^\d{4}-\d{2}-\d{2}$/'],
    'city' => ['required'],
    'district' => ['required'],
    'neighborhood' => ['required'],
]);

try {
    // BUG FIX: Her şey transaction içinde — race condition önlendi
    $pdo->beginTransaction();

    // E-posta uniq kontrolü
    $chk = $pdo->prepare("
        SELECT u.id
        FROM users u
        LEFT JOIN customers c ON c.user_id = u.id
        WHERE u.email = ? OR c.email = ?
        LIMIT 1
        FOR UPDATE
    ");
    $chk->execute([$email, $email]);
    if ($chk->fetchColumn()) {
        $pdo->rollBack();
        wb_err('Bu e-posta adresi zaten kayıtlı. Giriş yapın.', 409, 'email_exists');
    }

    // Telefon uniq kontrolü
    $phoneChk = $pdo->prepare("SELECT user_id FROM customers WHERE phone = ? LIMIT 1 FOR UPDATE");
    $phoneChk->execute([$phone]);
    if ($phoneChk->fetchColumn()) {
        $pdo->rollBack();
        wb_err('Bu telefon numarası zaten kayıtlı. Giriş yapın.', 409, 'phone_exists');
    }

    $hash = password_hash($password, PASSWORD_BCRYPT, ['cost' => 11]);
    $pdo->prepare("INSERT INTO users (google_id, email, name, avatar_url, password_hash, role, email_verified_at, created_at) VALUES (?, ?, ?, ?, ?, 'user', NOW(), NOW())")
        ->execute([
            $googleIdentity['google_id'] ?? null,
            $email,
            trim($firstName . ' ' . $lastName) ?: null,
            $googleIdentity['avatar'] ?? null,
            $hash,
        ]);
    $userId = (int)$pdo->lastInsertId();

    $pdo->prepare("
        INSERT INTO customers (user_id, first_name, last_name, phone, email, birthday, city, district, neighborhood, sms_ok, email_ok)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ")->execute([
        $userId,
        $firstName ?: null,
        $lastName  ?: null,
        $phone ?: null,
        $email,
        ($birthday && preg_match('/^\d{4}-\d{2}-\d{2}$/', $birthday)) ? $birthday : null,
        $city         ?: null,
        $district     ?: null,
        $neighborhood ?: null,
        $smsOk  ? 1 : 0,
        1,
    ]);

    $pdo->commit();

    session_regenerate_id(true);
    $_SESSION['user_id']    = $userId;
    $_SESSION['user_role']  = 'user';
    $_SESSION['user_phone'] = $phone;
    unset($_SESSION['admin_id'], $_SESSION['business_id']);
    unset($_SESSION['email_otp_verified']['email_verify'][$emailReal]);

    // Hoş geldin emaili gönder (email varsa)
    if ($emailReal) {
        try {
            require_once __DIR__ . '/../_mailer.php';
            require_once __DIR__ . '/../_email_templates.php';
            $cfg = require __DIR__ . '/../_email_config.php';
            [$subj, $html] = wbEmailWelcomeUser([
                'firstName' => $firstName ?: 'Değerli Üye',
                'siteUrl'   => $cfg['site_url'],
            ]);
            wbMail($emailReal, trim($firstName . ' ' . $lastName), $subj, $html);
        } catch (Throwable $mailErr) {
            error_log('[user/register.php welcome mail] ' . $mailErr->getMessage());
        }
    }

    wb_ok([
        'userId' => (string)$userId,
        'phone'  => $phone,
        'mode'   => 'created',
    ], 201);

} catch (Throwable $e) {
    if (isset($pdo) && $pdo->inTransaction()) $pdo->rollBack();
    // UNIQUE KEY ihlali (DB seviyesi ikincil koruması)
    if ($e->getCode() === '23000' || str_contains($e->getMessage(), 'Duplicate entry')) {
        if (str_contains($e->getMessage(), 'users.email')) {
            wb_err('Bu e-posta adresi zaten kayıtlı. Giriş yapın.', 409, 'email_exists');
        }
        wb_err('Bu telefon numarası zaten kayıtlı. Giriş yapın.', 409, 'phone_exists');
    }
    error_log('[user/register.php] ' . $e->getMessage());
    wb_err('Kayıt başarısız. Lütfen tekrar deneyin.', 500);
}


