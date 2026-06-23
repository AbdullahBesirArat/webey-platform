<?php
declare(strict_types=1);
/**
 * api/mobile/business/payment-settings.php
 * GET  — Salonun kapora IBAN ayarlarını döner (kayıt yoksa default JSON).
 * POST — Kapora IBAN ayarlarını kaydeder (upsert).
 *
 * MVP: Webey para tahsil etmez. Müşteri kaporayı doğrudan salonun IBAN'ına yollar.
 * Banka adı: girilmemişse IBAN'daki banka kodundan tahmin edilir
 *            (kart tipi IBAN'dan çıkarılamaz, yalnızca banka kodu).
 *
 * Auth: business/admin zorunlu, mobile_business_context ile business_id.
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';
require_once __DIR__ . '/_helpers.php';            // mobile_business_context() burada tanımlı
require_once __DIR__ . '/../_payment_settings.php';
require_once __DIR__ . '/../_bank_codes.php';

$method = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');
if ($method !== 'GET' && $method !== 'POST') {
    wb_err('Yöntem desteklenmiyor', 405, 'method_not_allowed');
}

// Tüm yetkili gövde tek bir try ile sarılı: hiçbir koşulda boş response dönme.
// (wb_ok/wb_err exit ettiği için normal akış catch'e düşmez; yalnızca beklenmedik
//  Throwable yakalanır ve JSON hata döner.)
try {

$auth = mobile_auth($pdo, ['business', 'admin']);
$ctx = mobile_business_context($pdo, $auth);
$businessId = (int)$ctx['business_id'];

$tableReady = mobile_table_has_column($pdo, 'business_payment_settings', 'id');

if ($method === 'GET') {
    // Her durumda valid JSON dön; beklenmedik hata olsa bile boş response dönme.
    try {
        $settings = $tableReady
            ? wb_business_payment_settings($pdo, $businessId)
            : [
                'deposit_enabled' => false,
                'iban' => '',
                'iban_formatted' => '',
                'account_holder' => null,
                'bank_name' => null,
                'instructions' => null,
                'has_iban' => false,
            ];

        // IBAN varsa bank_code/bank_name (tahmin) ekle.
        $inferredBank = wb_bank_name_from_iban((string)($settings['iban'] ?? ''));
        if (($settings['bank_name'] ?? null) === null && $inferredBank !== null) {
            $settings['bank_name'] = $inferredBank;
        }
        $settings['bank_code'] = wb_bank_code_from_iban((string)($settings['iban'] ?? ''));
        $settings['bank_name_inferred'] = $inferredBank;

        wb_ok([
            'payment_settings' => $settings,
            'persisted' => $tableReady,
        ]);
    } catch (Throwable $e) {
        error_log('[mobile/business/payment-settings.php GET] ' . $e->getMessage());
        // Hata olsa bile güvenli default JSON dön (boş response yerine).
        wb_ok([
            'payment_settings' => [
                'deposit_enabled' => false,
                'iban' => '',
                'iban_formatted' => '',
                'account_holder' => null,
                'bank_name' => null,
                'instructions' => null,
                'has_iban' => false,
                'bank_code' => null,
                'bank_name_inferred' => null,
            ],
            'persisted' => false,
        ]);
    }
}

// ── POST: upsert ──────────────────────────────────────────────────────────────
if (!$tableReady) {
    wb_err('Ödeme ayarları servisi şu an kullanılamıyor', 503, 'payment_settings_unavailable');
}

$in = wb_body();

// TEK KAYNAK: kapora aktifliği bu sayfadan KONTROL EDİLMEZ. deposit_enabled
// yalnızca master (deposit_policies) ile senkron tutulur; istemciden gelen
// değer YOK SAYILIR. Bu ekran sadece IBAN/banka bilgilerini yönetir.
$masterDepositEnabled = false;
try {
    $hasPolicyRow = false;
    if (mobile_table_has_column($pdo, 'deposit_policies', 'rate_pct')) {
        $rstmt = $pdo->prepare('SELECT rate_pct FROM deposit_policies WHERE business_id = ? LIMIT 1');
        $rstmt->execute([$businessId]);
        $rate = $rstmt->fetchColumn();
        $hasPolicyRow = $rate !== false;
        if ($hasPolicyRow) {
            $masterDepositEnabled = (int)$rate > 0;
            if (!$masterDepositEnabled
                && mobile_table_has_column($pdo, 'businesses', 'deposit_required')
                && mobile_table_has_column($pdo, 'businesses', 'deposit_amount')) {
                $brstmt = $pdo->prepare('SELECT deposit_required, deposit_amount FROM businesses WHERE id = ? LIMIT 1');
                $brstmt->execute([$businessId]);
                $bizDeposit = $brstmt->fetch() ?: [];
                $masterDepositEnabled = (bool)($bizDeposit['deposit_required'] ?? false)
                    && (float)($bizDeposit['deposit_amount'] ?? 0) > 0;
            }
        }
    }
    if (!$hasPolicyRow && mobile_table_has_column($pdo, 'businesses', 'deposit_required')) {
        $brstmt = $pdo->prepare('SELECT deposit_required FROM businesses WHERE id = ? LIMIT 1');
        $brstmt->execute([$businessId]);
        $masterDepositEnabled = (bool)$brstmt->fetchColumn();
    }
} catch (Throwable $e) {
    error_log('[payment-settings.php master_check] ' . $e->getMessage());
}
$depositEnabled = $masterDepositEnabled;

$ibanRaw = trim((string)($in['iban'] ?? ''));
$iban = wb_normalize_iban($ibanRaw);
$accountHolder = trim((string)($in['account_holder'] ?? ''));
$bankName = trim((string)($in['bank_name'] ?? ''));
$instructions = trim((string)($in['instructions'] ?? $in['note'] ?? ''));

if (mb_strlen($accountHolder) > 160) {
    $accountHolder = mb_substr($accountHolder, 0, 160);
}
if (mb_strlen($bankName) > 120) {
    $bankName = mb_substr($bankName, 0, 120);
}
if (mb_strlen($instructions) > 2000) {
    $instructions = mb_substr($instructions, 0, 2000);
}

// IBAN girilmişse format kontrolü.
if ($iban !== '' && !wb_is_valid_tr_iban($iban)) {
    wb_err('Geçerli bir TR IBAN girin (TR ile başlamalı, 26 karakter).', 422, 'invalid_iban');
}

// Kapora aktifken (master açık) IBAN ve hesap sahibi boş bırakılamaz.
if ($depositEnabled) {
    if ($iban === '') {
        wb_err('Kapora aktif olduğu için IBAN boş bırakılamaz. Kapora almayı Kapora Politikası sayfasından kapatabilirsiniz.', 422, 'iban_required');
    }
    if ($accountHolder === '') {
        wb_err('Kapora aktif olduğu için hesap sahibi boş bırakılamaz.', 422, 'account_holder_required');
    }
}

// Banka adı boşsa IBAN'dan tahmin et.
if ($bankName === '' && $iban !== '') {
    $bankName = (string)(wb_bank_name_from_iban($iban) ?? '');
}

try {
    $stmt = $pdo->prepare(
        'INSERT INTO business_payment_settings
            (business_id, deposit_enabled, iban, account_holder, bank_name, instructions, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, NOW(), NOW())
         ON DUPLICATE KEY UPDATE
            deposit_enabled = VALUES(deposit_enabled),
            iban = VALUES(iban),
            account_holder = VALUES(account_holder),
            bank_name = VALUES(bank_name),
            instructions = VALUES(instructions),
            updated_at = NOW()'
    );
    $stmt->execute([
        $businessId,
        $depositEnabled ? 1 : 0,
        $iban !== '' ? $iban : null,
        $accountHolder !== '' ? $accountHolder : null,
        $bankName !== '' ? $bankName : null,
        $instructions !== '' ? $instructions : null,
    ]);
} catch (Throwable $e) {
    error_log('[mobile/business/payment-settings.php] ' . $e->getMessage());
    wb_err('Ödeme ayarları kaydedilemedi. Lütfen tekrar deneyin.', 500, 'internal_error');
}

$settings = wb_business_payment_settings($pdo, $businessId);
$inferredBank = wb_bank_name_from_iban((string)($settings['iban'] ?? ''));
$settings['bank_code'] = wb_bank_code_from_iban((string)($settings['iban'] ?? ''));
$settings['bank_name_inferred'] = $inferredBank;

wb_ok([
    'payment_settings' => $settings,
    'message' => 'Kapora ödeme ayarları kaydedildi.',
    'persisted' => true,
]);

} catch (Throwable $e) {
    error_log('[mobile/business/payment-settings.php fatal] ' . $e->getMessage());
    wb_err('Ödeme ayarları işlenemedi. Lütfen tekrar deneyin.', 500, 'internal_error');
}
