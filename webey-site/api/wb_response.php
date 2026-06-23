<?php
declare(strict_types=1);
/**
 * api/wb_response.php — Merkezi API Response Yardımcısı
 * ══════════════════════════════════════════════════════
 *
 * Tüm API endpoint'lerinde YALNIZCA bu fonksiyonları kullan.
 * Eski yöntemleri (echo json_encode, json_ok, json_err, respond_json, jsonResponse) KULLANMA.
 *
 * Kullanım:
 *   wb_ok(['user' => $user]);          // 200 OK
 *   wb_err('Yetkisiz erişim', 401);    // 4xx / 5xx hata
 *   wb_method('POST');                 // Method guard — POST değilse 405 döner
 *   wb_body();                         // php://input'u JSON parse eder
 */

if (!function_exists('wb_ok')) {

    /**
     * Başarılı JSON yanıtı gönderir ve çıkar.
     *
     * @param array $data  İstemciye gönderilecek veri
     * @param int   $code  HTTP durum kodu (varsayılan 200)
     */
    function wb_ok(array $data = [], int $code = 200): void
    {
        http_response_code($code);
        header('Content-Type: application/json; charset=utf-8');
        header('Cache-Control: no-store');
        echo json_encode(
            ['ok' => true, 'data' => $data],
            JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES
        );
        exit;
    }

    /**
     * Hata JSON yanıtı gönderir ve çıkar.
     * NOT: Üretimde iç hata detaylarını (e.getMessage()) BURAYA YAZMA.
     *      Bunun yerine error_log() ile sunucu loguna yaz.
     *
     * @param string $message  İstemciye gösterilecek hata mesajı
     * @param int    $code     HTTP durum kodu (varsayılan 400)
     * @param string $errorKey Makine tarafından okunabilir hata kodu (opsiyonel)
     */
    function wb_err(string $message, int $code = 400, string $errorKey = '', array $extra = []): void
    {
        http_response_code($code);
        header('Content-Type: application/json; charset=utf-8');
        header('Cache-Control: no-store');
        $body = ['ok' => false, 'error' => $message];
        if ($errorKey !== '') {
            $body['code'] = $errorKey;
        }
        if (!empty($extra)) {
            foreach ($extra as $k => $v) {
                if (!is_string($k) || $k === '' || array_key_exists($k, $body)) {
                    continue;
                }
                $body[$k] = $v;
            }
        }
        echo json_encode($body, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        exit;
    }

    /**
     * İzin verilen HTTP metodunu kontrol eder.
     * Eşleşmezse 405 döner ve çıkar.
     *
     * @param string ...$methods  İzin verilen metodlar: 'GET', 'POST', 'PUT', 'DELETE'
     */
    function wb_method(string ...$methods): void
    {
        $allowed = array_map('strtoupper', $methods);
        if (!in_array(strtoupper($_SERVER['REQUEST_METHOD'] ?? ''), $allowed, true)) {
            header('Allow: ' . implode(', ', $allowed));
            wb_err('Metod desteklenmiyor', 405);
        }
    }

    /**
     * php://input'u JSON olarak okur ve array döner.
     * Parse hatası varsa 400 döner ve çıkar.
     *
     * @return array
     */
    function wb_body(): array
    {
        $raw = _wb_raw_input();
        if ($raw === '' ) {
            return [];
        }
        $data = json_decode($raw, true);
        if (json_last_error() !== JSON_ERROR_NONE) {
            wb_err('Geçersiz JSON: ' . json_last_error_msg(), 400);
        }
        return $data ?? [];
    }

    /**
     * php://input'u bir kez okuyup cache'ler.
     * wb_csrf_verify ve wb_body aynı isteği iki kez okuyamaz sorununu çözer.
     */
    function _wb_raw_input(): string
    {
        static $cache = null;
        if ($cache === null) {
            $raw   = file_get_contents('php://input');
            $cache = ($raw !== false) ? $raw : '';
        }
        return $cache;
    }

    /**
     * Session güvenli şekilde başlatır (tekrar çağrılırsa no-op).
     * wb_auth*, wb_csrf_token ve wb_csrf_verify buraya delege eder —
     * 7 satırlık session init bloğunun tekrarı giderildi.
     */
    function _wb_ensure_session(): void
    {
        if (session_status() !== PHP_SESSION_NONE) return;
        $isHttps = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off')
                || (($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https')
                || (($_SERVER['SERVER_PORT'] ?? '') === '443');
        ini_set('session.cookie_samesite',  'Lax');
        ini_set('session.cookie_httponly',  '1');
        ini_set('session.cookie_secure',    $isHttps ? '1' : '0');
        ini_set('session.use_strict_mode',  '1');
        ini_set('session.cookie_lifetime',  '0');
        ini_set('session.gc_maxlifetime',   '7200');
        session_start();
    }

    /**
     * Session tabanlı kimlik doğrulama guard'ı.
     * Oturum yoksa 401 döner ve çıkar.
     *
     * @return array ['user_id', 'admin_id', 'business_id']
     */
    function wb_auth(): array
    {
        _wb_ensure_session();

        if (empty($_SESSION['user_id'])) {
            wb_err('Yetkisiz erişim', 401, 'unauthorized');
        }

        return [
            'user_id'     => (int)$_SESSION['user_id'],
            'admin_id'    => isset($_SESSION['admin_id'])    ? (int)$_SESSION['admin_id']    : null,
            'business_id' => isset($_SESSION['business_id']) ? (int)$_SESSION['business_id'] : null,
        ];
    }

    /**
     * Admin+business gerektiren endpoint'ler için.
     * Hem user_id hem admin_id zorunlu.
     *
     * @return array ['user_id', 'admin_id', 'business_id']
     */
    function wb_auth_admin(): array
    {
        $user = wb_auth();
        if ($user['admin_id'] === null) {
            wb_err('Bu işlem için yönetici yetkisi gerekli', 403, 'forbidden');
        }
        return $user;
    }

    /**
     * Müşteri (end-user) gerektiren endpoint'ler için.
     * user_role = 'user' zorunlu.
     *
     * @return array ['user_id', 'phone']
     */
    function wb_auth_user(): array
    {
        _wb_ensure_session();

        if (empty($_SESSION['user_id']) || ($_SESSION['user_role'] ?? '') !== 'user') {
            wb_err('Müşteri girişi gerekli', 401, 'unauthorized');
        }

        return [
            'user_id' => (int)$_SESSION['user_id'],
            'phone'   => $_SESSION['user_phone'] ?? '',
        ];
    }

    /**
     * Superadmin gerektiren endpoint'ler için.
     * user_role = 'superadmin' zorunlu.
     *
     * @return array ['user_id']
     */
    function wb_auth_superadmin(): array
    {
        _wb_ensure_session();

        $userId = (int)($_SESSION['user_id'] ?? 0);
        $role   = $_SESSION['user_role'] ?? $_SESSION['role'] ?? '';

        if (!$userId || $role !== 'superadmin') {
            wb_err('Superadmin yetkisi gerekli', 403, 'superadmin_required');
        }

        return ['user_id' => $userId];
    }

    /**
     * Sayfalama (pagination) meta verisi üretir.
     *
     * @param int $total  Toplam kayıt sayısı
     * @param int $page   Mevcut sayfa (1'den başlar)
     * @param int $limit  Sayfa başı kayıt
     * @return array ['total', 'page', 'limit', 'pages', 'has_more']
     */
    function wb_paginate(int $total, int $page, int $limit): array
    {
        $pages = $limit > 0 ? (int)ceil($total / $limit) : 1;
        return [
            'total'    => $total,
            'page'     => $page,
            'limit'    => $limit,
            'pages'    => $pages,
            'has_more' => $page < $pages,
        ];
    }

    // ══════════════════════════════════════════
    // CSRF KORUMASI
    // ══════════════════════════════════════════

    /**
     * CSRF token üretir ve session'a kaydeder.
     */
    function wb_csrf_token(): string
    {
        _wb_ensure_session();
        if (empty($_SESSION['csrf_token']) || (time() - ($_SESSION['csrf_token_ts'] ?? 0)) > 7200) {
            $_SESSION['csrf_token']    = bin2hex(random_bytes(32));
            $_SESSION['csrf_token_ts'] = time();
        }
        return $_SESSION['csrf_token'];
    }

    /**
     * Gelen isteğin CSRF tokenını doğrular.
     */
    function wb_csrf_verify(bool $strict = false): void
    {
        _wb_ensure_session();

        $method = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');
        if (in_array($method, ['GET', 'HEAD', 'OPTIONS'], true)) return;

        $sessionToken = $_SESSION['csrf_token'] ?? '';
        $incoming = $_SERVER['HTTP_X_CSRF_TOKEN']
            ?? $_SERVER['HTTP_X_XSRF_TOKEN']
            ?? '';
        if ($incoming === '') {
            $body     = json_decode(_wb_raw_input(), true) ?? [];
            $incoming = $body['_csrf'] ?? '';
        }

        if ($sessionToken === '' && !$strict) return;

        if (!hash_equals($sessionToken, $incoming)) {
            error_log('[CSRF] Geçersiz token — IP: ' . ($_SERVER['REMOTE_ADDR'] ?? '?'));
            wb_err('Güvenlik hatası: geçersiz istek', 403, 'csrf_invalid');
        }
    }

    // ══════════════════════════════════════════
    // INPUT VALIDATOR
    // ══════════════════════════════════════════

    /**
     * Veri doğrulama yardımcısı.
     */
    function wb_validate(array $data, array $rules): void
    {
        $errors = [];
        foreach ($rules as $field => $fieldRules) {
            $value = $data[$field] ?? null;
            $strVal = is_string($value) ? trim($value) : (string)($value ?? '');

            foreach ($fieldRules as $rule) {
                if ($rule === 'required') {
                    if ($value === null || $strVal === '') {
                        $errors[$field] = "'$field' alanı zorunludur";
                        break;
                    }
                } elseif ($rule === 'email') {
                    if ($strVal !== '' && !filter_var($strVal, FILTER_VALIDATE_EMAIL)) {
                        $errors[$field] = "'$field' geçerli bir email adresi olmalı";
                    }
                } elseif ($rule === 'numeric') {
                    if ($strVal !== '' && !is_numeric($value)) {
                        $errors[$field] = "'$field' sayısal olmalı";
                    }
                } elseif (str_starts_with($rule, 'min:')) {
                    $min = (int)substr($rule, 4);
                    if (strlen($strVal) < $min) {
                        $errors[$field] = "'$field' en az $min karakter olmalı";
                    }
                } elseif (str_starts_with($rule, 'max:')) {
                    $max = (int)substr($rule, 4);
                    if (strlen($strVal) > $max) {
                        $errors[$field] = "'$field' en fazla $max karakter olabilir";
                    }
                } elseif (str_starts_with($rule, 'regex:')) {
                    $pattern = substr($rule, 6);
                    if ($strVal !== '' && !preg_match($pattern, $strVal)) {
                        $errors[$field] = "'$field' formatı geçersiz";
                    }
                } elseif (str_starts_with($rule, 'in:')) {
                    $allowed = explode(',', substr($rule, 3));
                    if ($strVal !== '' && !in_array($strVal, $allowed, true)) {
                        $errors[$field] = "'$field' geçersiz değer: $strVal";
                    }
                }

                if (isset($errors[$field])) break;
            }
        }

        if (!empty($errors)) {
            http_response_code(422);
            header('Content-Type: application/json; charset=utf-8');
            echo json_encode([
                'ok'     => false,
                'error'  => array_values($errors)[0],
                'errors' => $errors,
                'code'   => 'validation_error',
            ], JSON_UNESCAPED_UNICODE);
            exit;
        }
    }

}
