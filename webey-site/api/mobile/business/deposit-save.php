<?php
declare(strict_types=1);
/**
 * api/mobile/business/deposit-save.php
 * POST — Token sahibi işletmenin kapora ve iptal politikasını günceller (upsert).
 *
 * Body (JSON — opsiyonel alanlar; gönderilenler güncellenir):
 *   rate_pct              : int    — 0-100
 *   per_service           : bool
 *   cancel_policy         : string — esnek|orta|kati  (maks 20 karakter)
 *   free_cancel_hours     : int    — 1..168
 *   late_cancel_enabled   : bool
 *   late_cancel_rate_pct  : int    — 0..100
 *   no_show_policy        : string — forfeit|half_refund|refund
 *   customer_message      : string — maks 500
 *
 * Eksik kolonlar (idempotent migration uygulanmamış sistemler) güvenle atlanır.
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';
require_once __DIR__ . '/_helpers.php';
require_once __DIR__ . '/../_payment_settings.php';

wb_method('POST');

$auth = mobile_auth($pdo, ['business', 'admin']);
$ctx = mobile_business_context($pdo, $auth);
$businessId = (int)$ctx['business_id'];

$in = wb_body();

$depositMode = isset($in['deposit_mode'])
    ? strtolower(trim((string)$in['deposit_mode']))
    : null;
if ($depositMode !== null && !in_array($depositMode, ['percent', 'fixed'], true)) {
    wb_err('Kapora tipi percent veya fixed olmali.', 422, 'invalid_deposit_mode');
}
$fixedDepositAmount = isset($in['fixed_deposit_amount'])
    ? round((float)$in['fixed_deposit_amount'], 2)
    : null;
if ($fixedDepositAmount !== null && ($fixedDepositAmount < 0 || $fixedDepositAmount > 100000)) {
    wb_err('Sabit kapora tutari gecersiz.', 422, 'invalid_fixed_deposit_amount');
}
$ratePct = isset($in['rate_pct']) ? (int)$in['rate_pct'] : null;
$cancelPolicy = isset($in['cancel_policy'])
    ? mb_substr(trim((string)$in['cancel_policy']), 0, 20)
    : null;
$perService = isset($in['per_service']) ? ((bool)$in['per_service'] ? 1 : 0) : null;
$freeCancelHours = isset($in['free_cancel_hours'])
    ? max(0, min(168, (int)$in['free_cancel_hours']))
    : null;
$lateCancelEnabled = isset($in['late_cancel_enabled'])
    ? ((bool)$in['late_cancel_enabled'] ? 1 : 0)
    : null;
$lateCancelRatePct = isset($in['late_cancel_rate_pct'])
    ? max(0, min(100, (int)$in['late_cancel_rate_pct']))
    : null;
$noShowPolicy = isset($in['no_show_policy'])
    ? mb_substr(trim((string)$in['no_show_policy']), 0, 20)
    : null;
$customerMessage = isset($in['customer_message'])
    ? mb_substr(trim((string)$in['customer_message']), 0, 500)
    : null;

try {
    // Kolon kontrolü — idempotent migration uygulandı mı?
    $cols = [];
    $colsStmt = $pdo->prepare(
        "SELECT COLUMN_NAME FROM information_schema.COLUMNS
         WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'deposit_policies'"
    );
    $colsStmt->execute();
    foreach ($colsStmt->fetchAll() as $row) {
        $cols[$row['COLUMN_NAME']] = true;
    }
    $hasFreeHours = isset($cols['free_cancel_hours']);
    $hasLateEnabled = isset($cols['late_cancel_enabled']);
    $hasLateRate = isset($cols['late_cancel_rate_pct']);
    $hasNoShow = isset($cols['no_show_policy']);
    $hasCustMsg = isset($cols['customer_message']);

    $selectCols = 'rate_pct, per_service, cancel_policy'
        . ($hasFreeHours ? ', free_cancel_hours' : '')
        . ($hasLateEnabled ? ', late_cancel_enabled' : '')
        . ($hasLateRate ? ', late_cancel_rate_pct' : '')
        . ($hasNoShow ? ', no_show_policy' : '')
        . ($hasCustMsg ? ', customer_message' : '');
    $existingStmt = $pdo->prepare(
        "SELECT $selectCols FROM deposit_policies WHERE business_id = ? LIMIT 1"
    );
    $existingStmt->execute([$businessId]);
    $existing = $existingStmt->fetch();

    $finalRatePct = $ratePct ?? ($existing ? (int)$existing['rate_pct'] : 25);
    if ($finalRatePct > 0 && !in_array($finalRatePct, [25, 50, 75, 100], true)) {
        wb_err('Kapora orani 25, 50, 75 veya 100 olmali.', 422, 'invalid_rate_pct');
    }
    if ($depositMode === 'fixed') {
        if ($fixedDepositAmount === null || $fixedDepositAmount <= 0) {
            wb_err('Sabit kapora icin tutar girin.', 422, 'fixed_deposit_amount_required');
        }
        $finalRatePct = 0;
    }
    $finalPerService = $perService ?? ($existing ? (int)$existing['per_service'] : 0);
    if ($depositMode === 'fixed') {
        $finalPerService = 0;
    }
    $finalPolicy = ($cancelPolicy !== null && $cancelPolicy !== '')
        ? $cancelPolicy
        : ($existing ? (string)$existing['cancel_policy'] : 'esnek');

    // TEK KAYNAK: kapora aktifliği yalnız bu sayfadan (master). Açılıyorsa
    // geçerli IBAN şart — yoksa kaydetme ve kullanıcıyı IBAN sayfasına yönlendir.
    $enablingDeposit = ($depositMode === 'fixed' || $finalRatePct > 0);
    if ($enablingDeposit) {
        $ps = wb_business_payment_settings($pdo, $businessId);
        if (empty($ps['has_iban'])) {
            wb_err(
                'Kapora almak için önce IBAN bilgilerinizi tamamlayın.',
                422,
                'iban_required_for_deposit'
            );
        }
    }

    $insertCols = ['business_id', 'rate_pct', 'per_service', 'cancel_policy'];
    $placeholders = ['?', '?', '?', '?'];
    $updateSets = [
        'rate_pct = VALUES(rate_pct)',
        'per_service = VALUES(per_service)',
        'cancel_policy = VALUES(cancel_policy)',
    ];
    $params = [$businessId, $finalRatePct, $finalPerService, $finalPolicy];

    $finalFreeHours = null;
    if ($hasFreeHours) {
        $finalFreeHours = $freeCancelHours
            ?? ($existing && isset($existing['free_cancel_hours'])
                ? (int)$existing['free_cancel_hours']
                : 24);
        $insertCols[] = 'free_cancel_hours';
        $placeholders[] = '?';
        $updateSets[] = 'free_cancel_hours = VALUES(free_cancel_hours)';
        $params[] = $finalFreeHours;
    }
    $finalLateEnabled = null;
    if ($hasLateEnabled) {
        $finalLateEnabled = $lateCancelEnabled
            ?? ($existing && isset($existing['late_cancel_enabled'])
                ? (int)$existing['late_cancel_enabled']
                : 0);
        $insertCols[] = 'late_cancel_enabled';
        $placeholders[] = '?';
        $updateSets[] = 'late_cancel_enabled = VALUES(late_cancel_enabled)';
        $params[] = $finalLateEnabled;
    }
    $finalLateRate = null;
    if ($hasLateRate) {
        $finalLateRate = $lateCancelRatePct
            ?? ($existing && isset($existing['late_cancel_rate_pct'])
                ? (int)$existing['late_cancel_rate_pct']
                : 50);
        $insertCols[] = 'late_cancel_rate_pct';
        $placeholders[] = '?';
        $updateSets[] = 'late_cancel_rate_pct = VALUES(late_cancel_rate_pct)';
        $params[] = $finalLateRate;
    }
    $finalNoShow = null;
    if ($hasNoShow) {
        $finalNoShow = ($noShowPolicy !== null && $noShowPolicy !== '')
            ? $noShowPolicy
            : ($existing && isset($existing['no_show_policy'])
                ? (string)$existing['no_show_policy']
                : 'forfeit');
        $insertCols[] = 'no_show_policy';
        $placeholders[] = '?';
        $updateSets[] = 'no_show_policy = VALUES(no_show_policy)';
        $params[] = $finalNoShow;
    }
    $finalCustMsg = null;
    if ($hasCustMsg) {
        $finalCustMsg = $customerMessage
            ?? ($existing && isset($existing['customer_message'])
                ? (string)$existing['customer_message']
                : '');
        $finalCustMsg = $finalCustMsg !== '' ? $finalCustMsg : null;
        $insertCols[] = 'customer_message';
        $placeholders[] = '?';
        $updateSets[] = 'customer_message = VALUES(customer_message)';
        $params[] = $finalCustMsg;
    }

    $sql = 'INSERT INTO deposit_policies (' . implode(', ', $insertCols)
        . ') VALUES (' . implode(', ', $placeholders) . ')'
        . ' ON DUPLICATE KEY UPDATE ' . implode(', ', $updateSets)
        . ', updated_at = CURRENT_TIMESTAMP';
    $pdo->prepare($sql)->execute($params);

    // Eski ikinci aktiflik kaynağı (payment_settings.deposit_enabled) master ile
    // senkron tutulur — müşteri/booking görünürlüğü artık yalnız master'a bakar.
    if (mobile_table_has_column($pdo, 'business_payment_settings', 'deposit_enabled')) {
        $pdo->prepare('UPDATE business_payment_settings SET deposit_enabled = ?, updated_at = NOW() WHERE business_id = ?')
            ->execute([$enablingDeposit ? 1 : 0, $businessId]);
    }

    $hasBusinessDepositRequired = mobile_table_has_column($pdo, 'businesses', 'deposit_required');
    $hasBusinessDepositAmount = mobile_table_has_column($pdo, 'businesses', 'deposit_amount');
    if ($hasBusinessDepositRequired || $hasBusinessDepositAmount) {
        $businessSets = [];
        $businessParams = [];
        if ($hasBusinessDepositRequired) {
            $businessSets[] = 'deposit_required = ?';
            $businessParams[] = ($depositMode === 'fixed' || $finalRatePct > 0) ? 1 : 0;
        }
        if ($hasBusinessDepositAmount) {
            $businessSets[] = 'deposit_amount = ?';
            $businessParams[] = $depositMode === 'fixed' ? $fixedDepositAmount : null;
        }
        if ($businessSets !== []) {
            $businessParams[] = $businessId;
            $pdo->prepare(
                'UPDATE businesses SET ' . implode(', ', $businessSets) . ' WHERE id = ? LIMIT 1'
            )->execute($businessParams);
        }
    }

    $policy = [
        'rate_pct' => $finalRatePct,
        'per_service' => (bool)$finalPerService,
        'cancel_policy' => $finalPolicy,
        'deposit_required' => ($depositMode === 'fixed' || $finalRatePct > 0),
        'deposit_mode' => $depositMode === 'fixed' ? 'fixed' : 'percent',
        'fixed_deposit_amount' => $depositMode === 'fixed' ? $fixedDepositAmount : null,
    ];
    if ($hasFreeHours) $policy['free_cancel_hours'] = $finalFreeHours;
    if ($hasLateEnabled) $policy['late_cancel_enabled'] = (bool)$finalLateEnabled;
    if ($hasLateRate) $policy['late_cancel_rate_pct'] = $finalLateRate;
    if ($hasNoShow) $policy['no_show_policy'] = $finalNoShow;
    if ($hasCustMsg) $policy['customer_message'] = $finalCustMsg;

    wb_ok(['policy' => $policy]);
} catch (Throwable $e) {
    error_log('[mobile/business/deposit-save.php] ' . $e->getMessage());
    wb_err('Kapora politikası kaydedilemedi.', 500, 'internal_error');
}
