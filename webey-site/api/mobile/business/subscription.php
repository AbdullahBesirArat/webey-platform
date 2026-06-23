<?php
declare(strict_types=1);
/**
 * api/mobile/business/subscription.php
 * GET — İşletmenin Webey abonelik durumunu döndürür (YALNIZCA GÖSTERİM).
 *
 * Faz 1 kuralları:
 *  - Salt-okunur. Ödeme / IBAN / "satın al" CTA YOK (payment_cta_enabled=false).
 *  - Eski web/iyzico `subscriptions` tablosuna BAKMAZ.
 *  - Mobil görünürlük gate'i bu endpointten ETKİLENMEZ (gate Faz 3).
 *  - Tablolar yoksa veya kayıt yoksa güvenli fallback döner; asla boş yanıt yok.
 *  - İç admin notları business app'e SIZDIRILMAZ (notes daima null).
 *
 * Auth: business/admin; yalnızca kendi işletmesi.
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';
require_once __DIR__ . '/_helpers.php';

wb_method('GET');

try {
    $auth       = mobile_auth($pdo, ['business', 'admin']);
    $ctx        = mobile_business_context($pdo, $auth);
    $businessId = (int)$ctx['business_id'];

    // Tablo yoksa kullanılacak sabit plan değerleri.
    $planDefaults = [
        'code'          => 'webey_business',
        'name'          => 'Webey İşletme Paketi',
        'monthly_price' => 2500.00,
        'trial_days'    => 30,
    ];

    // Plan kataloğu (business_subscription_plans) — varsa gerçek değer.
    $plan = $planDefaults;
    if (mobile_table_has_column($pdo, 'business_subscription_plans', 'id')) {
        $planStmt = $pdo->prepare(
            "SELECT code, name, monthly_price, trial_days
             FROM business_subscription_plans
             WHERE code = ? AND is_active = 1
             LIMIT 1"
        );
        $planStmt->execute([$planDefaults['code']]);
        $planRow = $planStmt->fetch();
        if ($planRow) {
            $plan = [
                'code'          => (string)$planRow['code'],
                'name'          => (string)$planRow['name'],
                'monthly_price' => (float)$planRow['monthly_price'],
                'trial_days'    => (int)$planRow['trial_days'],
            ];
        }
    }

    // İşletmenin en güncel abonelik kaydı (varsa).
    $sub = null;
    if (mobile_table_has_column($pdo, 'business_subscriptions', 'id')) {
        $subStmt = $pdo->prepare(
            "SELECT status, monthly_price, trial_started_at, trial_ends_at,
                    current_period_start, current_period_end, last_payment_at,
                    next_payment_due_at, payment_method
             FROM business_subscriptions
             WHERE business_id = ?
             ORDER BY id DESC
             LIMIT 1"
        );
        $subStmt->execute([$businessId]);
        $sub = $subStmt->fetch() ?: null;
    }

    $labels = [
        'trial'     => 'Deneme',
        'active'    => 'Aktif',
        'overdue'   => 'Ödeme Gecikti',
        'suspended' => 'Askıya Alındı',
        'cancelled' => 'İptal Edildi',
        'unknown'   => 'Tanımlanmadı',
    ];

    $daysLeft = static function (?string $dt): ?int {
        if (!$dt) {
            return null;
        }
        $ts = strtotime($dt);
        if ($ts === false) {
            return null;
        }
        $diff = $ts - time();
        return $diff > 0 ? (int)ceil($diff / 86400) : 0;
    };

    if ($sub) {
        $status = (string)$sub['status'];
        if (!isset($labels[$status])) {
            $status = 'unknown';
        }
        // Geri sayım: trial'da deneme bitişi, diğerlerinde dönem bitişi.
        $countdownEnd = $status === 'trial'
            ? ($sub['trial_ends_at'] ?? null)
            : ($sub['current_period_end'] ?? null);

        $subscription = [
            'status'              => $status,
            'status_label'        => $labels[$status],
            'source'              => 'record',
            'monthly_price'       => $sub['monthly_price'] !== null
                ? (float)$sub['monthly_price']
                : (float)$plan['monthly_price'],
            'trial_ends_at'       => $sub['trial_ends_at'] ?? null,
            'current_period_end'  => $sub['current_period_end'] ?? null,
            'next_payment_due_at' => $sub['next_payment_due_at'] ?? null,
            'payment_method'      => $sub['payment_method'] ?? null,
            'days_left'           => $daysLeft($countdownEnd !== null ? (string)$countdownEnd : null),
            'notes'               => null, // İç admin notu business app'e gösterilmez.
        ];
    } else {
        // Kayıt yok → güvenli türetilmiş GÖSTERİM (gate değil).
        // Deneme bitişi yalnızca işletmenin created_at'inden türetilir;
        // eski iyzico `subscriptions` tablosuna BAKILMAZ.
        $createdAt = null;
        try {
            $bStmt = $pdo->prepare("SELECT created_at FROM businesses WHERE id = ? LIMIT 1");
            $bStmt->execute([$businessId]);
            $createdAt = $bStmt->fetchColumn();
            $createdAt = $createdAt !== false ? (string)$createdAt : null;
        } catch (Throwable $e) {
            $createdAt = null;
        }

        $status      = 'unknown';
        $trialEndsAt = null;
        if ($createdAt) {
            $trialEndTs = strtotime($createdAt) + ((int)$plan['trial_days'] * 86400);
            if ($trialEndTs > time()) {
                $status      = 'trial';
                $trialEndsAt = date('Y-m-d H:i:s', $trialEndTs);
            }
        }

        $subscription = [
            'status'              => $status,
            'status_label'        => $labels[$status],
            'source'              => 'derived',
            'monthly_price'       => (float)$plan['monthly_price'],
            'trial_ends_at'       => $trialEndsAt,
            'current_period_end'  => null,
            'next_payment_due_at' => null,
            'payment_method'      => null,
            'days_left'           => $daysLeft($trialEndsAt),
            'notes'               => null,
        ];
    }

    wb_ok([
        'plan' => [
            'code'          => (string)$plan['code'],
            'name'          => (string)$plan['name'],
            'monthly_price' => (float)$plan['monthly_price'],
            'trial_days'    => (int)$plan['trial_days'],
        ],
        'subscription'       => $subscription,
        'billing_managed_by' => 'webey_team',
        'payment_cta_enabled' => false,
        'support_message'    => 'Ödeme ve fatura işlemleri Webey ekibi tarafından yönetilir.',
    ]);
} catch (Throwable $e) {
    error_log('[mobile/business/subscription.php] ' . $e->getMessage());
    wb_err('Abonelik bilgisi alınamadı. Lütfen tekrar deneyin.', 500, 'internal_error');
}
