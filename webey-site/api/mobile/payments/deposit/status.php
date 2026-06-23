<?php
declare(strict_types=1);
/**
 * api/mobile/payments/deposit/status.php
 * GET — Randevunun kapora ödeme durumunu döner.
 *
 * Query params:
 *   appointment_id : int (zorunlu)
 *
 * Yanıt deposit_status değerleri:
 *   not_required — randevuda kapora gerekmez
 *   not_started  — kapora gerekli ama ödeme başlatılmamış
 *   pending      — ödeme başlatıldı, sonuç bekleniyor
 *   paid         — ödeme tamamlandı
 *   failed       — ödeme başarısız veya hata
 *   refunded     — ödeme iade edildi
 *   cancelled    — ödeme iptal edildi
 */

require_once __DIR__ . '/../../_bootstrap.php';
require_once __DIR__ . '/../../_auth.php';
require_once __DIR__ . '/_helpers.php';

wb_method('GET');

$sess   = mobile_auth($pdo, 'customer');
$userId = $sess['user_id'];

$appointmentId = mobile_int_param('appointment_id', 0) ?? 0;

if ($appointmentId < 1) {
    wb_err('appointment_id zorunludur', 422, 'missing_appointment_id');
}

// ── Randevu sahipliği + deposit gereksinimi ─────────────────────────────────
$appt = deposit_get_appointment_for_customer($pdo, $appointmentId, $userId);
if ($appt === null) {
    wb_err('Randevu bulunamadı', 404, 'appointment_not_found');
}

$depositRequired = (bool)($appt['deposit_required'] ?? false);
$depositAmount   = $appt['deposit_amount'] !== null ? (float)$appt['deposit_amount'] : null;

if (!$depositRequired) {
    wb_ok([
        'appointment_id'   => $appointmentId,
        'deposit_status'   => 'not_required',
        'deposit_required' => false,
        'amount'           => null,
        'paid_at'          => null,
    ]);
}

// ── Ödeme kaydını kontrol et ─────────────────────────────────────────────────
if (!deposit_table_ready($pdo)) {
    wb_ok([
        'appointment_id'   => $appointmentId,
        'deposit_status'   => 'not_started',
        'deposit_required' => true,
        'amount'           => $depositAmount,
        'paid_at'          => null,
    ]);
}

$payment = deposit_find_payment($pdo, $appointmentId);

if ($payment === null) {
    wb_ok([
        'appointment_id'   => $appointmentId,
        'deposit_status'   => 'not_started',
        'deposit_required' => true,
        'amount'           => $depositAmount,
        'paid_at'          => null,
    ]);
}

$status           = (string)($payment['status'] ?? 'pending');
$normalizedStatus = match ($status) {
    'paid'      => 'paid',
    'refunded'  => 'refunded',
    'cancelled' => 'cancelled',
    'failed',
    'error'     => 'failed',
    default     => 'pending',
};

wb_ok([
    'appointment_id'   => $appointmentId,
    'deposit_status'   => $normalizedStatus,
    'deposit_required' => true,
    'amount'           => $payment['amount'] !== null ? (float)$payment['amount'] : $depositAmount,
    'paid_at'          => $payment['paid_at'] ?? null,
]);
