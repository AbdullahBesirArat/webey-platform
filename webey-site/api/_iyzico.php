<?php
// api/_iyzico.php
// ─────────────────────────────────────────────────────────────────────
// İyzico Ödeme Yardımcısı
//
// Kullanım:
//   require_once __DIR__ . '/_iyzico.php';
//
//   // 1) Ödeme formu başlat (kullanıcıyı iyzico checkout'a yönlendir)
//   $result = iyzicoInitCheckout($userId, $plan, $price, $userName, $userEmail, $userPhone);
//   if ($result['ok']) redirect($result['checkoutUrl']);
//
//   // 2) Kayıtlı kart token'ı ile ödeme al
//   $result = iyzicoChargeCard($cardToken, $price, $userId, $userName, $userEmail, $userPhone, $description);
//
//   // 3) Kart kaydet (checkout form — iyzico 3DS ile)
//   $result = iyzicoInitCardStore($userId, $userName, $userEmail);
// ─────────────────────────────────────────────────────────────────────
declare(strict_types=1);

// ── Checkout Başlat (ödeme formu aç) ────────────────────────────────

/**
 * İyzico checkout form token'ı üret.
 * Frontend bu token ile iyzico'nun hazır ödeme formunu açar.
 *
 * @return array ['ok'=>bool, 'checkoutToken'=>string, 'checkoutUrl'=>string, 'error'=>string]
 */
function iyzicoInitCheckout(
    int    $userId,
    string $plan,
    float  $price,
    string $userName,
    string $userEmail,
    string $userPhone
): array {
    $cfg = require __DIR__ . '/_iyzico_config.php';

    if ($cfg['debug']) {
        // Debug modunda sahte token döndür
        $fakeToken = 'checkout_' . bin2hex(random_bytes(8));
        error_log('[iyzico DEBUG] InitCheckout | user:' . $userId . ' plan:' . $plan . ' price:' . $price);
        return [
            'ok'           => true,
            'checkoutToken'=> $fakeToken,
            'checkoutUrl'  => $cfg['site_url'] . '/fiyat.html?debug_payment=1&token=' . $fakeToken,
        ];
    }

    $conversationId = 'sub_' . $userId . '_' . time();
    $priceStr       = number_format($price, 2, '.', '');

    $payload = [
        'locale'                => 'tr',
        'conversationId'        => $conversationId,
        'price'                 => $priceStr,
        'paidPrice'             => $priceStr,
        'currency'              => 'TRY',
        'basketId'              => $plan . '_' . $userId,
        'paymentGroup'          => 'SUBSCRIPTION',
        'callbackUrl'           => $cfg['callback_url'] . '?userId=' . $userId . '&plan=' . $plan,
        'enabledInstallments'   => [1],
        'buyer'                 => [
            'id'                  => (string)$userId,
            'name'                => explode(' ', $userName)[0] ?? 'Ad',
            'surname'             => explode(' ', $userName, 2)[1] ?? 'Soyad',
            'gsmNumber'           => '+90' . preg_replace('/^0|^\+90|^90/', '', preg_replace('/\D/', '', $userPhone)),
            'email'               => $userEmail ?: $userId . '@webey.com.tr',
            'identityNumber'      => '11111111110', // TC (sandbox için sabit)
            'registrationAddress' => 'Türkiye',
            'city'                => 'Istanbul',
            'country'             => 'Turkey',
        ],
        'shippingAddress'       => ['contactName' => $userName, 'city' => 'Istanbul', 'country' => 'Turkey', 'address' => 'Türkiye'],
        'billingAddress'        => ['contactName' => $userName, 'city' => 'Istanbul', 'country' => 'Turkey', 'address' => 'Türkiye'],
        'basketItems'           => [[
            'id'        => $plan,
            'name'      => 'Webey ' . ucfirst(str_replace('_', ' ', $plan)) . ' Abonelik',
            'category1' => 'Yazılım',
            'itemType'  => 'VIRTUAL',
            'price'     => $priceStr,
        ]],
    ];

    $resp = _iyzicoPost($cfg, '/payment/iyzipos/checkoutform/initialize/auth/ecom', $payload);

    if (($resp['status'] ?? '') !== 'success') {
        error_log('[iyzico] InitCheckout hata: ' . json_encode($resp));
        return ['ok' => false, 'error' => $resp['errorMessage'] ?? 'Ödeme başlatılamadı'];
    }

    return [
        'ok'            => true,
        'checkoutToken' => $resp['token'],
        'checkoutUrl'   => $resp['paymentPageUrl'] ?? '',
    ];
}

