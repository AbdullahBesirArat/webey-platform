<?php
declare(strict_types=1);
/**
 * api/billing/invoices.php — Fatura listesi
 * GET — admin auth gerekli
 */

require_once __DIR__ . '/../admin/_bootstrap.php';
wb_method('GET');

$userId = $user['user_id'];

try {
    $stmt = $pdo->prepare("
        SELECT i.id, i.plan_label AS planLabel, i.amount, i.status,
               i.created_at AS createdAt, s.start_date, s.end_date
        FROM invoices i
        LEFT JOIN subscriptions s ON s.id=i.subscription_id
        WHERE i.user_id=?
        ORDER BY i.created_at DESC
        LIMIT 50
    ");
    $stmt->execute([$userId]);
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    $invoices = array_map(function($r) {
        $period = '';
        if ($r['start_date'] && $r['end_date']) {
            $s = new DateTime($r['start_date']);
            $e = new DateTime($r['end_date']);
            $period = $s->format('d.m.Y') . ' – ' . $e->format('d.m.Y');
        }
        return [
            'id'        => $r['id'],
            'planLabel' => $r['planLabel'],
            'amount'    => (float)$r['amount'],
            'status'    => $r['status'],
            'createdAt' => $r['createdAt'],
            'period'    => $period,
        ];
    }, $rows);

    wb_ok(['invoices' => $invoices]);
} catch (Throwable $e) {
    error_log('[billing/invoices.php] ' . $e->getMessage());
    wb_ok(['invoices' => []]);
}