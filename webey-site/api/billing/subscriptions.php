<?php
declare(strict_types=1);
/**
 * api/billing/subscriptions.php
 * GET - Admin abonelik listesi.
 */

require_once __DIR__ . '/../admin/_bootstrap.php';
require_once __DIR__ . '/_plans.php';

wb_method('GET');

$userId = $user['user_id'];
$planLabels = array_map(
    static fn(array $plan): string => (string)$plan['label'],
    WB_PLANS
);

try {
    $userRow = $pdo->prepare("SELECT created_at FROM users WHERE id=? LIMIT 1");
    $userRow->execute([$userId]);
    $userRow = $userRow->fetch(PDO::FETCH_ASSOC);

    $stmt = $pdo->prepare("
        SELECT s.id, s.plan, s.status, s.price, s.start_date, s.end_date,
               s.cancel_at_period_end, s.cancelled_at, s.created_at,
               pc.code AS promo_code,
               pc.discount_type,
               pc.discount_value
        FROM subscriptions s
        LEFT JOIN promo_code_uses pcu ON pcu.subscription_id = s.id
        LEFT JOIN promo_codes pc ON pc.id = pcu.promo_id
        WHERE s.user_id = ?
        ORDER BY s.created_at DESC
    ");
    $stmt->execute([$userId]);
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    $subscriptions = [];
    $hasRealTrialRow = false;

    foreach ($rows as $row) {
        if ($row['plan'] === 'monthly_1' && (float)$row['price'] === 0.0 && $row['promo_code'] === null) {
            $hasRealTrialRow = true;
            break;
        }
    }

    if (!$hasRealTrialRow && $userRow) {
        $trialStart = new DateTime($userRow['created_at']);
        $trialEnd = (clone $trialStart)->modify('+30 days');
        $trialStatus = $trialEnd > new DateTime() ? 'trialing' : 'expired';

        $subscriptions[] = [
            'id'        => null,
            'plan'      => 'trial',
            'planLabel' => '1 Aylik Ucretsiz Baslangic Paketi',
            'status'    => $trialStatus,
            'price'     => 0,
            'startDate' => $trialStart->format('Y-m-d H:i:s'),
            'endDate'   => $trialEnd->format('Y-m-d H:i:s'),
            'isTrial'   => true,
            'promoCode' => null,
            'payLabel'  => 'Ucretsiz',
        ];
    }

    foreach ($rows as $row) {
        $isStarterFree = ($row['plan'] === 'monthly_1'
            && (float)$row['price'] === 0.0
            && $row['promo_code'] === null);

        if ($row['promo_code']) {
            $payLabel = $row['promo_code'];
        } elseif ($isStarterFree) {
            $payLabel = 'Ucretsiz Baslangic Paketi';
        } elseif ((float)$row['price'] === 0.0) {
            $payLabel = 'Ucretsiz';
        } else {
            $payLabel = 'Kredi / Banka Karti';
        }

        $subscriptions[] = [
            'id'          => (int)$row['id'],
            'plan'        => $row['plan'],
            'planLabel'   => $isStarterFree
                ? '1 Aylik Ucretsiz Baslangic Paketi'
                : ($planLabels[$row['plan']] ?? $row['plan']),
            'status'      => $row['status'],
            'statusLabel' => match($row['status']) {
                'active' => 'Aktif',
                'queued' => 'Bekliyor',
                'cancelled' => 'Iptal',
                'expired' => 'Suresi Doldu',
                'trialing' => 'Deneme',
                default => $row['status'],
            },
            'price'       => (float)$row['price'],
            'startDate'   => $row['start_date'],
            'endDate'     => $row['end_date'],
            'cancelledAt' => $row['cancelled_at'],
            'isTrial'     => $isStarterFree,
            'promoCode'   => $row['promo_code'],
            'payLabel'    => $payLabel,
        ];
    }

    $activeSub = null;
    $pendingSub = null;

    foreach ($rows as $row) {
        $isStarterFree = ($row['plan'] === 'monthly_1'
            && (float)$row['price'] === 0.0
            && $row['promo_code'] === null);

        if ($row['promo_code']) {
            $payLabel = $row['promo_code'];
        } elseif ($isStarterFree) {
            $payLabel = 'Ucretsiz Baslangic Paketi';
        } elseif ((float)$row['price'] === 0.0) {
            $payLabel = 'Ucretsiz';
        } else {
            $payLabel = 'Kredi / Banka Karti';
        }

        if ($row['status'] === 'active' && strtotime((string)$row['end_date']) > time() && !$activeSub) {
            $activeSub = [
                'plan'          => $row['plan'],
                'planLabel'     => $isStarterFree
                    ? '1 Aylik Ucretsiz Baslangic Paketi'
                    : ($planLabels[$row['plan']] ?? $row['plan']),
                'status'        => $row['status'],
                'startDate'     => $row['start_date'],
                'endDate'       => $row['end_date'],
                'price'         => (float)$row['price'],
                'promoCode'     => $row['promo_code'],
                'payLabel'      => $payLabel,
                'isStarterFree' => $isStarterFree,
            ];
        }

        if ($row['status'] === 'queued' && !$pendingSub) {
            $pendingSub = [
                'id'        => (int)$row['id'],
                'plan'      => $row['plan'],
                'planLabel' => $planLabels[$row['plan']] ?? $row['plan'],
                'status'    => 'queued',
                'startDate' => $row['start_date'],
                'endDate'   => $row['end_date'],
                'price'     => (float)$row['price'],
                'promoCode' => $row['promo_code'],
            ];
        }
    }

    wb_ok([
        'subscriptions' => $subscriptions,
        'activeSub' => $activeSub,
        'pendingSub' => $pendingSub,
    ]);
} catch (Throwable $e) {
    error_log('[billing/subscriptions] ' . $e->getMessage());
    wb_ok(['subscriptions' => [], 'activeSub' => null, 'pendingSub' => null]);
}
