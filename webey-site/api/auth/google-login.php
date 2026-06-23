<?php
/**
 * api/auth/google-login.php
 * POST /api/auth/google-login.php
 * Body: { "credential": "<Google JWT>" }
 */
declare(strict_types=1);

require_once __DIR__ . '/../_public_bootstrap.php';
require_once __DIR__ . '/../_google_auth.php';
wb_method('POST');
wb_csrf_verify(true);

$origin  = trim((string)($_SERVER['HTTP_ORIGIN'] ?? ''));
$referer = trim((string)($_SERVER['HTTP_REFERER'] ?? ''));

$hostRaw = (string)($_SERVER['HTTP_X_FORWARDED_HOST'] ?? $_SERVER['HTTP_HOST'] ?? '');
$hostRaw = trim(explode(',', $hostRaw)[0] ?? '');
$expectedHost = strtolower((string)parse_url((str_contains($hostRaw, '://') ? $hostRaw : 'http://' . $hostRaw), PHP_URL_HOST));
$expectedPort = (int)($_SERVER['HTTP_X_FORWARDED_PORT'] ?? $_SERVER['SERVER_PORT'] ?? 0);

$isSameOrigin = static function (string $url) use ($expectedHost, $expectedPort): bool {
    if ($url === '' || strtolower($url) === 'null') return false;
    $host = strtolower((string)parse_url($url, PHP_URL_HOST));
    $port = (int)(parse_url($url, PHP_URL_PORT) ?? 0);
    if ($host === '' || $expectedHost === '') return false;
    if ($host !== $expectedHost) return false;
    if ($port !== 0 && $expectedPort !== 0 && $port !== $expectedPort) return false;
    return true;
};

if ($origin !== '') {
    if (!$isSameOrigin($origin)) {
        wb_err('Gecersiz kaynak', 403, 'origin_invalid');
    }
} elseif ($referer !== '') {
    if (!$isSameOrigin($referer)) {
        wb_err('Gecersiz kaynak', 403, 'referer_invalid');
    }
}

$data          = wb_body();
$credential    = trim((string)($data['credential'] ?? ''));
$requestedRole = strtolower(trim((string)($data['role'] ?? 'user')));
$requestedRole = in_array($requestedRole, ['user', 'admin'], true) ? $requestedRole : 'user';

if ($credential === '') {
    wb_err('Google token eksik', 400, 'missing_token');
}

$GOOGLE_CLIENT_ID = wb_google_client_id();
if (!$GOOGLE_CLIENT_ID) {
    error_log('[google-login] GOOGLE_CLIENT_ID ortam degiskeni tanimli degil');
    wb_err('Google girisi su an kullanilamiyor.', 503, 'misconfigured');
}

$identity = wb_google_extract_identity($credential);
if (!$identity) {
    wb_err('Gecersiz Google token', 401, 'invalid_token');
}

$googleId  = (string)$identity['google_id'];
$email     = (string)$identity['email'];
$firstName = (string)$identity['first_name'];
$lastName  = (string)$identity['last_name'];
$avatar    = (string)$identity['avatar'];
$fullName  = (string)$identity['full_name'];

