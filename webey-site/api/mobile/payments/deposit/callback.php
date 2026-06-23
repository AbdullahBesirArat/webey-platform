<?php
declare(strict_types=1);
/**
 * api/mobile/payments/deposit/callback.php
 * POST — İyzico'nun kapora ödemesi sonrası çağırdığı callback endpoint.
 *
 * İyzico bu URL'e form-encoded POST gönderir:
 *   token : string  (checkout token)
 *
 * Query params (start.php'nin callbackUrl'ine eklediği):
 *   appointment_id : int
 *
 * Güvenlik:
 *   - Bearer token auth yok (iyzico bu endpoint'i çağırır, müşteri değil)
 *   - Debug mode: sadece local ortamda kabul edilir (billing pattern)
 *   - Ödeme iyzico API'sine yeniden doğrulanır; POST gövdesindeki token'a körü körüne güvenilmez
 *   - conversationId çapraz kontrolü yapılır (response vs DB)
 *   - Tutar her zaman DB'den alınır; iyzico'dan gelen tutar yalnızca doğrulama için karşılaştırılır
 *   - İdempotency: zaten 'paid' ise ikinci kez işlem yapılmaz
 *   - Her durumda HTTP 200 döner (iyzico bunu zorunlu tutar)
 *   - Sanitize edilmiş iyzico yanıtı raw_payload kolonuna yazılır (audit trail)
 */

require_once __DIR__ . '/../../_bootstrap.php';
require_once __DIR__ . '/_helpers.php';

$appointmentId = (int)($_GET['appointment_id'] ?? 0);
$token         = trim((string)($_POST['token'] ?? ''));

if ($appointmentId < 1 || $token === '') {
    error_log('[deposit/callback.php] Geçersiz parametreler: appointment_id=' . $appointmentId . ' token_len=' . strlen($token));
    wb_ok(['received' => true, 'ignored' => true, 'reason' => 'missing_params']);
}

// ── Ödeme tablosu hazır mı? ───────────────────────────────────────────────────
if (!deposit_table_ready($pdo)) {
    error_log('[deposit/callback.php] appointment_payments tablosu mevcut değil');
    wb_ok(['received' => true, 'ignored' => true, 'reason' => 'table_not_ready']);
}

// ── Ödeme kaydını bul ────────────────────────────────────────────────────────
$payment = deposit_find_payment($pdo, $appointmentId);
if ($payment === null) {
    error_log('[deposit/callback.php] Ödeme kaydı bulunamadı: appointment_id=' . $appointmentId);
    wb_ok(['received' => true, 'ignored' => true, 'reason' => 'payment_not_found']);
}

// ── İdempotency: zaten ödendiyse tekrar işlem yapma ──────────────────────────
if ($payment['status'] === 'paid') {
    wb_ok(['received' => true, 'ignored' => true, 'reason' => 'already_paid']);
}

// ── Config yükle — doğrulama için gerekli ────────────────────────────────────
$cfg = require dirname(__DIR__, 3) . '/_iyzico_config.php';

