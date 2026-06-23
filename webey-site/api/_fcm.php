<?php
declare(strict_types=1);

/**
 * Firebase Cloud Messaging HTTP v1 helper.
 *
 * Reads a service account JSON path from FIREBASE_SERVICE_ACCOUNT_PATH.
 * Missing config or send failures are reported through return values and logs;
 * callers should not let push delivery affect the primary request flow.
 */

function wb_fcm_base64url(string $data): string
{
    return rtrim(strtr(base64_encode($data), '+/', '-_'), '=');
}

function wb_fcm_service_account_path(): string
{
    $path = getenv('FIREBASE_SERVICE_ACCOUNT_PATH');
    if ($path === false || trim((string)$path) === '') {
        $path = $_ENV['FIREBASE_SERVICE_ACCOUNT_PATH'] ?? '';
    }
    if (trim((string)$path) === '') {
        $path = $_SERVER['FIREBASE_SERVICE_ACCOUNT_PATH'] ?? '';
    }
    if (trim((string)$path) === '') {
        $siblingSecurePath = dirname(__DIR__) . '-secure/firebase-service-account.json';
        if (is_file($siblingSecurePath)) {
            $path = $siblingSecurePath;
        }
    }

    return trim((string)$path);
}

function wb_fcm_load_service_account(): ?array
{
    $path = wb_fcm_service_account_path();
    if ($path === '') {
        error_log('[FCM] FIREBASE_SERVICE_ACCOUNT_PATH is not configured.');
        return null;
    }
    if (!is_file($path) || !is_readable($path)) {
        error_log('[FCM] Service account file is missing or unreadable: ' . $path);
        return null;
    }

    $raw = file_get_contents($path);
    if ($raw === false) {
        error_log('[FCM] Service account file could not be read: ' . $path);
        return null;
    }

    $json = json_decode($raw, true);
    if (!is_array($json)) {
        error_log('[FCM] Service account JSON is invalid: ' . $path);
        return null;
    }

    foreach (['project_id', 'client_email', 'private_key'] as $key) {
        if (empty($json[$key]) || !is_string($json[$key])) {
            error_log('[FCM] Service account JSON missing key: ' . $key);
            return null;
        }
    }

    return $json;
}

function wb_fcm_access_token(array $account): ?string
{
    $now = time();
    $header = wb_fcm_base64url(json_encode([
        'alg' => 'RS256',
        'typ' => 'JWT',
    ], JSON_UNESCAPED_SLASHES));
    $claims = wb_fcm_base64url(json_encode([
        'iss' => $account['client_email'],
        'scope' => 'https://www.googleapis.com/auth/firebase.messaging',
        'aud' => 'https://oauth2.googleapis.com/token',
        'iat' => $now,
        'exp' => $now + 3600,
    ], JSON_UNESCAPED_SLASHES));

    $unsignedJwt = $header . '.' . $claims;
    $signature = '';
    $ok = openssl_sign($unsignedJwt, $signature, $account['private_key'], OPENSSL_ALGO_SHA256);
    if (!$ok) {
        error_log('[FCM] Could not sign OAuth JWT.');
        return null;
    }

    $jwt = $unsignedJwt . '.' . wb_fcm_base64url($signature);
    $ch = curl_init('https://oauth2.googleapis.com/token');
    curl_setopt_array($ch, [
        CURLOPT_POST => true,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_HTTPHEADER => ['Content-Type: application/x-www-form-urlencoded'],
        CURLOPT_POSTFIELDS => http_build_query([
            'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
            'assertion' => $jwt,
        ]),
        CURLOPT_TIMEOUT => 15,
    ]);

    $body = curl_exec($ch);
    $status = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $err = curl_error($ch);
    curl_close($ch);

    if ($body === false || $status < 200 || $status >= 300) {
        error_log('[FCM] OAuth token failed status=' . $status . ' error=' . $err . ' body=' . (string)$body);
        return null;
    }

    $json = json_decode((string)$body, true);
    if (!is_array($json) || empty($json['access_token'])) {
        error_log('[FCM] OAuth token response missing access_token. body=' . (string)$body);
        return null;
    }

    return (string)$json['access_token'];
}

