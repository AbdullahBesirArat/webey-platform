<?php
declare(strict_types=1);

if (!defined('WB_GOOGLE_CLIENT_ID_FALLBACK')) {
    define('WB_GOOGLE_CLIENT_ID_FALLBACK', '279602177241-o5qmpgshp4g13jlrunnkav6vdu4hiejv.apps.googleusercontent.com');
}

if (!function_exists('wb_google_client_id')) {
    function wb_google_client_id(): string
    {
        return trim((string)(getenv('GOOGLE_CLIENT_ID') ?: WB_GOOGLE_CLIENT_ID_FALLBACK));
    }
}

if (!function_exists('wb_google_b64url_decode')) {
    function wb_google_b64url_decode(string $value): string
    {
        $remainder = strlen($value) % 4;
        if ($remainder > 0) {
            $value .= str_repeat('=', 4 - $remainder);
        }
        $decoded = base64_decode(strtr($value, '-_', '+/'), true);
        return $decoded === false ? '' : $decoded;
    }
}

if (!function_exists('wb_google_asn1_length')) {
    function wb_google_asn1_length(int $length): string
    {
        if ($length < 128) {
            return chr($length);
        }
        $temp = '';
        while ($length > 0) {
            $temp = chr($length & 0xff) . $temp;
            $length >>= 8;
        }
        return chr(0x80 | strlen($temp)) . $temp;
    }
}

if (!function_exists('wb_google_asn1_integer')) {
    function wb_google_asn1_integer(string $bytes): string
    {
        $bytes = ltrim($bytes, "\x00");
        if ($bytes === '') {
            $bytes = "\x00";
        }
        if ((ord($bytes[0]) & 0x80) === 0x80) {
            $bytes = "\x00" . $bytes;
        }
        return "\x02" . wb_google_asn1_length(strlen($bytes)) . $bytes;
    }
}

if (!function_exists('wb_google_jwk_to_pem')) {
    function wb_google_jwk_to_pem(array $jwk): ?string
    {
        if (($jwk['kty'] ?? '') !== 'RSA' || empty($jwk['n']) || empty($jwk['e'])) {
            return null;
        }

        $modulus = wb_google_b64url_decode((string)$jwk['n']);
        $exponent = wb_google_b64url_decode((string)$jwk['e']);
        if ($modulus === '' || $exponent === '') {
            return null;
        }

        $rsaPublicKey = wb_google_asn1_integer($modulus) . wb_google_asn1_integer($exponent);
        $rsaPublicKey = "\x30" . wb_google_asn1_length(strlen($rsaPublicKey)) . $rsaPublicKey;
        $bitString = "\x03" . wb_google_asn1_length(strlen($rsaPublicKey) + 1) . "\x00" . $rsaPublicKey;
        $algorithm = hex2bin('300d06092a864886f70d0101010500');
        if ($algorithm === false) {
            return null;
        }

        $sequence = "\x30" . wb_google_asn1_length(strlen($algorithm . $bitString)) . $algorithm . $bitString;
        $pem = "-----BEGIN PUBLIC KEY-----\n";
        $pem .= chunk_split(base64_encode($sequence), 64, "\n");
        $pem .= "-----END PUBLIC KEY-----\n";
        return $pem;
    }
}

if (!function_exists('wb_google_fetch_jwks')) {
    function wb_google_fetch_jwks(bool $forceRefresh = false): array
    {
        $cachePath = rtrim(sys_get_temp_dir(), DIRECTORY_SEPARATOR) . DIRECTORY_SEPARATOR . 'webey-google-jwks.json';
        $cacheTtl = 3600;

        if (!$forceRefresh && is_file($cachePath)) {
            $cached = json_decode((string)@file_get_contents($cachePath), true);
            $fetchedAt = (int)($cached['fetched_at'] ?? 0);
            if ($fetchedAt > 0 && (time() - $fetchedAt) < $cacheTtl && !empty($cached['keys']) && is_array($cached['keys'])) {
                return $cached['keys'];
            }
        }

        $ch = curl_init('https://www.googleapis.com/oauth2/v3/certs');
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT => 5,
            CURLOPT_CONNECTTIMEOUT => 3,
            CURLOPT_HTTPHEADER => ['Accept: application/json'],
        ]);
        $response = curl_exec($ch);
        $httpCode = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        if (!is_string($response) || $response === '' || $httpCode >= 400) {
            return [];
        }

        $decoded = json_decode($response, true);
        $keys = is_array($decoded['keys'] ?? null) ? $decoded['keys'] : [];
        if ($keys !== []) {
            @file_put_contents($cachePath, json_encode([
                'fetched_at' => time(),
                'keys' => $keys,
            ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES));
        }

        return $keys;
    }
}

