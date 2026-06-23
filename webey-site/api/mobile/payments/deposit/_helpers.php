<?php
declare(strict_types=1);
/**
 * api/mobile/payments/deposit/_helpers.php
 * Deposit ödeme akışı için paylaşılan yardımcılar.
 * start.php, status.php, callback.php tarafından require edilir.
 */

require_once dirname(__DIR__, 3) . '/_iyzico.php';
require_once dirname(__DIR__, 3) . '/_user_notifications.php';

if (!function_exists('deposit_table_ready')) {

    function deposit_table_ready(PDO $pdo): bool
    {
        return mobile_table_has_column($pdo, 'appointment_payments', 'id');
    }

    /**
     * Randevuyu müşteri sahipliği kontrolüyle çeker.
     * Deposit kolon yoksa (migration çalışmamış) fallback değerler eklenir.
     */
    function deposit_get_appointment_for_customer(
        PDO $pdo,
        int $appointmentId,
        int $customerUserId
    ): ?array {
        $hasDepositCols = mobile_table_has_column($pdo, 'appointments', 'deposit_required');
        $depositSelect  = $hasDepositCols ? ', a.deposit_required, a.deposit_amount' : '';

        $stmt = $pdo->prepare(
            "SELECT a.id, a.status, a.business_id, a.customer_user_id,
                    a.start_at, a.service_id {$depositSelect}
             FROM appointments a
             WHERE a.id = ? AND a.customer_user_id = ?
             LIMIT 1"
        );
        $stmt->execute([$appointmentId, $customerUserId]);
        $row = $stmt->fetch();
        if (!$row) {
            return null;
        }
        if (!$hasDepositCols) {
            $row['deposit_required'] = 0;
            $row['deposit_amount']   = null;
        }
        return $row;
    }

    /**
     * appointment_payments tablosundan mevcut ödeme kaydını döner.
     * checkout_url kolonu varsa (2026_05_22b migration) dahil edilir; yoksa null döner.
     */
    function deposit_find_payment(PDO $pdo, int $appointmentId): ?array
    {
        $hasCheckoutUrl = mobile_table_has_column($pdo, 'appointment_payments', 'checkout_url');
        $urlSelect      = $hasCheckoutUrl ? ', checkout_url' : '';

        $stmt = $pdo->prepare(
            "SELECT id, appointment_id, customer_user_id, business_id,
                    status, amount, currency, provider,
                    provider_payment_id, checkout_token, conversation_id{$urlSelect},
                    paid_at, created_at, updated_at
             FROM appointment_payments
             WHERE appointment_id = ?
             LIMIT 1"
        );
        $stmt->execute([$appointmentId]);
        $row = $stmt->fetch();
        if (!$row) {
            return null;
        }
        if (!$hasCheckoutUrl) {
            $row['checkout_url'] = null;
        }
        return $row;
    }

    /**
     * Yeni kayıt oluşturur veya yeniden deneme için mevcut pending/failed/cancelled kaydı günceller.
     * checkout_url kolonu varsa (2026_05_22b migration) yazılır.
     */
    function deposit_upsert_pending_payment(
        PDO    $pdo,
        int    $appointmentId,
        int    $customerUserId,
        int    $businessId,
        float  $amount,
        string $checkoutToken,
        string $conversationId,
        string $checkoutUrl = '',
        ?array $existing = null
    ): void {
        $hasUrlCol = mobile_table_has_column($pdo, 'appointment_payments', 'checkout_url');

        if ($existing === null) {
            $urlColSql = $hasUrlCol ? ', checkout_url' : '';
            $urlPhSql  = $hasUrlCol ? ', ?' : '';
            $args = [$appointmentId, $customerUserId, $businessId, $amount, $checkoutToken, $conversationId];
            if ($hasUrlCol) {
                $args[] = $checkoutUrl !== '' ? $checkoutUrl : null;
            }

            $pdo->prepare(
                "INSERT INTO appointment_payments
                     (appointment_id, customer_user_id, business_id, amount, currency,
                      status, checkout_token, conversation_id{$urlColSql}, provider, created_at, updated_at)
                 VALUES (?, ?, ?, ?, 'TRY', 'pending', ?, ?{$urlPhSql}, 'iyzico', NOW(), NOW())"
            )->execute($args);
        } else {
            $urlSetSql = $hasUrlCol ? ', checkout_url = ?' : '';
            $args = [$amount, $checkoutToken, $conversationId];
            if ($hasUrlCol) {
                $args[] = $checkoutUrl !== '' ? $checkoutUrl : null;
            }
            $args[] = $appointmentId;

            $pdo->prepare(
                "UPDATE appointment_payments
                 SET status = 'pending', amount = ?,
                     checkout_token = ?, conversation_id = ?{$urlSetSql}, updated_at = NOW()
                 WHERE appointment_id = ?
                   AND status IN ('pending', 'failed', 'cancelled')"
            )->execute($args);
        }
    }

    /**
     * Kart bilgileri veya hassas token'ları çıkararak iyzico yanıtını güvenli hale getirir.
     */
    function deposit_safe_payload_log(array $response): string
    {
        $safe = $response;
        foreach (['cardToken', 'cardUserKey', 'binNumber', 'lastFourDigits', 'cardAlias'] as $k) {
            unset($safe[$k]);
        }
        return json_encode($safe) ?: '{}';
    }

    /**
     * İyzico checkout form başlatır.
     * Billing sistemindeki iyzicoInitCheckout yerine doğrudan _iyzicoPost çağırır;
     * paymentGroup='PRODUCT', özel callbackUrl ve conversationId formatı kullanır.
     *
     * @return array{ok:bool, checkout_token:string, checkout_url:string, conversation_id:string}|array{ok:false, error:string}
     */
    function deposit_provider_checkout_start(
        int    $appointmentId,
        int    $customerUserId,
        float  $amount,
        string $userName,
        string $userEmail,
        string $userPhone
    ): array {
        $cfg = require dirname(__DIR__, 3) . '/_iyzico_config.php';

        $conversationId = 'deposit_' . $appointmentId . '_' . $customerUserId . '_' . time();
        $priceStr       = number_format($amount, 2, '.', '');

        $callbackUrl = rtrim((string)$cfg['site_url'], '/')
            . '/api/mobile/payments/deposit/callback.php?appointment_id=' . $appointmentId;

        if ($cfg['debug']) {
            $fakeToken = 'dep_checkout_' . bin2hex(random_bytes(8));
            error_log('[deposit DEBUG] checkout_start | appt:' . $appointmentId . ' amount:' . $amount);
            return [
                'ok'              => true,
                'checkout_token'  => $fakeToken,
                'checkout_url'    => rtrim((string)$cfg['site_url'], '/') . '/odeme?debug=1&token=' . $fakeToken,
                'conversation_id' => $conversationId,
            ];
        }

        $nameParts = explode(' ', trim($userName), 2);
        $firstName = $nameParts[0] ?: 'Ad';
        $lastName  = $nameParts[1] ?? 'Soyad';
        $gsmNumber = '+90' . preg_replace('/^0|^\+90|^90/', '', preg_replace('/\D/', '', $userPhone));
        $email     = $userEmail ?: $customerUserId . '@webey.com.tr';

        $payload = [
            'locale'              => 'tr',
            'conversationId'      => $conversationId,
            'price'               => $priceStr,
            'paidPrice'           => $priceStr,
            'currency'            => 'TRY',
            'basketId'            => 'deposit_' . $appointmentId,
            'paymentGroup'        => 'PRODUCT',
            'callbackUrl'         => $callbackUrl,
            'enabledInstallments' => [1],
            'buyer'               => [
                'id'                  => (string)$customerUserId,
                'name'                => $firstName,
                'surname'             => $lastName,
                'gsmNumber'           => $gsmNumber,
                'email'               => $email,
                'identityNumber'      => '11111111110',
                'registrationAddress' => 'Türkiye',
                'city'                => 'Istanbul',
                'country'             => 'Turkey',
            ],
            'shippingAddress'     => ['contactName' => $userName, 'city' => 'Istanbul', 'country' => 'Turkey', 'address' => 'Türkiye'],
            'billingAddress'      => ['contactName' => $userName, 'city' => 'Istanbul', 'country' => 'Turkey', 'address' => 'Türkiye'],
            'basketItems'         => [[
                'id'        => 'deposit_' . $appointmentId,
                'name'      => 'Randevu Kapora',
                'category1' => 'Hizmet',
                'itemType'  => 'VIRTUAL',
                'price'     => $priceStr,
            ]],
        ];

        $resp = _iyzicoPost($cfg, '/payment/iyzipos/checkoutform/initialize/auth/ecom', $payload);

        if (($resp['status'] ?? '') !== 'success') {
            error_log('[deposit] checkout_start hata: ' . deposit_safe_payload_log($resp));
            return ['ok' => false, 'error' => $resp['errorMessage'] ?? 'Ödeme başlatılamadı'];
        }

        return [
            'ok'              => true,
            'checkout_token'  => (string)($resp['token'] ?? ''),
            'checkout_url'    => (string)($resp['paymentPageUrl'] ?? ''),
            'conversation_id' => $conversationId,
        ];
    }

    /**
     * Başarılı kapora ödemesi sonrası müşteriyi bildirir.
     */
    function deposit_notify_paid(PDO $pdo, array $payment, int $appointmentId): void
    {
        if (!function_exists('wbInsertUserNotification')) {
            return;
        }

        $userId = (int)$payment['customer_user_id'];
        if ($userId < 1) {
            return;
        }

        try {
            $apptStmt = $pdo->prepare(
                "SELECT a.start_at, b.name AS biz_name, s.name AS svc_name
                 FROM appointments a
                 LEFT JOIN businesses b ON b.id = a.business_id
                 LEFT JOIN services   s ON s.id = a.service_id
                 WHERE a.id = ? LIMIT 1"
            );
            $apptStmt->execute([$appointmentId]);
            $row = $apptStmt->fetch();
            if (!$row) {
                return;
            }

            $bizName = (string)($row['biz_name'] ?? 'İşletme');
            $startAt = (string)($row['start_at'] ?? '');
            $svcName = (string)($row['svc_name'] ?? '');
            $amount  = number_format((float)$payment['amount'], 2, ',', '.') . ' TL';

            wbInsertUserNotification(
                $pdo,
                $userId,
                $appointmentId,
                'deposit_paid',
                'Kapora ödemeniz alındı',
                $bizName . ' - ' . $startAt . ($svcName !== '' ? ' (' . $svcName . ')' : '') . '. ' . $amount . ' kapora ödemesi alındı.',
                $bizName
            );
        } catch (Throwable $e) {
            error_log('[deposit_notify_paid] ' . $e->getMessage());
        }
    }
}