// ── Debug mode production guard (billing/payment-callback.php pattern) ───────
if (!empty($cfg['debug'])) {
    $host    = strtolower((string)($_SERVER['HTTP_HOST'] ?? $_SERVER['SERVER_NAME'] ?? ''));
    $isLocal = in_array($host, ['localhost', '127.0.0.1', '::1'], true)
        || str_ends_with($host, '.local')
        || str_ends_with($host, '.test');

    if (!$isLocal) {
        error_log('[deposit/callback.php] Kritik: iyzico debug mode üretim ortamında aktif. Host: ' . $host);
        wb_ok(['received' => true, 'ignored' => true, 'reason' => 'debug_not_allowed']);
    }

    // Local debug: token format kontrolü
    error_log('[deposit DEBUG] callback | token:' . $token . ' appt:' . $appointmentId);
    $verifyOk          = str_starts_with($token, 'dep_checkout_');
    $paidPrice         = (float)$payment['amount'];
    $providerPaymentId = 'DEBUG_' . strtoupper(bin2hex(random_bytes(4)));
    $resp              = null; // debug modda provider response mevcut değil
} else {
    // ── İyzico'ya ödeme detayını doğrula ─────────────────────────────────────
    $conversationId = (string)($payment['conversation_id'] ?? '');

    $verifyPayload = [
        'locale'         => 'tr',
        'conversationId' => $conversationId,
        'token'          => $token,
    ];
    $resp = _iyzicoPost($cfg, '/payment/iyzipos/checkoutform/auth/ecom/detail', $verifyPayload);

    $verifyOk = ($resp['status'] ?? '') === 'success'
        && ($resp['paymentStatus'] ?? '') === 'SUCCESS';

    $paidPrice         = isset($resp['paidPrice']) ? (float)$resp['paidPrice'] : 0.0;
    $providerPaymentId = (string)($resp['paymentId'] ?? '');

    if (!$verifyOk) {
        error_log('[deposit/callback.php] İyzico doğrulama başarısız: ' . deposit_safe_payload_log($resp));
    }

    // ── ConversationId çapraz kontrolü ───────────────────────────────────────
    // iyzico response içindeki conversationId DB kaydıyla uyuşmalı.
    $respConvId = (string)($resp['conversationId'] ?? '');
    if ($verifyOk && $conversationId !== '' && $respConvId !== $conversationId) {
        error_log(sprintf(
            '[deposit/callback.php] conversationId uyumsuzluğu: beklenen=%s gelen=%s appt=%d',
            $conversationId, $respConvId, $appointmentId
        ));
        $verifyOk = false;
    }
}

// ── Tutar tutarsızlığı kontrolü (tamper koruması) ────────────────────────────
$expectedAmount = round((float)$payment['amount'], 2);
if ($verifyOk && !empty($cfg['debug']) === false && abs($paidPrice - $expectedAmount) > 0.01) {
    error_log(sprintf(
        '[deposit/callback.php] Tutar uyumsuzluğu: beklenen=%.2f gelen=%.2f appt=%d',
        $expectedAmount, $paidPrice, $appointmentId
    ));
    $verifyOk = false;
}

// ── raw_payload yazma (audit trail) — kolon varsa sanitize edilmiş yanıt kaydedilir ──
$hasRawPayload = mobile_table_has_column($pdo, 'appointment_payments', 'raw_payload');
$safePayload   = ($hasRawPayload && $resp !== null) ? deposit_safe_payload_log($resp) : null;

// ── Ödeme kaydını güncelle ────────────────────────────────────────────────────
try {
    if ($verifyOk) {
        $rawSetSql  = ($safePayload !== null) ? ', raw_payload = ?' : '';
        $updateArgs = [$providerPaymentId ?: null];
        if ($safePayload !== null) {
            $updateArgs[] = $safePayload;
        }
        $updateArgs[] = $appointmentId;

        $pdo->prepare(
            "UPDATE appointment_payments
             SET status = 'paid',
                 provider_payment_id = ?,
                 paid_at = NOW(){$rawSetSql},
                 updated_at = NOW()
             WHERE appointment_id = ?
               AND status != 'paid'"
        )->execute($updateArgs);

        // Müşteri bildirimi gönder
        try {
            $refreshed = deposit_find_payment($pdo, $appointmentId);
            if ($refreshed) {
                deposit_notify_paid($pdo, $refreshed, $appointmentId);
            }
        } catch (Throwable $notifEx) {
            error_log('[deposit/callback.php notif] ' . $notifEx->getMessage());
        }
    } else {
        $rawSetSql  = ($safePayload !== null) ? ', raw_payload = ?' : '';
        $updateArgs = [];
        if ($safePayload !== null) {
            $updateArgs[] = $safePayload;
        }
        $updateArgs[] = $appointmentId;

        $pdo->prepare(
            "UPDATE appointment_payments
             SET status = 'failed'{$rawSetSql},
                 updated_at = NOW()
             WHERE appointment_id = ?
               AND status NOT IN ('paid', 'failed')"
        )->execute($updateArgs);
    }
} catch (Throwable $e) {
    error_log('[deposit/callback.php] DB güncelleme hatası: ' . $e->getMessage());
    wb_ok(['received' => true, 'status' => 'error']);
}

wb_ok(['received' => true, 'status' => $verifyOk ? 'ok' : 'failed']);
