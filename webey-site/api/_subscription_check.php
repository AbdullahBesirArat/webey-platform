<?php
/**
 * _subscription_check.php
 * ─────────────────────────────────────────────────────────
 * Merkezi abonelik durum kontrol yardımcısı.
 *
 * Kullanım:
 *   require __DIR__ . '/../_subscription_check.php';
 *   $sub = getSubscriptionStatus($pdo, $userId);
 *   if (!$sub['active']) { ... }
 *
 * Dönüş: [
 *   'active'     => bool,   // randevu + yayın için yeterli mi?
 *   'trialing'   => bool,   // deneme süresi mi?
 *   'plan'       => string, // 'trial' | 'monthly_1' | ... | 'none'
 *   'end_date'   => string|null,
 *   'days_left'  => int,
 *   'reason'     => string, // neden pasif (UI mesajı için)
 * ]
 */
declare(strict_types=1);

if (!function_exists('getSubscriptionStatus')) {

    function getSubscriptionStatus(PDO $pdo, int $userId): array
    {
        $now = new DateTimeImmutable();

        /* ── 1. Aktif abonelik var mı? ── */
        try {
            $stmt = $pdo->prepare("
                SELECT plan, status, end_date, cancel_at_period_end
                FROM subscriptions
                WHERE user_id = ?
                  AND status = 'active'
                  AND end_date > NOW()
                ORDER BY end_date DESC
                LIMIT 1
            ");
            $stmt->execute([$userId]);
            $sub = $stmt->fetch();
        } catch (Throwable $e) {
            $sub = null; // subscriptions tablosu henüz yoksa graceful
        }

        if ($sub) {
            $end      = new DateTimeImmutable($sub['end_date']);
            $daysLeft = (int)$now->diff($end)->days;
            return [
                'active'     => true,
                'trialing'   => false,
                'plan'       => $sub['plan'],
                'end_date'   => $sub['end_date'],
                'days_left'  => $daysLeft,
                'cancel_soon'=> (bool)$sub['cancel_at_period_end'],
                'reason'     => '',
            ];
        }

        /* ── 2. Deneme süresi içinde mi? (30 gün) ── */
        try {
            $stmt = $pdo->prepare("
                SELECT created_at FROM users WHERE id = ? LIMIT 1
            ");
            $stmt->execute([$userId]);
            $userRow = $stmt->fetch();
        } catch (Throwable $e) {
            $userRow = null;
        }

        if ($userRow && $userRow['created_at']) {
            $trialEnd = (new DateTimeImmutable($userRow['created_at']))->modify('+30 days');
            if ($now < $trialEnd) {
                $daysLeft = (int)$now->diff($trialEnd)->days;
                return [
                    'active'     => true,
                    'trialing'   => true,
                    'plan'       => 'trial',
                    'end_date'   => $trialEnd->format('Y-m-d H:i:s'),
                    'days_left'  => $daysLeft,
                    'cancel_soon'=> false,
                    'reason'     => '',
                ];
            }
        }

        /* ── 3. Pasif ── */
        return [
            'active'     => false,
            'trialing'   => false,
            'plan'       => 'none',
            'end_date'   => null,
            'days_left'  => 0,
            'cancel_soon'=> false,
            'reason'     => 'subscription_expired',
        ];
    }


    /**
     * getBusinessSubscriptionStatus — business_id üzerinden kontrol
     * (owner_id'yi businesses tablosundan çeker)
     */
    function getBusinessSubscriptionStatus(PDO $pdo, int $businessId): array
    {
        try {
            $stmt = $pdo->prepare("SELECT owner_id FROM businesses WHERE id = ? LIMIT 1");
            $stmt->execute([$businessId]);
            $row = $stmt->fetch();
        } catch (Throwable $e) {
            $row = null;
        }

        if (!$row) {
            return [
                'active' => false, 'trialing' => false, 'plan' => 'none',
                'end_date' => null, 'days_left' => 0, 'cancel_soon' => false,
                'reason' => 'business_not_found',
            ];
        }

        return getSubscriptionStatus($pdo, (int)$row['owner_id']);
    }
}