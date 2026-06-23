<?php
declare(strict_types=1);
/**
 * api/mobile/business/deposit.php
 * GET — Token sahibi işletmenin kapora politikasını döner.
 *
 * Yanıt:
 *   policy : object
 *     - rate_pct         : int          — kapora oranı (%)
 *     - per_service      : bool         — hizmet bazında mı?
 *     - cancel_policy    : string       — esnek|siki|yok
 *
 * Tablo: deposit_policies (canlı şema)
 *   id int, business_id int UNIQUE, rate_pct tinyint DEFAULT 25,
 *   per_service tinyint(1) DEFAULT 0, cancel_policy varchar(20) DEFAULT 'esnek',
 *   updated_at datetime ON UPDATE CURRENT_TIMESTAMP
 *
 * Faz 8B — Bearer token zorunlu, business/admin tipi.
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';
require_once __DIR__ . '/_helpers.php';

wb_method('GET');

$auth       = mobile_auth($pdo, ['business', 'admin']);
$ctx        = mobile_business_context($pdo, $auth);
$businessId = (int)$ctx['business_id'];

try {
    // Hangi ek kolonlar mevcut?
    $cols = [];
    $colsStmt = $pdo->prepare(
        "SELECT COLUMN_NAME FROM information_schema.COLUMNS
         WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'deposit_policies'"
    );
    $colsStmt->execute();
    foreach ($colsStmt->fetchAll() as $c) {
        $cols[$c['COLUMN_NAME']] = true;
    }
    $extra = [];
    foreach ([
        'free_cancel_hours', 'late_cancel_enabled', 'late_cancel_rate_pct',
        'no_show_policy', 'customer_message',
    ] as $c) {
        if (isset($cols[$c])) $extra[] = $c;
    }
    $selectCols = 'rate_pct, per_service, cancel_policy'
        . ($extra ? ', ' . implode(', ', $extra) : '');

    $stmt = $pdo->prepare(
        "SELECT $selectCols FROM deposit_policies WHERE business_id = ? LIMIT 1"
    );
    $stmt->execute([$businessId]);
    $row = $stmt->fetch();

    $hasBusinessDepositRequired = mobile_table_has_column($pdo, 'businesses', 'deposit_required');
    $hasBusinessDepositAmount = mobile_table_has_column($pdo, 'businesses', 'deposit_amount');
    $businessDepositRequired = false;
    $businessDepositAmount = null;
    if ($hasBusinessDepositRequired || $hasBusinessDepositAmount) {
        $businessCols = []
        ;
        if ($hasBusinessDepositRequired) $businessCols[] = 'deposit_required';
        if ($hasBusinessDepositAmount) $businessCols[] = 'deposit_amount';
        $bizStmt = $pdo->prepare(
            'SELECT ' . implode(', ', $businessCols) . ' FROM businesses WHERE id = ? LIMIT 1'
        );
        $bizStmt->execute([$businessId]);
        $bizRow = $bizStmt->fetch();
        if ($bizRow) {
            $businessDepositRequired = $hasBusinessDepositRequired
                ? (bool)($bizRow['deposit_required'] ?? false)
                : false;
            $businessDepositAmount = $hasBusinessDepositAmount && ($bizRow['deposit_amount'] ?? null) !== null
                ? (float)$bizRow['deposit_amount']
                : null;
        }
    }

    $ratePct = $row ? (int)$row['rate_pct'] : 25;
    if ($ratePct > 0 && !in_array($ratePct, [25, 50, 75, 100], true)) {
        $ratePct = 25;
    }
    $fixedAmount = $businessDepositAmount !== null && $businessDepositAmount > 0
        ? round($businessDepositAmount, 2)
        : null;
    $depositMode = ($ratePct <= 0 && $businessDepositRequired && $fixedAmount !== null)
        ? 'fixed'
        : 'percent';
    $depositRequired = $depositMode === 'fixed'
        ? true
        : $ratePct > 0;

    $policy = [
        'rate_pct'      => $ratePct,
        'per_service'   => $row ? (bool)$row['per_service']     : false,
        'cancel_policy' => $row ? (string)$row['cancel_policy'] : 'esnek',
        'deposit_required' => $depositRequired,
        'deposit_mode' => $depositMode,
        'fixed_deposit_amount' => $fixedAmount,
    ];
    if (isset($cols['free_cancel_hours'])) {
        $policy['free_cancel_hours'] = $row && $row['free_cancel_hours'] !== null
            ? (int)$row['free_cancel_hours'] : 24;
    }
    if (isset($cols['late_cancel_enabled'])) {
        $policy['late_cancel_enabled'] = $row ? (bool)$row['late_cancel_enabled'] : false;
    }
    if (isset($cols['late_cancel_rate_pct'])) {
        $policy['late_cancel_rate_pct'] = $row && $row['late_cancel_rate_pct'] !== null
            ? (int)$row['late_cancel_rate_pct'] : 50;
    }
    if (isset($cols['no_show_policy'])) {
        $policy['no_show_policy'] = $row && $row['no_show_policy'] !== null
            ? (string)$row['no_show_policy'] : 'forfeit';
    }
    if (isset($cols['customer_message'])) {
        $policy['customer_message'] = $row && $row['customer_message'] !== null
            ? (string)$row['customer_message'] : null;
    }

    wb_ok(['policy' => $policy]);
} catch (Throwable $e) {
    error_log('[mobile/business/deposit.php] ' . $e->getMessage());
    wb_err('Kapora politikası alınamadı.', 500, 'internal_error');
}
