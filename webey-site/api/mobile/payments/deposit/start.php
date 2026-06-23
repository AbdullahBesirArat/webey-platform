<?php
declare(strict_types=1);
/**
 * api/mobile/payments/deposit/start.php
 * POST — Müşteri için kapora ödeme sürecini başlatır.
 *
 * Body (JSON):
 *   appointment_id : int (zorunlu)
 *
 * Yanıt:
 *   checkout_token   : string  — iyzico token
 *   checkout_url     : string  — iyzico ödeme sayfası URL (asla boş dönmez)
 *   appointment_id   : int
 *   amount           : float
 *   already_paid     : bool    — önceden ödendiyse true, checkout_url boş gelir
 *   deposit_required : bool    — false ise kapora gerekmediği bilgisi
 */

require_once __DIR__ . '/../../_bootstrap.php';
require_once __DIR__ . '/../../_auth.php';
require_once __DIR__ . '/_helpers.php';

wb_method('POST');

$sess   = mobile_auth($pdo, 'customer');
$userId = $sess['user_id'];

$in            = wb_body();
$appointmentId = (int)($in['appointment_id'] ?? 0);

if ($appointmentId < 1) {
    wb_err('appointment_id zorunludur', 422, 'missing_appointment_id');
}

// ── appointment_payments tablosu henüz migration ile oluşturulmamış ─────────
if (!deposit_table_ready($pdo)) {
    wb_err('Ödeme sistemi şu an aktif değil', 503, 'payments_not_ready');
}

// ── Randevu sahipliği + deposit gereksinimi ─────────────────────────────────
$appt = deposit_get_appointment_for_customer($pdo, $appointmentId, $userId);
if ($appt === null) {
    wb_err('Randevu bulunamadı', 404, 'appointment_not_found');
}

if (!(bool)($appt['deposit_required'] ?? false)) {
    wb_ok([
        'appointment_id'   => $appointmentId,
        'already_paid'     => false,
        'deposit_required' => false,
        'message'          => 'Bu randevu için kapora gerekmemektedir',
    ]);
}

$amount = (float)($appt['deposit_amount'] ?? 0);
if ($amount <= 0) {
    wb_err('Kapora tutarı tanımlanmamış', 422, 'deposit_amount_not_set');
}

// Terminal durumlarda yeni ödeme başlatılamaz
$terminalStatuses = ['cancelled', 'rejected', 'declined', 'no_show'];
if (in_array(strtolower((string)$appt['status']), $terminalStatuses, true)) {
    wb_err('Bu randevu için ödeme başlatılamaz', 409, 'appointment_not_payable');
}

// ── Mevcut ödeme kaydı kontrolü ─────────────────────────────────────────────
$existing = deposit_find_payment($pdo, $appointmentId);

if ($existing !== null) {
    // Zaten ödendi → checkout başlatma
    if ($existing['status'] === 'paid') {
        wb_ok([
            'appointment_id'   => $appointmentId,
            'already_paid'     => true,
            'deposit_required' => true,
            'amount'           => (float)$existing['amount'],
            'paid_at'          => (string)$existing['paid_at'],
            'checkout_token'   => '',
            'checkout_url'     => '',
        ]);
    }

    // Fresh pending + URL kayıtlı → iyzico'ya ikinci istek atmadan dön
    $existingUrl   = (string)($existing['checkout_url'] ?? '');
    $existingToken = (string)($existing['checkout_token'] ?? '');
    $isFresh       = strtotime((string)$existing['updated_at']) > (time() - 1800);

    if ($existing['status'] === 'pending'
        && $existingToken !== ''
        && $existingUrl !== ''
        && $isFresh
    ) {
        wb_ok([
            'appointment_id'   => $appointmentId,
            'already_paid'     => false,
            'deposit_required' => true,
            'amount'           => (float)$existing['amount'],
            'checkout_token'   => $existingToken,
            'checkout_url'     => $existingUrl,
        ]);
    }
    // Diğer durumlar (fresh pending ama URL yok, eski pending, failed, cancelled):
    // aşağıya düşerek yeni checkout oluşturulacak.
}

// ── Müşteri bilgilerini DB'den çek ─────────────────────────────────────────
$custStmt = $pdo->prepare(
    "SELECT u.name AS user_name, u.email,
            c.first_name, c.last_name, c.phone
     FROM users u
     LEFT JOIN customers c ON c.user_id = u.id
     WHERE u.id = ? LIMIT 1"
);
$custStmt->execute([$userId]);
$cust = $custStmt->fetch();
if (!$cust) {
    wb_err('Müşteri bilgisi alınamadı', 500, 'customer_not_found');
}

$firstName    = trim((string)($cust['first_name'] ?? ''));
$lastName     = trim((string)($cust['last_name']  ?? ''));
$customerName = trim($firstName . ' ' . $lastName);
if ($customerName === '') {
    $customerName = trim((string)($cust['user_name'] ?? '')) ?: 'Müşteri';
}
$customerEmail = trim((string)($cust['email']  ?? ''));
$customerPhone = trim((string)($cust['phone']  ?? ''));

// ── İyzico checkout başlat ──────────────────────────────────────────────────
$result = deposit_provider_checkout_start(
    $appointmentId,
    $userId,
    $amount,
    $customerName,
    $customerEmail,
    $customerPhone
);

if (!$result['ok']) {
    wb_err($result['error'] ?? 'Ödeme başlatılamadı', 502, 'payment_provider_error');
}

// Provider checkout URL'i döndürmediyse güvenli hata ver
if (empty($result['checkout_url'])) {
    error_log('[deposit/start.php] Provider checkout_url boş döndü: appt=' . $appointmentId);
    wb_err('Ödeme sayfası adresi alınamadı', 502, 'provider_checkout_url_missing');
}

// ── Ödeme kaydını kaydet / güncelle ─────────────────────────────────────────
try {
    deposit_upsert_pending_payment(
        $pdo,
        $appointmentId,
        $userId,
        (int)$appt['business_id'],
        $amount,
        $result['checkout_token'],
        $result['conversation_id'],
        $result['checkout_url'],
        $existing
    );
} catch (Throwable $e) {
    error_log('[deposit/start.php] upsert: ' . $e->getMessage());
    wb_err('Ödeme kaydı oluşturulamadı', 500, 'internal_error');
}

wb_ok([
    'appointment_id'   => $appointmentId,
    'already_paid'     => false,
    'deposit_required' => true,
    'amount'           => $amount,
    'checkout_token'   => $result['checkout_token'],
    'checkout_url'     => $result['checkout_url'],
]);