/**
 * Kayıtlı kart token'ı ile ödeme al (otomatik yenileme için).
 *
 * @return array ['ok'=>bool, 'paymentId'=>string, 'error'=>string]
 */
function iyzicoChargeCard(
    string $cardToken,
    float  $price,
    int    $userId,
    string $userName,
    string $userEmail,
    string $userPhone,
    string $description = 'Webey Abonelik'
): array {
    $cfg = require __DIR__ . '/_iyzico_config.php';

    if ($cfg['debug']) {
        $fakeId = 'PAY_' . strtoupper(bin2hex(random_bytes(6)));
        error_log('[iyzico DEBUG] ChargeCard | card:' . $cardToken . ' price:' . $price);
        return ['ok' => true, 'paymentId' => $fakeId];
    }

    $priceStr = number_format($price, 2, '.', '');

    $payload = [
        'locale'          => 'tr',
        'conversationId'  => 'charge_' . $userId . '_' . time(),
        'price'           => $priceStr,
        'paidPrice'       => $priceStr,
        'currency'        => 'TRY',
        'installment'     => '1',
        'basketId'        => 'renewal_' . $userId,
        'paymentChannel'  => 'WEB',
        'paymentGroup'    => 'SUBSCRIPTION',
        'paymentCard'     => [
            'cardUserKey' => $cardToken,
        ],
        'buyer' => [
            'id'                  => (string)$userId,
            'name'                => explode(' ', $userName)[0] ?? 'Ad',
            'surname'             => explode(' ', $userName, 2)[1] ?? 'Soyad',
            'gsmNumber'           => '+90' . preg_replace('/^0|^\+90|^90/', '', preg_replace('/\D/', '', $userPhone)),
            'email'               => $userEmail ?: $userId . '@webey.com.tr',
            'identityNumber'      => '11111111110',
            'registrationAddress' => 'Türkiye',
            'city'                => 'Istanbul',
            'country'             => 'Turkey',
        ],
        'shippingAddress' => ['contactName' => $userName, 'city' => 'Istanbul', 'country' => 'Turkey', 'address' => 'Türkiye'],
        'billingAddress'  => ['contactName' => $userName, 'city' => 'Istanbul', 'country' => 'Turkey', 'address' => 'Türkiye'],
        'basketItems'     => [[
            'id'        => 'renewal',
            'name'      => $description,
            'category1' => 'Yazılım',
            'itemType'  => 'VIRTUAL',
            'price'     => $priceStr,
        ]],
    ];

    $resp = _iyzicoPost($cfg, '/payment/auth', $payload);

    if (($resp['status'] ?? '') !== 'success') {
        error_log('[iyzico] ChargeCard hata: ' . json_encode($resp));
        return ['ok' => false, 'error' => $resp['errorMessage'] ?? 'Ödeme başarısız'];
    }

    return ['ok' => true, 'paymentId' => (string)($resp['paymentId'] ?? '')];
}

// ── İç Yardımcılar ───────────────────────────────────────────────────

/**
 * İyzico API'ye POST isteği gönder.
 * HMAC-SHA256 imzalı Authorization header ekler.
 */
function _iyzicoPost(array $cfg, string $path, array $payload): array {
    $body      = json_encode($payload);
    $randomKey = bin2hex(random_bytes(8)); // nonce
    $timestamp = (string)(int)(microtime(true) * 1000);

    // İmza: base64(HMAC-SHA256(apiKey + randomKey + timestamp + body, secretKey))
    $toSign    = $cfg['api_key'] . $randomKey . $timestamp . $body;
    $signature = base64_encode(hash_hmac('sha256', $toSign, $cfg['secret_key'], true));
    $authHeader = 'IYZWS ' . $cfg['api_key'] . ':' . $signature;

    $opts = [
        'http' => [
            'method'  => 'POST',
            'header'  =>
                "Content-Type: application/json\r\n" .
                "Accept: application/json\r\n" .
                "Authorization: {$authHeader}\r\n" .
                "x-iyzi-rnd: {$randomKey}\r\n" .
                "x-iyzi-client-version: iyzipay-php-2.0.0\r\n",
            'content' => $body,
            'timeout' => 30,
            'ignore_errors' => true,
        ],
    ];

    $raw  = @file_get_contents(rtrim($cfg['base_url'], '/') . $path, false, stream_context_create($opts));
    $data = $raw ? (json_decode($raw, true) ?? []) : [];

    if (!$raw) {
        error_log('[iyzico] Bağlantı hatası: ' . $path);
        return ['status' => 'failure', 'errorMessage' => 'Ödeme sunucusuna bağlanılamadı'];
    }

    return $data;
}