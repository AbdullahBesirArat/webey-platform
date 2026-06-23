<?php
declare(strict_types=1);

/**
 * api/mobile/_auth.php
 * Bearer token tabanlı mobil auth helperları.
 *
 * Raw token sadece login/register response içinde döner. DB'de token_hash tutulur.
 */

if (!function_exists('mobile_generate_token')) {
    function mobile_generate_token(): string
    {
        return 'wbm_' . rtrim(strtr(base64_encode(random_bytes(48)), '+/', '-_'), '=');
    }

    function mobile_hash_token(string $token): string
    {
        return hash('sha256', $token);
    }

    function mobile_bearer_token(): ?string
    {
        $header = $_SERVER['HTTP_AUTHORIZATION']
            ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION']
            ?? '';

        if ($header === '' && function_exists('apache_request_headers')) {
            $headers = apache_request_headers();
            foreach ($headers as $key => $value) {
                if (strtolower((string)$key) === 'authorization') {
                    $header = (string)$value;
                    break;
                }
            }
        }

        if (!is_string($header) || $header === '') {
            return null;
        }

        if (!preg_match('/^Bearer\s+(.+)$/i', trim($header), $matches)) {
            return null;
        }

        $token = trim($matches[1]);
        return $token !== '' ? $token : null;
    }

    function mobile_session_meta(array $meta = []): array
    {
        $platform = strtolower(trim((string)($meta['platform'] ?? 'unknown')));
        if (!in_array($platform, ['ios', 'android', 'web', 'unknown'], true)) {
            $platform = 'unknown';
        }

        $remoteIp = trim((string)($_SERVER['REMOTE_ADDR'] ?? ''));
        $ip = filter_var($remoteIp, FILTER_VALIDATE_IP) ? $remoteIp : null;

        return [
            'device_name' => mb_substr(trim((string)($meta['device_name'] ?? '')), 0, 120) ?: null,
            'device_id' => mb_substr(trim((string)($meta['device_id'] ?? '')), 0, 120) ?: null,
            'platform' => $platform,
            'app_version' => mb_substr(trim((string)($meta['app_version'] ?? '')), 0, 50) ?: null,
            'ip_address' => $ip,
            'user_agent' => mb_substr(trim((string)($_SERVER['HTTP_USER_AGENT'] ?? '')), 0, 255) ?: null,
        ];
    }

    function mobile_create_session(PDO $pdo, string $userType, int $userId, array $meta = []): array
    {
        if (!in_array($userType, ['customer', 'business', 'admin'], true)) {
            wb_err('Geçersiz kullanıcı tipi', 500, 'internal_error');
        }

        $sessionMeta = mobile_session_meta($meta);
        $ttlSeconds = 60 * 60 * 24 * 30;
        $expiresAt = date('Y-m-d H:i:s', time() + $ttlSeconds);

        for ($i = 0; $i < 3; $i++) {
            $token = mobile_generate_token();
            $hash = mobile_hash_token($token);

            try {
                $stmt = $pdo->prepare("
                    INSERT INTO mobile_sessions
                        (token_hash, user_type, user_id, device_name, device_id, platform,
                         app_version, ip_address, user_agent, expires_at, created_at)
                    VALUES
                        (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())
                ");
                $stmt->execute([
                    $hash,
                    $userType,
                    $userId,
                    $sessionMeta['device_name'],
                    $sessionMeta['device_id'],
                    $sessionMeta['platform'],
                    $sessionMeta['app_version'],
                    $sessionMeta['ip_address'],
                    $sessionMeta['user_agent'],
                    $expiresAt,
                ]);

                return [
                    'token' => $token,
                    'token_type' => 'Bearer',
                    'expires_in' => $ttlSeconds,
                    'expires_at' => $expiresAt,
                ];
            } catch (Throwable $e) {
                if ($i < 2 && ($e->getCode() === '23000' || str_contains($e->getMessage(), 'Duplicate'))) {
                    continue;
                }
                error_log('[mobile_create_session] ' . $e->getMessage());
                wb_err('Mobil oturum oluşturulamadı', 500, 'session_create_failed');
            }
        }

        wb_err('Mobil oturum oluşturulamadı', 500, 'session_create_failed');
    }

    function mobile_auth(PDO $pdo, string|array|null $requiredType = null): array
    {
        $token = mobile_bearer_token();
        if (!$token) {
            wb_err('Yetkisiz erişim', 401, 'unauthorized');
        }

        $hash = mobile_hash_token($token);

        try {
            $stmt = $pdo->prepare("
                SELECT id, user_type, user_id, expires_at, revoked_at
                FROM mobile_sessions
                WHERE token_hash = ?
                LIMIT 1
            ");
            $stmt->execute([$hash]);
            $session = $stmt->fetch();

            if (!$session || !empty($session['revoked_at'])) {
                wb_err('Yetkisiz erişim', 401, 'unauthorized');
            }

            if (strtotime((string)$session['expires_at']) <= time()) {
                wb_err('Oturum süresi dolmuş', 401, 'token_expired');
            }

            $userType = (string)$session['user_type'];
            $allowedTypes = $requiredType === null
                ? null
                : (is_array($requiredType) ? $requiredType : [$requiredType]);

            if ($allowedTypes !== null && !in_array($userType, $allowedTypes, true)) {
                wb_err('Bu işlem için yetkiniz yok', 403, 'forbidden');
            }

            $pdo->prepare('UPDATE mobile_sessions SET last_used_at = NOW() WHERE id = ?')
                ->execute([(int)$session['id']]);

            return [
                'session_id' => (int)$session['id'],
                'user_type' => $userType,
                'user_id' => (int)$session['user_id'],
            ];
        } catch (Throwable $e) {
            error_log('[mobile_auth] ' . $e->getMessage());
            wb_err('Oturum doğrulanamadı', 500, 'auth_failed');
        }
    }

    function mobile_revoke_current_session(PDO $pdo): void
    {
        $token = mobile_bearer_token();
        if (!$token) {
            wb_err('Yetkisiz erişim', 401, 'unauthorized');
        }

        try {
            $hash = mobile_hash_token($token);
            $stmt = $pdo->prepare("
                UPDATE mobile_sessions
                SET revoked_at = NOW()
                WHERE token_hash = ?
                  AND revoked_at IS NULL
                  AND expires_at > NOW()
            ");
            $stmt->execute([$hash]);
        } catch (Throwable $e) {
            error_log('[mobile_revoke_current_session] ' . $e->getMessage());
            wb_err('Çıkış yapılamadı', 500, 'logout_failed');
        }
    }

    function mobile_user_payload(PDO $pdo, string $userType, int $userId): array
    {
        try {
            if ($userType === 'customer') {
                $stmt = $pdo->prepare("
                    SELECT u.id, u.email, u.name, u.avatar_url, u.created_at, u.last_login_at,
                           u.email_verified_at, u.phone_verified_at, u.google_id,
                           c.first_name, c.last_name, c.phone, c.birthday, c.city,
                           c.district, c.neighborhood, c.sms_ok, c.email_ok
                    FROM users u
                    LEFT JOIN customers c ON c.user_id = u.id
                    WHERE u.id = ? AND u.role = 'user'
                    LIMIT 1
                ");
                $stmt->execute([$userId]);
                $row = $stmt->fetch();
                if (!$row) {
                    wb_err('Kullanıcı bulunamadı', 404, 'user_not_found');
                }

                $firstName = (string)($row['first_name'] ?? '');
                $lastName = (string)($row['last_name'] ?? '');
                $fullName = trim($firstName . ' ' . $lastName);
                if ($fullName === '') {
                    $fullName = (string)($row['name'] ?? '');
                }

                return [
                    'id' => (string)$row['id'],
                    'type' => 'customer',
                    'role' => 'customer',
                    'email' => (string)($row['email'] ?? ''),
                    'full_name' => $fullName,
                    'first_name' => $firstName,
                    'last_name' => $lastName,
                    'phone' => $row['phone'] ?? null,
                    'birthday' => $row['birthday'] ?? null,
                    'city' => $row['city'] ?? null,
                    'district' => $row['district'] ?? null,
                    'neighborhood' => $row['neighborhood'] ?? null,
                    'avatar_url' => $row['avatar_url'] ?? null,
                    'sms_ok' => (bool)($row['sms_ok'] ?? true),
                    'email_ok' => (bool)($row['email_ok'] ?? false),
                    'email_verified' => !empty($row['email_verified_at']) || !empty($row['email_ok']),
                    'phone_verified' => !empty($row['phone_verified_at']),
                    'google_connected' => !empty($row['google_id']),
                    'created_at' => $row['created_at'] ?? null,
                    'last_login_at' => $row['last_login_at'] ?? null,
                ];
            }

            if ($userType === 'business' || $userType === 'admin') {
                $stmt = $pdo->prepare("
                    SELECT u.id, u.email, u.name, u.avatar_url, u.role, u.created_at,
                           u.last_login_at, u.email_verified_at,
                           au.id AS admin_id, au.onboarding_completed AS admin_onboarding_completed,
                           b.id AS business_id, b.name AS business_name, b.owner_name,
                           b.status AS business_status, b.onboarding_step,
                           b.onboarding_completed AS business_onboarding_completed
                    FROM users u
                    INNER JOIN admin_users au ON au.user_id = u.id
                    LEFT JOIN businesses b ON b.owner_id = u.id
                    WHERE u.id = ?
                    LIMIT 1
                ");
                $stmt->execute([$userId]);
                $row = $stmt->fetch();
                if (!$row) {
                    wb_err('Kullanıcı bulunamadı', 404, 'user_not_found');
                }

                return [
                    'id' => (string)$row['id'],
                    'type' => $row['business_id'] ? 'business' : 'admin',
                    'role' => $row['business_id'] ? 'business' : 'admin',
                    'email' => (string)($row['email'] ?? ''),
                    'name' => $row['name'] ?? null,
                    'avatar_url' => $row['avatar_url'] ?? null,
                    'admin_id' => (string)$row['admin_id'],
                    'business_id' => $row['business_id'] !== null ? (string)$row['business_id'] : null,
                    'business_name' => $row['business_name'] ?? null,
                    'owner_name' => $row['owner_name'] ?? null,
                    'business_status' => $row['business_status'] ?? null,
                    'onboarding_completed' => (bool)($row['admin_onboarding_completed'] ?? false),
                    'business_onboarding_completed' => (bool)($row['business_onboarding_completed'] ?? false),
                    'onboarding_step' => $row['onboarding_step'] !== null ? (int)$row['onboarding_step'] : 0,
                    'email_verified' => !empty($row['email_verified_at']),
                    'created_at' => $row['created_at'] ?? null,
                    'last_login_at' => $row['last_login_at'] ?? null,
                ];
            }

            wb_err('Geçersiz kullanıcı tipi', 500, 'internal_error');
        } catch (Throwable $e) {
            error_log('[mobile_user_payload] ' . $e->getMessage());
            wb_err('Kullanıcı bilgisi alınamadı', 500, 'user_payload_failed');
        }
    }
}
