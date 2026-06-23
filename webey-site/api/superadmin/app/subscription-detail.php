<?php
declare(strict_types=1);
/**
 * api/superadmin/app/subscription-detail.php?business_id=...
 * GET — Tek işletmenin abonelik detayı + manuel ödeme + audit. READ-ONLY (Faz 1).
 *
 * Eski web/iyzico `subscriptions` için yalnızca var/yok bilgisi döner (detay yok).
 * Hiçbir INSERT/UPDATE/DELETE yok.
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/_helpers.php';
require_once __DIR__ . '/../../mobile/_business_visibility.php';
wb_method('GET');

$businessId = (int)($_GET['business_id'] ?? 0);
if ($businessId <= 0) {
    wb_err('Geçersiz işletme id', 400, 'invalid_id');
}

try {
    $visibilityJoin = wb_business_visibility_join_sql($pdo);
    $visibilitySelect = wb_business_visibility_select_sql($pdo);
    $biz = sa_row($pdo, "
        SELECT b.id, b.name, b.slug, b.type, b.status, b.owner_id, b.owner_name, b.phone,
               b.city, b.district, b.onboarding_completed, b.onboarding_step,
               b.created_at, b.updated_at
               $visibilitySelect
        FROM businesses b
        $visibilityJoin
        WHERE b.id = ?", [$businessId]);
    if (!$biz) {
        wb_err('İşletme bulunamadı', 404, 'not_found');
    }

    $visibility = wb_business_visibility_from_row($biz);

    $tableExists = static function (PDO $pdo, string $t): bool {
        return (bool)sa_val($pdo,
            "SELECT COUNT(*) FROM information_schema.tables
             WHERE table_schema = DATABASE() AND table_name = ?", [$t]);
    };

    // En güncel abonelik kaydı (+ plan).
    $subscription = null;
    if ($tableExists($pdo, 'business_subscriptions')) {
        $hasPlans = $tableExists($pdo, 'business_subscription_plans');
        $planJoin = $hasPlans ? 'LEFT JOIN business_subscription_plans p ON p.id = s.plan_id' : '';
        $planSel  = $hasPlans ? 'p.code AS plan_code, p.name AS plan_name,' : 'NULL AS plan_code, NULL AS plan_name,';
        $sub = sa_row($pdo, "
            SELECT s.id, {$planSel} s.status, s.monthly_price, s.trial_started_at, s.trial_ends_at,
                   s.current_period_start, s.current_period_end, s.last_payment_at,
                   s.next_payment_due_at, s.payment_method, s.notes,
                   s.created_by, s.updated_by, s.created_at, s.updated_at
            FROM business_subscriptions s
            {$planJoin}
            WHERE s.business_id = ?
            ORDER BY s.id DESC LIMIT 1", [$businessId]);
        $subscription = $sub ?: null;
    }

    // Manuel ödeme kayıtları (en yeni 20).
    $payments = [];
    if ($tableExists($pdo, 'business_subscription_payments')) {
        $payments = sa_rows($pdo, "
            SELECT id, subscription_id, amount, paid_at, method, period_start, period_end,
                   reference, notes, recorded_by, created_at
            FROM business_subscription_payments
            WHERE business_id = ?
            ORDER BY paid_at DESC, id DESC LIMIT 20", [$businessId]);
    }

    // Audit izi (en yeni 20).
    $audit = [];
    if ($tableExists($pdo, 'business_subscription_audit')) {
        $audit = sa_rows($pdo, "
            SELECT id, subscription_id, action, from_status, to_status, actor_user_id, created_at
            FROM business_subscription_audit
            WHERE business_id = ?
            ORDER BY id DESC LIMIT 20", [$businessId]);
    }

    // Plan kataloğu (referans).
    $plan = null;
    if ($tableExists($pdo, 'business_subscription_plans')) {
        $plan = sa_row($pdo, "
            SELECT code, name, monthly_price, trial_days, is_active
            FROM business_subscription_plans WHERE code = 'webey_business' LIMIT 1");
    }

    // Eski web/iyzico abonelik — yalnızca var/yok (detay YOK).
    $legacyExists = false;
    try {
        $legacyExists = (bool)sa_val($pdo,
            "SELECT COUNT(*) FROM subscriptions WHERE user_id = ?", [(int)$biz['owner_id']]);
    } catch (Throwable $e) {
        $legacyExists = false;
    }

    wb_ok([
        'business' => [
            'id'                   => (int)$biz['id'],
            'name'                 => $biz['name'],
            'status'               => $biz['status'],
            'type'                 => $biz['type'],
            'owner_name'           => $biz['owner_name'],
            'owner_phone_masked'   => sa_mask_phone($biz['phone']),
            'city'                 => $biz['city'],
            'district'             => $biz['district'],
            'onboarding_completed' => (bool)$biz['onboarding_completed'],
            'onboarding_step'      => (int)$biz['onboarding_step'],
            'subscription_status'   => $visibility['subscription_status'],
            'visibility_status'     => $visibility['visibility_status'],
            'customer_visible'      => $visibility['visibility_status'] !== 'hidden',
            'is_boosted'            => $visibility['is_boosted'],
            'boost_badge'           => $visibility['boost_badge'],
            'boost_ends_at'         => $visibility['boost_ends_at'],
            'profile_quality_score' => $visibility['profile_quality_score'],
            'created_at'           => $biz['created_at'],
            'updated_at'           => $biz['updated_at'],
        ],
        'subscription' => $subscription ? [
            'id'                   => (int)$subscription['id'],
            'plan_code'            => $subscription['plan_code'] ?? null,
            'plan_name'            => $subscription['plan_name'] ?? null,
            'status'               => (string)$subscription['status'],
            'monthly_price'        => $subscription['monthly_price'] !== null ? (float)$subscription['monthly_price'] : null,
            'trial_started_at'     => $subscription['trial_started_at'],
            'trial_ends_at'        => $subscription['trial_ends_at'],
            'current_period_start' => $subscription['current_period_start'],
            'current_period_end'   => $subscription['current_period_end'],
            'last_payment_at'      => $subscription['last_payment_at'],
            'next_payment_due_at'  => $subscription['next_payment_due_at'],
            'payment_method'       => $subscription['payment_method'],
            'notes'                => $subscription['notes'],
            'created_at'           => $subscription['created_at'],
            'updated_at'           => $subscription['updated_at'],
        ] : null,
        'plan' => $plan ? [
            'code'          => $plan['code'],
            'name'          => $plan['name'],
            'monthly_price' => (float)$plan['monthly_price'],
            'trial_days'    => (int)$plan['trial_days'],
            'is_active'     => (bool)$plan['is_active'],
        ] : null,
        'payments' => array_map(static fn(array $p): array => [
            'id'              => (int)$p['id'],
            'subscription_id' => $p['subscription_id'] !== null ? (int)$p['subscription_id'] : null,
            'amount'          => (float)$p['amount'],
            'paid_at'         => $p['paid_at'],
            'method'          => $p['method'],
            'period_start'    => $p['period_start'],
            'period_end'      => $p['period_end'],
            'reference'       => $p['reference'],
            'notes'           => $p['notes'],
            'created_at'      => $p['created_at'],
        ], $payments),
        'audit' => array_map(static fn(array $a): array => [
            'id'              => (int)$a['id'],
            'subscription_id' => $a['subscription_id'] !== null ? (int)$a['subscription_id'] : null,
            'action'          => $a['action'],
            'from_status'     => $a['from_status'],
            'to_status'       => $a['to_status'],
            'actor_user_id'   => $a['actor_user_id'] !== null ? (int)$a['actor_user_id'] : null,
            'created_at'      => $a['created_at'],
        ], $audit),
        'legacy_web_subscription_exists' => $legacyExists,
        'phase'     => 1,
        'read_only' => true,
    ]);
} catch (Throwable $e) {
    error_log('[superadmin/app/subscription-detail] ' . $e->getMessage());
    wb_err('Abonelik detayı yüklenemedi', 500, 'internal_error');
}
