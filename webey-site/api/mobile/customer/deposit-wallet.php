<?php
declare(strict_types=1);
/**
 * api/mobile/customer/deposit-wallet.php
 * GET — Giriş yapan müşterinin kapora & cüzdan özeti (gerçek randevu verisi).
 *
 * MVP: Webey online tahsilat yapmaz. Kapora doğrudan salon IBAN'ına gider;
 *      işletme onaylayınca "paid", iade edilince "refunded" olur. Bu endpoint
 *      mock/demo veri DÖNDÜRMEZ; yalnızca müşterinin kendi randevularını sayar.
 *
 * Kimlik: customer_user_id veya normalize edilmiş telefon eşleşmesi.
 *
 * deposit_status değerleri:
 *   pending               → kapora bekleniyor (müşteri henüz göndermedi)
 *   customer_marked_sent  → müşteri gönderdiğini bildirdi, işletme onayı bekleniyor
 *   paid                  → işletme onayladı (ödenen)
 *   not_received          → işletme almadığını bildirdi
 *   refunded              → iade edildi
 *
 * Response:
 *   { "ok": true, "data": {
 *       "summary": { "paid_total", "pending_total", "refunded_total", "currency" },
 *       "items": [ { "appointment_id","status","label","amount","currency",
 *                    "business_name","service_name","appointment_start","event_at" } ]
 *   } }
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';

wb_method('GET');

$session = mobile_auth($pdo, 'customer');
$userId  = (int)$session['user_id'];

$empty = [
    'summary' => [
        'paid_total'     => 0.0,
        'pending_total'  => 0.0,
        'refunded_total' => 0.0,
        'currency'       => 'TRY',
    ],
    'items' => [],
];

$hasDepositStatus = mobile_table_has_column($pdo, 'appointments', 'deposit_status');
$hasDepositAmount = mobile_table_has_column($pdo, 'appointments', 'deposit_amount');

if (!$hasDepositStatus || !$hasDepositAmount) {
    wb_ok($empty);
}

$hasDepositRequired = mobile_table_has_column($pdo, 'appointments', 'deposit_required');
$hasDepositPaidAt   = mobile_table_has_column($pdo, 'appointments', 'deposit_paid_at');
$hasDepositMarkedAt = mobile_table_has_column($pdo, 'appointments', 'deposit_marked_at');

try {
    // ── Kimlik: customer_user_id veya telefon (son 10 hane) ────────────────────
    $cPhoneStmt = $pdo->prepare('SELECT phone FROM customers WHERE user_id = ? LIMIT 1');
    $cPhoneStmt->execute([$userId]);
    $rawPhone = preg_replace('/\D/', '', (string)($cPhoneStmt->fetchColumn() ?: ''));
    $phone10  = $rawPhone !== '' ? substr($rawPhone, -10) : '';

    if ($phone10 !== '') {
        $identitySql = "(a.customer_user_id = ? OR RIGHT(REPLACE(REPLACE(REPLACE(COALESCE(a.customer_phone,''),'+',''),' ',''),'-',''), 10) = ?)";
        $identityParams = [$userId, $phone10];
    } else {
        $identitySql = 'a.customer_user_id = ?';
        $identityParams = [$userId];
    }

    // Olay zamanı için en uygun kolon.
    $eventCol = 'a.updated_at';
    if ($hasDepositPaidAt && $hasDepositMarkedAt) {
        $eventCol = 'COALESCE(a.deposit_paid_at, a.deposit_marked_at, a.updated_at)';
    } elseif ($hasDepositPaidAt) {
        $eventCol = 'COALESCE(a.deposit_paid_at, a.updated_at)';
    } elseif ($hasDepositMarkedAt) {
        $eventCol = 'COALESCE(a.deposit_marked_at, a.updated_at)';
    }

    // ── Özet toplamlar ─────────────────────────────────────────────────────────
    $sumStmt = $pdo->prepare(
        "SELECT a.deposit_status AS st, COALESCE(SUM(a.deposit_amount), 0) AS amt
           FROM appointments a
          WHERE $identitySql
            AND a.deposit_amount IS NOT NULL
            AND a.deposit_status IN ('paid','refunded')
          GROUP BY a.deposit_status"
    );
    $sumStmt->execute($identityParams);
    $paidTotal = 0.0;
    $refundedTotal = 0.0;
    foreach ($sumStmt->fetchAll() as $row) {
        if (($row['st'] ?? '') === 'paid') {
            $paidTotal = (float)$row['amt'];
        } elseif (($row['st'] ?? '') === 'refunded') {
            $refundedTotal = (float)$row['amt'];
        }
    }

    // Onay bekleyen: müşteri göndermiş ama henüz onaylanmamış (veya kapora bekleniyor),
    // randevu iptal/terminal değil.
    $reqClause = $hasDepositRequired ? 'AND (a.deposit_required = 1 OR a.deposit_amount > 0)' : 'AND a.deposit_amount > 0';
    $pendStmt = $pdo->prepare(
        "SELECT COALESCE(SUM(a.deposit_amount), 0) AS amt
           FROM appointments a
          WHERE $identitySql
            AND a.deposit_status IN ('pending','customer_marked_sent')
            AND a.status NOT IN ('cancelled','rejected','declined','no_show')
            $reqClause"
    );
    $pendStmt->execute($identityParams);
    $pendingTotal = (float)($pendStmt->fetchColumn() ?: 0);

    // ── Son kapora hareketleri ─────────────────────────────────────────────────
    $itemsStmt = $pdo->prepare(
        "SELECT a.id AS appointment_id,
                a.deposit_status AS st,
                a.deposit_amount AS amt,
                a.start_at AS appointment_start,
                $eventCol AS event_at,
                s.name AS service_name,
                b.name AS business_name
           FROM appointments a
           LEFT JOIN services   s ON s.id = a.service_id
           LEFT JOIN businesses b ON b.id = a.business_id
          WHERE $identitySql
            AND a.deposit_amount IS NOT NULL
            AND a.deposit_status IN ('paid','refunded','customer_marked_sent','pending','not_received')
          ORDER BY $eventCol DESC
          LIMIT 50"
    );
    $itemsStmt->execute($identityParams);

    $items = [];
    foreach ($itemsStmt->fetchAll() as $row) {
        $st = (string)($row['st'] ?? '');
        $label = match ($st) {
            'paid'                 => 'Onaylandı',
            'refunded'             => 'İade edildi',
            'customer_marked_sent' => 'Onay bekliyor',
            'not_received'         => 'Alınamadı',
            default                => 'Bekliyor',
        };
        $items[] = [
            'appointment_id'    => (int)$row['appointment_id'],
            'status'            => $st,
            'label'             => $label,
            'amount'            => $row['amt'] !== null ? (float)$row['amt'] : 0.0,
            'currency'          => 'TRY',
            'business_name'     => (string)($row['business_name'] ?? ''),
            'service_name'      => $row['service_name'] !== null ? (string)$row['service_name'] : null,
            'appointment_start' => (string)($row['appointment_start'] ?? ''),
            'event_at'          => (string)($row['event_at'] ?? ''),
        ];
    }

    wb_ok([
        'summary' => [
            'paid_total'     => $paidTotal,
            'pending_total'  => $pendingTotal,
            'refunded_total' => $refundedTotal,
            'currency'       => 'TRY',
        ],
        'items' => $items,
    ]);
} catch (Throwable $e) {
    error_log('[mobile/customer/deposit-wallet.php] ' . $e->getMessage());
    wb_err('Kapora bilgileri alınamadı.', 500, 'internal_error');
}
