<?php
declare(strict_types=1);
/**
 * api/mobile/business/invoices.php
 * GET — Webey komisyon/fatura geçmişi.
 *
 * MVP: Webey kapora tahsil etmiyor; komisyon/abonelik billing aktif değil.
 *      Bu endpoint mock fatura döndürmez; gerçek tablo yoksa boş liste döner.
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';
require_once __DIR__ . '/_helpers.php';

wb_method('GET');

$auth = mobile_auth($pdo, ['business', 'admin']);
$ctx = mobile_business_context($pdo, $auth);
$businessId = (int)$ctx['business_id'];

$summary = [
    'commission_month' => 0.0,
    'unpaid_balance' => 0.0,
    'last_invoice_date' => null,
    'last_invoice_amount' => null,
];
$items = [];

// İleride invoices tablosu eklendiğinde buradan beslenir.
try {
    $check = $pdo->prepare(
        "SELECT COUNT(*) FROM information_schema.TABLES
          WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'business_invoices'"
    );
    $check->execute();
    if ((int)$check->fetchColumn() > 0) {
        $stmt = $pdo->prepare(
            "SELECT id, invoice_no, issued_at, due_at, status,
                    COALESCE(total_amount, 0) AS total_amount,
                    COALESCE(commission_amount, 0) AS commission_amount,
                    pdf_url
               FROM business_invoices
              WHERE business_id = ?
              ORDER BY issued_at DESC
              LIMIT 50"
        );
        $stmt->execute([$businessId]);
        foreach ($stmt->fetchAll() ?: [] as $row) {
            $items[] = [
                'id' => (string)$row['id'],
                'invoice_no' => (string)($row['invoice_no'] ?? ''),
                'issued_at' => (string)($row['issued_at'] ?? ''),
                'due_at' => (string)($row['due_at'] ?? ''),
                'status' => (string)($row['status'] ?? 'unknown'),
                'total_amount' => (float)$row['total_amount'],
                'commission_amount' => (float)$row['commission_amount'],
                'currency' => 'TRY',
                'pdf_url' => $row['pdf_url'] ?? null,
            ];
        }
        if (!empty($items)) {
            $summary['last_invoice_date'] = $items[0]['issued_at'];
            $summary['last_invoice_amount'] = $items[0]['total_amount'];
        }
    }
} catch (Throwable $e) {
    error_log('[mobile/business/invoices.php] ' . $e->getMessage());
}

wb_ok([
    'summary' => $summary,
    'items' => $items,
    'billing_active' => false,
    'message' => 'Webey komisyon ve fatura sistemi aktif olduğunda faturalarınız burada görünecek.',
]);
