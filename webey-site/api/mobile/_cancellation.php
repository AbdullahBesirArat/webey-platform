<?php
declare(strict_types=1);
/**
 * api/mobile/_cancellation.php
 * İptal / geç iptal / no-show finansal motoru — tek otorite.
 *
 * KRİTİK KURAL: Kesinti/iade YALNIZCA gerçekten ödenmiş kapora üzerinden
 * hesaplanır (toplam hizmet tutarından DEĞİL). Negatif tutar oluşmaz.
 * İade Webey tarafından otomatik banka transferi yapılmaz; işletme manuel yapar.
 *
 * Tüm tarih/saat kararları Europe/Istanbul. Politika randevu oluşturulurken
 * snapshot'lanır; sonradan politika değişse bile randevunun kuralı sabit kalır.
 */

if (!function_exists('wb_cancellation_policy')) {

    /** İşletmenin güncel iptal politikası (deposit_policies). Eksikse güvenli default. */
    function wb_cancellation_policy(PDO $pdo, int $businessId): array
    {
        $default = [
            'free_cancel_hours'    => 24,
            'late_cancel_enabled'  => false,
            'late_cancel_rate_pct' => 50,
            'no_show_policy'       => 'forfeit', // forfeit | half_refund | refund
            'cancel_policy'        => 'esnek',
            'customer_message'     => null,
        ];
        try {
            if (!mobile_table_has_column($pdo, 'deposit_policies', 'free_cancel_hours')) {
                return $default;
            }
            $stmt = $pdo->prepare(
                'SELECT free_cancel_hours, late_cancel_enabled, late_cancel_rate_pct,
                        no_show_policy, cancel_policy, customer_message
                   FROM deposit_policies WHERE business_id = ? LIMIT 1'
            );
            $stmt->execute([$businessId]);
            $row = $stmt->fetch();
            if (!$row) {
                return $default;
            }
            return [
                'free_cancel_hours'    => $row['free_cancel_hours'] !== null ? (int)$row['free_cancel_hours'] : 24,
                'late_cancel_enabled'  => (bool)($row['late_cancel_enabled'] ?? false),
                'late_cancel_rate_pct' => $row['late_cancel_rate_pct'] !== null ? (int)$row['late_cancel_rate_pct'] : 50,
                'no_show_policy'       => (string)($row['no_show_policy'] ?? 'forfeit'),
                'cancel_policy'        => (string)($row['cancel_policy'] ?? 'esnek'),
                'customer_message'     => ($row['customer_message'] ?? '') !== '' ? (string)$row['customer_message'] : null,
            ];
        } catch (Throwable $e) {
            error_log('[wb_cancellation_policy] ' . $e->getMessage());
            return $default;
        }
    }

    /** no_show_policy -> iade yüzdesi. */
    function wb_cancellation_no_show_refund_pct(string $policy): int
    {
        return match ($policy) {
            'refund' => 100,
            'half_refund' => 50,
            default => 0, // forfeit
        };
    }

    /**
     * Randevu oluşturulurken yazılacak snapshot değerleri.
     * @return array{free_hours:int, late_fee_pct:int, no_show_refund_pct:int}
     */
    function wb_cancellation_snapshot_values(array $policy): array
    {
        return [
            'free_hours'         => (int)$policy['free_cancel_hours'],
            'late_fee_pct'       => $policy['late_cancel_enabled'] ? (int)$policy['late_cancel_rate_pct'] : 0,
            'no_show_refund_pct' => wb_cancellation_no_show_refund_pct((string)$policy['no_show_policy']),
        ];
    }

    /**
     * Finansal hesap. Snapshot yoksa çağıran taraf güncel politikadan türetip verir.
     *
     * @param array{free_hours:int, late_fee_pct:int, no_show_refund_pct:int} $snap
     * @param float $paidDeposit  Gerçekten ödenmiş kapora (0 ise sonuç 0).
     * @param string $reason 'customer_cancel' | 'no_show'
     * @return array<string,mixed>
     */
    function wb_cancellation_quote(
        array $snap,
        float $paidDeposit,
        DateTimeImmutable $startAt,
        DateTimeImmutable $now,
        string $reason
    ): array {
        $paid = max(0.0, round($paidDeposit, 2));

        // Kapora yoksa/ödenmemişse finansal sonuç sıfır.
        if ($paid <= 0) {
            return [
                'reason'           => $reason,
                'paid_deposit'     => 0.0,
                'is_free'          => $reason === 'customer_cancel',
                'is_late'          => false,
                'refund_amount'    => 0.0,
                'retained_amount'  => 0.0,
                'rule_result'      => $reason === 'no_show' ? 'no_show_no_deposit' : 'no_deposit',
                'headline'         => 'Bu randevuda kapora bulunmuyor.',
                'message'          => 'İade veya kesinti söz konusu değildir.',
                'manual_refund'    => false,
            ];
        }

        if ($reason === 'no_show') {
            $refundPct = max(0, min(100, (int)$snap['no_show_refund_pct']));
            $refund = round($paid * $refundPct / 100, 2);
            $retained = round($paid - $refund, 2);
            $rule = 'no_show_' . match ($refundPct) {
                100 => 'full_refund',
                50 => 'half_refund',
                default => 'forfeit',
            };
            $headline = match ($refundPct) {
                100 => 'Randevuya katılmadığınız için kapora tam iade edilir.',
                50 => 'Randevuya katılmadığınız için kapora politikasına göre yarısı iade edilir.',
                default => 'Randevuya katılmadığınız için kapora politikasına göre iade edilmez.',
            };
            return [
                'reason'          => $reason,
                'paid_deposit'    => $paid,
                'is_free'         => false,
                'is_late'         => true,
                'refund_amount'   => $refund,
                'retained_amount' => $retained,
                'rule_result'     => $rule,
                'headline'        => $headline,
                'message'         => $refund > 0
                    ? 'İade, işletme tarafından manuel olarak yapılacaktır.'
                    : 'Kapora işletmede kalır.',
                'manual_refund'   => $refund > 0,
            ];
        }

        // customer_cancel: ücretsiz pencere kontrolü
        $freeUntil = $startAt->modify('-' . (int)$snap['free_hours'] . ' hours');
        $isFree = $now <= $freeUntil;

        if ($isFree) {
            return [
                'reason'          => $reason,
                'paid_deposit'    => $paid,
                'is_free'         => true,
                'is_late'         => false,
                'refund_amount'   => $paid,
                'retained_amount' => 0.0,
                'rule_result'     => 'free_cancel',
                'headline'        => 'Ücretsiz iptal süresi içindesiniz; kapora tam iade edilir.',
                'message'         => 'İade, işletme tarafından manuel olarak yapılacaktır.',
                'manual_refund'   => true,
            ];
        }

        // Geç iptal
        $feePct = max(0, min(100, (int)$snap['late_fee_pct']));
        if ($feePct <= 0) {
            // Geç iptal ücreti kapalı → kesinti yok, tam iade.
            return [
                'reason'          => $reason,
                'paid_deposit'    => $paid,
                'is_free'         => false,
                'is_late'         => true,
                'refund_amount'   => $paid,
                'retained_amount' => 0.0,
                'rule_result'     => 'late_cancel_no_fee',
                'headline'        => 'Geç iptal; ancak işletme geç iptal ücreti uygulamıyor. Kapora iade edilir.',
                'message'         => 'İade, işletme tarafından manuel olarak yapılacaktır.',
                'manual_refund'   => true,
            ];
        }
        $retained = round($paid * $feePct / 100, 2);
        $refund = round($paid - $retained, 2);
        return [
            'reason'          => $reason,
            'paid_deposit'    => $paid,
            'is_free'         => false,
            'is_late'         => true,
            'refund_amount'   => max(0.0, $refund),
            'retained_amount' => max(0.0, $retained),
            'rule_result'     => 'late_cancel',
            'headline'        => 'Ücretsiz iptal süresi geçti; geç iptal kesintisi uygulanır.',
            'message'         => $refund > 0
                ? 'İade, işletme tarafından manuel olarak yapılacaktır.'
                : 'Kapora işletmede kalır.',
            'manual_refund'   => $refund > 0,
        ];
    }

    /**
     * Bir randevunun snapshot'ını (yoksa güncel politikadan fallback) + ödenmiş
     * kaporasını çözüp quote döndürür. appointment row + businessId verilir.
     */
    function wb_cancellation_quote_for_appointment(
        PDO $pdo,
        array $appt,
        int $businessId,
        string $reason,
        ?DateTimeImmutable $now = null
    ): array {
        $tz = new DateTimeZone('Europe/Istanbul');
        $now = $now ?? new DateTimeImmutable('now', $tz);

        // Snapshot (booking anında yazılmış); yoksa güncel politikadan türet.
        $hasSnap = array_key_exists('free_cancel_hours_snapshot', $appt)
            && $appt['free_cancel_hours_snapshot'] !== null;
        if ($hasSnap) {
            $snap = [
                'free_hours'         => (int)$appt['free_cancel_hours_snapshot'],
                'late_fee_pct'       => (int)($appt['late_cancel_fee_pct_snapshot'] ?? 0),
                'no_show_refund_pct' => (int)($appt['no_show_refund_pct_snapshot'] ?? 0),
            ];
        } else {
            $snap = wb_cancellation_snapshot_values(wb_cancellation_policy($pdo, $businessId));
        }

        // Ödenmiş kapora: snapshot varsa onu, yoksa deposit_status='paid' ise deposit_amount.
        if (array_key_exists('paid_deposit_amount_snapshot', $appt)
            && $appt['paid_deposit_amount_snapshot'] !== null) {
            $paid = (float)$appt['paid_deposit_amount_snapshot'];
        } else {
            $depStatus = (string)($appt['deposit_status'] ?? '');
            $depRequired = (bool)($appt['deposit_required'] ?? false);
            $paid = ($depRequired && $depStatus === 'paid' && $appt['deposit_amount'] !== null)
                ? (float)$appt['deposit_amount']
                : 0.0;
        }

        $startAt = new DateTimeImmutable((string)$appt['start_at'], $tz);
        return wb_cancellation_quote($snap, $paid, $startAt, $now, $reason);
    }

    /** Müşteriye gösterilecek kısa politika özeti satırları (salon detay / booking). */
    function wb_cancellation_summary_lines(array $policy): array
    {
        $lines = [];
        $hours = (int)$policy['free_cancel_hours'];
        $lines[] = 'Randevudan ' . $hours . ' saat öncesine kadar ücretsiz iptal.';
        if ($policy['late_cancel_enabled'] && (int)$policy['late_cancel_rate_pct'] > 0) {
            $lines[] = 'Geç iptalde kaporanın %' . (int)$policy['late_cancel_rate_pct'] . '\'i kesilir.';
        } else {
            $lines[] = 'Geç iptalde kapora kesintisi uygulanmaz.';
        }
        $nsPct = wb_cancellation_no_show_refund_pct((string)$policy['no_show_policy']);
        $lines[] = match ($nsPct) {
            100 => 'Gelmeme durumunda kapora tam iade edilir.',
            50 => 'Gelmeme durumunda kaporanın yarısı iade edilir.',
            default => 'Gelmeme durumunda kapora iade edilmez.',
        };
        return $lines;
    }
}
