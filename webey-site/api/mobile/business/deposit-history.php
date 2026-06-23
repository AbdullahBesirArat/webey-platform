<?php
declare(strict_types=1);
/**
 * api/mobile/business/deposit-history.php
 * GET — Salonun kapora hareketleri (gerçek randevu kayıtları).
 *
 * MVP: Webey online tahsilat yapmaz. Kapora doğrudan salon IBAN'ına gelir,
 *      salon "alındı / iade edildi / not_received" olarak manuel işaretler.
 *      Bu endpoint mock/demo veri döndürmez.
 *
 * Query:
 *   range : 'month' (varsayılan, içinde bulunulan ay)
 *
 * Response:
 *   {
 *     "ok": true,
 *     "data": {
 *       "summary": {
 *         "month_total_collected": float,
 *         "month_deposit_collected": float,
 *         "pending_amount": float,
 *         "refunded_amount": float,
 *         "month_change_percent": float|null
 *       },
 *       "items": [
 *         {
 *           "id", "appointment_id", "type", "status", "amount", "currency",
 *           "customer_name", "service_name",
 *           "appointment_start", "created_at", "label"
 *         }
 *       ]
 *     }
 *   }
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';
require_once __DIR__ . '/_helpers.php';

wb_method('GET');

$auth = mobile_auth($pdo, ['business', 'admin']);
$ctx = mobile_business_context($pdo, $auth);
$businessId = (int)$ctx['business_id'];

$empty = [
    'summary' => [
        'month_total_collected' => 0.0,
        'month_deposit_collected' => 0.0,
        'pending_amount' => 0.0,
        'refunded_amount' => 0.0,
        'month_change_percent' => null,
    ],
    'items' => [],
];

$hasDepositStatus = mobile_table_has_column($pdo, 'appointments', 'deposit_status');
$hasDepositAmount = mobile_table_has_column($pdo, 'appointments', 'deposit_amount');
$hasDepositRequired = mobile_table_has_column($pdo, 'appointments', 'deposit_required');
$hasDepositPaidAt = mobile_table_has_column($pdo, 'appointments', 'deposit_paid_at');
$hasDepositMarkedAt = mobile_table_has_column($pdo, 'appointments', 'deposit_marked_at');

if (!$hasDepositStatus || !$hasDepositAmount) {
    wb_ok($empty);
}

try {
    $tz = new DateTimeZone('Europe/Istanbul');
    $now = new DateTimeImmutable('now', $tz);
    $monthStart = new DateTimeImmutable($now->format('Y-m-01 00:00:00'), $tz);
    $monthEnd = $monthStart->modify('+1 month');
    $prevStart = $monthStart->modify('-1 month');

    $startStr = $monthStart->format('Y-m-d H:i:s');
    $endStr = $monthEnd->format('Y-m-d H:i:s');
    $prevStartStr = $prevStart->format('Y-m-d H:i:s');

    $eventCol = $hasDepositMarkedAt ? 'a.deposit_marked_at' : 'a.updated_at';

    // ── Items (kapora hareketleri) ───────────────────────────────────────────
    $itemsStmt = $pdo->prepare(
        "SELECT a.id AS appointment_id,
                a.deposit_status,
                a.deposit_amount,
                a.start_at AS appointment_start,
                $eventCol AS event_at,
                a.customer_name,
                s.name AS service_name
           FROM appointments a
           LEFT JOIN services s ON s.id = a.service_id
          WHERE a.business_id = ?
            AND a.deposit_status IS NOT NULL
            AND a.deposit_status IN ('paid','refunded','not_received','pending')
            AND $eventCol IS NOT NULL
            AND $eventCol >= ?
            AND $eventCol <  ?
          ORDER BY $eventCol DESC
          LIMIT 200"
    );
    $itemsStmt->execute([$businessId, $startStr, $endStr]);

    $items = [];
    foreach ($itemsStmt->fetchAll() as $row) {
        $status = (string)($row['deposit_status'] ?? '');
        $type = match ($status) {
            'paid' => 'deposit_collected',
            'refunded' => 'deposit_refunded',
            'not_received' => 'deposit_not_received',
            default => 'deposit_pending',
        };
        $label = match ($status) {
            'paid' => 'Kapora alındı',
            'refunded' => 'İade edildi',
            'not_received' => 'Kapora alınmadı',
            default => 'Kapora bekleniyor',
        };
        $items[] = [
            'id' => (string)$row['appointment_id'],
            'appointment_id' => (int)$row['appointment_id'],
            'type' => $type,
            'status' => $status,
            'amount' => $row['deposit_amount'] !== null ? (float)$row['deposit_amount'] : 0.0,
            'currency' => 'TRY',
            'customer_name' => (string)($row['customer_name'] ?? ''),
            'service_name' => $row['service_name'] !== null ? (string)$row['service_name'] : null,
            'appointment_start' => (string)($row['appointment_start'] ?? ''),
            'created_at' => (string)($row['event_at'] ?? ''),
            'label' => $label,
        ];
    }

    // ── Summary (bu ay) ──────────────────────────────────────────────────────
    $sumStmt = $pdo->prepare(
        "SELECT a.deposit_status, COALESCE(SUM(a.deposit_amount), 0) AS amt
           FROM appointments a
          WHERE a.business_id = ?
            AND $eventCol IS NOT NULL
            AND $eventCol >= ?
            AND $eventCol <  ?
            AND a.deposit_status IN ('paid','refunded')
          GROUP BY a.deposit_status"
    );
    $sumStmt->execute([$businessId, $startStr, $endStr]);
    $collected = 0.0;
    $refunded = 0.0;
    foreach ($sumStmt->fetchAll() as $row) {
        if (($row['deposit_status'] ?? '') === 'paid') {
            $collected = (float)$row['amt'];
        } elseif (($row['deposit_status'] ?? '') === 'refunded') {
            $refunded = (float)$row['amt'];
        }
    }

    // Bekleyen: deposit_required AND status NOT cancelled AND deposit_status not paid/refunded.
    $pending = 0.0;
    if ($hasDepositRequired) {
        $pendStmt = $pdo->prepare(
            "SELECT COALESCE(SUM(a.deposit_amount), 0) AS amt
               FROM appointments a
              WHERE a.business_id = ?
                AND a.deposit_required = 1
                AND (a.deposit_status IS NULL
                     OR a.deposit_status IN ('pending','not_received'))
                AND a.status NOT IN ('cancelled','rejected','declined','no_show')
                AND a.start_at >= ?"
        );
        $pendStmt->execute([$businessId, $now->format('Y-m-d 00:00:00')]);
        $pending = (float)($pendStmt->fetchColumn() ?: 0);
    }

    // Önceki ay karşılaştırması (collected toplamı).
    $prevStmt = $pdo->prepare(
        "SELECT COALESCE(SUM(a.deposit_amount), 0) AS amt
           FROM appointments a
          WHERE a.business_id = ?
            AND a.deposit_status = 'paid'
            AND $eventCol IS NOT NULL
            AND $eventCol >= ?
            AND $eventCol <  ?"
    );
    $prevStmt->execute([$businessId, $prevStartStr, $startStr]);
    $prevCollected = (float)($prevStmt->fetchColumn() ?: 0);

    $monthChange = null;
    if ($prevCollected > 0) {
        $monthChange = round((($collected - $prevCollected) / $prevCollected) * 100, 1);
    }

    wb_ok([
        'summary' => [
            // MVP: Webey ayrı bir full-payment tablosu kullanmıyor.
            // Tahsil edilen = kapora alındı toplamı.
            'month_total_collected' => $collected,
            'month_deposit_collected' => $collected,
            'pending_amount' => $pending,
            'refunded_amount' => $refunded,
            'month_change_percent' => $monthChange,
        ],
        'items' => $items,
    ]);
} catch (Throwable $e) {
    error_log('[mobile/business/deposit-history.php] ' . $e->getMessage());
    wb_err('Kapora geçmişi alınamadı.', 500, 'internal_error');
}