function wb_fcm_string_data(array $data): array
{
    $out = [];
    foreach ($data as $key => $value) {
        if ($value === null) {
            continue;
        }
        if (is_scalar($value)) {
            $out[(string)$key] = (string)$value;
        }
    }
    return $out;
}

function wb_fcm_is_unregistered_response(int $status, string $body): bool
{
    if ($body === '') {
        return false;
    }

    return (bool)preg_match('/UNREGISTERED|registration-token-not-registered|Requested entity was not found/i', $body);
}

function wb_fcm_send_to_token(
    string $token,
    string $title,
    string $body,
    array $data = [],
    array $options = []
): array
{
    $token = trim($token);
    if ($token === '') {
        return [
            'ok' => false,
            'status' => 0,
            'body' => '',
            'error' => 'empty_token',
            'invalid_token' => false,
        ];
    }

    $account = wb_fcm_load_service_account();
    if ($account === null) {
        return [
            'ok' => false,
            'status' => 0,
            'body' => '',
            'error' => 'missing_service_account',
            'invalid_token' => false,
        ];
    }

    $accessToken = wb_fcm_access_token($account);
    if ($accessToken === null) {
        return [
            'ok' => false,
            'status' => 0,
            'body' => '',
            'error' => 'oauth_failed',
            'invalid_token' => false,
        ];
    }

    $stringData = wb_fcm_string_data($data);

    // Data-only by default: NEVER attach an android.notification block unless the
    // caller explicitly wants a system-rendered notification. Any notification
    // block (even one carrying only channel_id) marks the message as a
    // "notification message"; Android then auto-renders it in the system tray and
    // SKIPS onMessageReceived() while the app is backgrounded/killed — which
    // suppresses our custom action-button notification and shows an empty one.
    $includeNotification = ($options['include_notification'] ?? true) !== false;

    $message = [
        'token' => $token,
        'data' => $stringData,
        'android' => [
            'priority' => 'high',
        ],
    ];

    if ($includeNotification) {
        $message['notification'] = [
            'title' => $title,
            'body' => $body,
        ];
        $message['android']['notification'] = [
            'channel_id' => (string)($options['android_channel_id'] ?? 'bookings_sound_v1'),
        ];
    }

    $payload = ['message' => $message];

    error_log(
        '[FCM] prepare data_only=' . ($includeNotification ? '0' : '1')
        . ' data_keys=' . implode(',', array_keys($stringData))
    );

    $url = 'https://fcm.googleapis.com/v1/projects/' . rawurlencode((string)$account['project_id']) . '/messages:send';
    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_POST => true,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_HTTPHEADER => [
            'Authorization: Bearer ' . $accessToken,
            'Content-Type: application/json',
        ],
        CURLOPT_POSTFIELDS => json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
        CURLOPT_TIMEOUT => 20,
    ]);

    $responseBody = curl_exec($ch);
    $status = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $err = curl_error($ch);
    curl_close($ch);

    $responseText = $responseBody === false ? '' : (string)$responseBody;
    $ok = $responseBody !== false && $status >= 200 && $status < 300;
    $invalidToken = wb_fcm_is_unregistered_response($status, $responseText);

    error_log('[FCM] send status=' . $status . ' ok=' . ($ok ? '1' : '0') . ' invalid=' . ($invalidToken ? '1' : '0') . ' body=' . $responseText);
    if ($responseBody === false || $err !== '') {
        error_log('[FCM] curl error=' . $err);
    }

    return [
        'ok' => $ok,
        'status' => $status,
        'body' => $responseText,
        'error' => $ok ? null : ($err !== '' ? $err : 'fcm_send_failed'),
        'invalid_token' => $invalidToken,
    ];
}
