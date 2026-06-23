<?php
declare(strict_types=1);
/**
 * api/superadmin/business-detail.php
 * GET ?user_id=X — Bir adminin tüm plan/ödeme geçmişi
 */

require_once __DIR__ . '/_bootstrap.php';
wb_method('GET');

$userId = (int)($_GET['user_id'] ?? 0);
if (!$userId) wb_err('user_id zorunlu', 400, 'missing_user_id');

try {
    $uStmt = $pdo->prepare("SELECT u.id, u.email, u.name, u.created_at, u.last_login_at, b.id AS biz_id, b.name AS biz_name, b.status AS biz_status, b.city, b.district, b.phone AS biz_phone, b.created_at AS biz_created_at FROM users u LEFT JOIN businesses b ON b.owner_id=u.id WHERE u.id=? AND u.role IN ('admin','superadmin') LIMIT 1");
    $uStmt->execute([$userId]);
    $uRow = $uStmt->fetch(PDO::FETCH_ASSOC);
    if (!$uRow) wb_err('Kullanıcı bulunamadı', 404, 'not_found');

    $subStmt = $pdo->prepare("SELECT s.id, s.plan, s.status, s.price, s.start_date, s.end_date, s.cancelled_at, s.cancel_at_period_end, s.created_at, pc.code AS promo_code, pc.discount_type, pc.discount_value FROM subscriptions s LEFT JOIN promo_code_uses pcu ON pcu.subscription_id=s.id LEFT JOIN promo_codes pc ON pc.id=pcu.promo_id WHERE s.user_id=? ORDER BY s.created_at DESC");
    $subStmt->execute([$userId]);
    $subs = $subStmt->fetchAll(PDO::FETCH_ASSOC);

    $invStmt = $pdo->prepare('SELECT id, subscription_id, user_id, plan_label, amount, status, iyzico_payment_id, pdf_url, created_at, paid_at FROM invoices WHERE user_id = ? ORDER BY created_at DESC LIMIT 50');
    $invStmt->execute([$userId]);
    $invoices = $invStmt->fetchAll(PDO::FETCH_ASSOC);

    $activeSub = null;
    foreach ($subs as $s) {
        if (in_array($s['status'], ['active','trialing'], true)) { $activeSub = $s; break; }
    }
    $totalPaid = (float)array_sum(array_column(array_filter($subs, fn($s) => $s['status'] === 'active'), 'price'));

    wb_ok(['user' => $uRow, 'subs' => $subs, 'invoices' => $invoices, 'active_sub' => $activeSub, 'total_paid' => $totalPaid, 'sub_count' => count($subs)]);

} catch (Throwable $e) {
    error_log('[superadmin/business-detail] ' . $e->getMessage());
    wb_err('Detay yüklenemedi', 500, 'internal_error');
}