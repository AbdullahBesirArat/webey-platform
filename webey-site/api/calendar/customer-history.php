<?php
declare(strict_types=1);
/**
 * api/calendar/customer-history.php
 * GET ?phone=05xxxxxxxxx — Müşteri bilgisi + geçmiş randevular
 */

require_once __DIR__ . '/../admin/_bootstrap.php';
wb_method('GET');

$bid = $user['business_id'];
if (!$bid) wb_err('İşletme bulunamadı', 404, 'business_not_found');

$phone = trim($_GET['phone'] ?? '');
if ($phone === '') wb_err('phone zorunlu', 400, 'missing_phone');

$phoneNorm = preg_replace('/\D/', '', $phone);

try {
    $stmt = $pdo->prepare("
        SELECT customer_name AS name, customer_phone AS phone, customer_email AS email,
               COUNT(*) AS totalVisits, MAX(start_at) AS lastVisit
        FROM appointments
        WHERE business_id = ?
          AND REGEXP_REPLACE(customer_phone,'[^0-9]','') = ?
        GROUP BY customer_name, customer_phone, customer_email
        ORDER BY lastVisit DESC
        LIMIT 1
    ");
    $stmt->execute([$bid, $phoneNorm]);
    $customer = $stmt->fetch();

    wb_ok(['customer' => $customer ? [
        'name'        => $customer['name'],
        'phone'       => $customer['phone'],
        'email'       => $customer['email'],
        'totalVisits' => (int)$customer['totalVisits'],
        'lastVisit'   => $customer['lastVisit'],
    ] : null]);

} catch (Throwable $e) {
    error_log('[calendar/customer-history] ' . $e->getMessage());
    wb_err('Müşteri geçmişi yüklenemedi', 500, 'internal_error');
}