if (!function_exists('wb_google_find_jwk')) {
    function wb_google_find_jwk(string $kid, bool $forceRefresh = false): ?array
    {
        foreach (wb_google_fetch_jwks($forceRefresh) as $key) {
            if (($key['kid'] ?? '') === $kid) {
                return $key;
            }
        }
        return null;
    }
}

if (!function_exists('wb_google_verify_id_token')) {
    function wb_google_verify_id_token(string $jwt, string $expectedAudience): ?array
    {
        $parts = explode('.', $jwt);
        if (count($parts) !== 3) {
            return null;
        }

        [$headerB64, $payloadB64, $signatureB64] = $parts;
        $header = json_decode(wb_google_b64url_decode($headerB64), true);
        $payload = json_decode(wb_google_b64url_decode($payloadB64), true);
        $signature = wb_google_b64url_decode($signatureB64);

        if (!is_array($header) || !is_array($payload) || $signature === '') {
            return null;
        }
        if (($header['alg'] ?? '') !== 'RS256' || empty($header['kid'])) {
            return null;
        }

        $jwk = wb_google_find_jwk((string)$header['kid']);
        if ($jwk === null) {
            $jwk = wb_google_find_jwk((string)$header['kid'], true);
        }
        if ($jwk === null) {
            return null;
        }

        $pem = wb_google_jwk_to_pem($jwk);
        if ($pem === null) {
            return null;
        }

        $verified = openssl_verify($headerB64 . '.' . $payloadB64, $signature, $pem, OPENSSL_ALGO_SHA256);
        if ($verified !== 1) {
            return null;
        }

        $issuer = (string)($payload['iss'] ?? '');
        if (!in_array($issuer, ['accounts.google.com', 'https://accounts.google.com'], true)) {
            return null;
        }

        if (($payload['aud'] ?? '') !== $expectedAudience) {
            return null;
        }

        $now = time();
        $exp = (int)($payload['exp'] ?? 0);
        $nbf = (int)($payload['nbf'] ?? 0);
        if ($exp <= 0 || $exp < ($now - 60)) {
            return null;
        }
        if ($nbf > 0 && $nbf > ($now + 60)) {
            return null;
        }

        return $payload;
    }
}

if (!function_exists('wb_google_extract_identity')) {
    function wb_google_extract_identity(string $credential): ?array
    {
        $clientId = wb_google_client_id();
        if ($clientId === '') {
            return null;
        }

        $payload = wb_google_verify_id_token($credential, $clientId);
        if (
            !is_array($payload) ||
            empty($payload['email']) ||
            !in_array($payload['email_verified'] ?? false, [true, 'true', 1, '1'], true)
        ) {
            return null;
        }

        $googleId  = trim((string)($payload['sub'] ?? ''));
        $email     = strtolower(trim((string)($payload['email'] ?? '')));
        $firstName = trim((string)($payload['given_name'] ?? ''));
        $lastName  = trim((string)($payload['family_name'] ?? ''));
        $avatar    = trim((string)($payload['picture'] ?? ''));
        $fullName  = trim($firstName . ' ' . $lastName);
        if ($fullName === '') {
            $fullName = strstr($email, '@', true) ?: 'Kullanici';
        }

        if ($googleId === '' || $email === '') {
            return null;
        }

        return [
            'google_id'  => $googleId,
            'email'      => $email,
            'first_name' => $firstName,
            'last_name'  => $lastName,
            'full_name'  => $fullName,
            'avatar'     => $avatar,
            'payload'    => $payload,
        ];
    }
}