try {
    $pdo->beginTransaction();

    if ($requestedRole === 'admin') {
        $stmt = $pdo->prepare("
            SELECT u.id, u.email, u.name, u.role, au.id AS admin_id, au.onboarding_completed
            FROM users u
            LEFT JOIN admin_users au ON au.user_id = u.id
            WHERE u.google_id = ?
            LIMIT 1
        ");
        $stmt->execute([$googleId]);
        $admin = $stmt->fetch();

        if ($admin && !in_array((string)($admin['role'] ?? ''), ['admin', 'superadmin'], true)) {
            $pdo->rollBack();
            wb_err('Bu Google hesabi bir musteri hesabi ile bagli.', 409, 'role_mismatch');
        }

        if (!$admin) {
            $stmt = $pdo->prepare("
                SELECT u.id, u.email, u.name, u.role, au.id AS admin_id, au.onboarding_completed
                FROM users u
                LEFT JOIN admin_users au ON au.user_id = u.id
                WHERE u.email = ?
                LIMIT 1
            ");
            $stmt->execute([$email]);
            $admin = $stmt->fetch();

            if ($admin && !in_array((string)($admin['role'] ?? ''), ['admin', 'superadmin'], true)) {
                $pdo->rollBack();
                wb_err('Bu e-posta bir musteri hesabi ile kullaniliyor.', 409, 'role_mismatch');
            }

            if ($admin) {
                if ((string)($admin['role'] ?? '') === 'superadmin') {
                    $pdo->rollBack();
                    wb_err('Bu e-posta superadmin hesabi ile kullaniliyor.', 409, 'role_mismatch');
                }
                $pdo->prepare("
                    UPDATE users
                    SET google_id = ?, avatar_url = COALESCE(NULLIF(avatar_url, ''), ?), name = CASE WHEN ? != '' THEN ? ELSE name END, role = 'admin', email_verified_at = COALESCE(email_verified_at, NOW())
                    WHERE id = ?
                ")->execute([$googleId, $avatar, $fullName, $fullName, $admin['id']]);

                if (empty($admin['admin_id'])) {
                    $pdo->prepare("
                        INSERT INTO admin_users (user_id, onboarding_completed, created_at)
                        VALUES (?, 0, NOW())
                    ")->execute([(int)$admin['id']]);
                    $admin['admin_id'] = (int)$pdo->lastInsertId();
                    $admin['onboarding_completed'] = 0;
                }
            } else {
                $oauthPlaceholderHash = password_hash(bin2hex(random_bytes(32)), PASSWORD_BCRYPT);
                $pdo->prepare("
                    INSERT INTO users (google_id, email, name, avatar_url, role, email_verified_at, password_hash, created_at)
                    VALUES (?, ?, ?, ?, 'admin', NOW(), ?, NOW())
                ")->execute([$googleId, $email, $fullName, $avatar, $oauthPlaceholderHash]);
                $userId = (int)$pdo->lastInsertId();

                $pdo->prepare("
                    INSERT INTO admin_users (user_id, onboarding_completed, created_at)
                    VALUES (?, 0, NOW())
                ")->execute([$userId]);

                $admin = [
                    'id' => $userId,
                    'email' => $email,
                    'name' => $fullName,
                    'admin_id' => (int)$pdo->lastInsertId(),
                    'onboarding_completed' => 0,
                ];
            }
        }

        if ((string)($admin['role'] ?? '') === 'superadmin') {
            $pdo->rollBack();
            wb_err('Bu Google hesabi superadmin oturumu icin kullanilamaz.', 409, 'role_mismatch');
        }

        if (empty($admin['admin_id'])) {
            $pdo->prepare("
                INSERT INTO admin_users (user_id, onboarding_completed, created_at)
                VALUES (?, 0, NOW())
            ")->execute([(int)$admin['id']]);
            $admin['admin_id'] = (int)$pdo->lastInsertId();
            $admin['onboarding_completed'] = 0;
        }

        $userId = (int)$admin['id'];
        $adminId = (int)$admin['admin_id'];
        $pdo->prepare('UPDATE users SET last_login_at = NOW() WHERE id = ?')->execute([$userId]);
        $pdo->commit();

        session_regenerate_id(true);
        $_SESSION['user_id']   = $userId;
        $_SESSION['admin_id']  = $adminId;
        $_SESSION['email']     = $email;
        $_SESSION['user_role'] = 'admin';
        $_SESSION['login_via'] = 'google';
        unset($_SESSION['user_phone'], $_SESSION['business_id']);

        wb_ok([
            'user' => [
                'id' => $userId,
                'name' => (string)($admin['name'] ?? $fullName),
                'email' => $email,
            ],
            'role' => 'admin',
            'adminId' => $adminId,
            'onboardingCompleted' => ((int)($admin['onboarding_completed'] ?? 0) === 1),
        ]);
    }

    $stmt = $pdo->prepare("
        SELECT u.id, u.email, u.name, u.role, c.phone
        FROM users u
        LEFT JOIN customers c ON c.user_id = u.id
        WHERE u.google_id = ?
        LIMIT 1
    ");
    $stmt->execute([$googleId]);
    $user = $stmt->fetch();

    if ($user && (string)($user['role'] ?? '') !== 'user') {
        $pdo->rollBack();
        wb_err('Bu Google hesabi yonetici hesabi ile bagli.', 409, 'role_mismatch');
    }

    if (!$user) {
        $stmt = $pdo->prepare("
            SELECT u.id, u.email, u.name, u.role, c.phone
            FROM users u
            LEFT JOIN customers c ON c.user_id = u.id
            WHERE u.email = ? OR c.email = ?
            LIMIT 1
        ");
        $stmt->execute([$email, $email]);
        $user = $stmt->fetch();

        if ($user && (string)($user['role'] ?? '') !== 'user') {
            $pdo->rollBack();
            wb_err('Bu e-posta yonetici hesabi ile kullaniliyor.', 409, 'role_mismatch');
        }

        if ($user) {
            $pdo->prepare("
                UPDATE users
                SET google_id = ?, avatar_url = COALESCE(NULLIF(avatar_url, ''), ?), name = CASE WHEN ? != '' THEN ? ELSE name END, role = 'user', email_verified_at = COALESCE(email_verified_at, NOW())
                WHERE id = ?
            ")->execute([$googleId, $avatar, $fullName, $fullName, $user['id']]);
        } else {
            $pdo->rollBack();
            wb_err('Bu Google hesabi ile kayit tamamlanmamis. Lutfen Google ile devam et akisini kullanin.', 409, 'signup_required');
        }
    }

    $userId = (int)$user['id'];
    $custStmt = $pdo->prepare("SELECT phone FROM customers WHERE user_id = ? LIMIT 1");
    $custStmt->execute([$userId]);
    $customer = $custStmt->fetch();

    if (!$customer) {
        $pdo->prepare("
            INSERT INTO customers (user_id, first_name, last_name, email, sms_ok, email_ok)
            VALUES (?, ?, ?, ?, 1, 1)
        ")->execute([
            $userId,
            $firstName !== '' ? $firstName : null,
            $lastName !== '' ? $lastName : null,
            $email,
        ]);
        $user['phone'] = '';
    } else {
        $pdo->prepare("
            UPDATE customers
            SET email = COALESCE(NULLIF(email, ''), ?),
                email_ok = 1,
                first_name = CASE WHEN (first_name IS NULL OR first_name = '') AND ? != '' THEN ? ELSE first_name END,
                last_name = CASE WHEN (last_name IS NULL OR last_name = '') AND ? != '' THEN ? ELSE last_name END,
                updated_at = NOW()
            WHERE user_id = ?
        ")->execute([$email, $firstName, $firstName, $lastName, $lastName, $userId]);
        $user['phone'] = (string)($customer['phone'] ?? '');
    }

    $pdo->prepare('UPDATE users SET last_login_at = NOW() WHERE id = ?')->execute([$userId]);
    $pdo->commit();

    session_regenerate_id(true);
    $_SESSION['user_id']    = $userId;
    $_SESSION['user_name']  = (string)($user['name'] ?? $fullName);
    $_SESSION['user_role']  = 'user';
    $_SESSION['user_phone'] = (string)($user['phone'] ?? '');
    $_SESSION['login_via']  = 'google';
    unset($_SESSION['admin_id'], $_SESSION['business_id'], $_SESSION['email']);

    wb_ok([
        'user' => [
            'id' => $userId,
            'name' => (string)($user['name'] ?? $fullName),
            'email' => $email,
        ],
        'role' => 'user',
    ]);
} catch (Throwable $e) {
    if (isset($pdo) && $pdo->inTransaction()) {
        $pdo->rollBack();
    }
    error_log('[google-login] ' . $e->getMessage());
    wb_err('Sunucu hatasi, tekrar deneyin', 500, 'internal_error');
}
