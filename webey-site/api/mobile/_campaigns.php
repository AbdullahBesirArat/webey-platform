<?php
declare(strict_types=1);
/**
 * api/mobile/_campaigns.php
 * Kampanya MVP ortak motoru — uygunluk, doğrulama ve fiyat hesabı.
 *
 * Kapsam (condition_type): general | weekday | hourly
 * discount_kind: percent | fixed
 * scope_type   : all_services | selected_services
 * status       : active | paused | archived
 *
 * KRİTİK: İstemci fiyatına/indirimine ASLA güvenilmez. Final fiyat ve indirim
 * tutarı yalnızca bu motorla, sunucu zamanı ve DB verisi üzerinden hesaplanır.
 */

if (!function_exists('wb_campaign_tables_ready')) {

    /** business_campaigns tablosu var mı (migration çalıştı mı). Request içi cache. */
    function wb_campaign_tables_ready(PDO $pdo): bool
    {
        static $ready = null;
        if ($ready !== null) {
            return $ready;
        }
        try {
            $stmt = $pdo->query(
                "SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES
                 WHERE TABLE_SCHEMA = DATABASE()
                   AND TABLE_NAME IN ('business_campaigns','campaign_services')"
            );
            $ready = ((int)$stmt->fetchColumn()) === 2;
        } catch (Throwable $e) {
            error_log('[wb_campaign_tables_ready] ' . $e->getMessage());
            $ready = false;
        }
        return $ready;
    }

    /** appointments kampanya snapshot kolonları var mı. */
    function wb_campaign_appt_cols_ready(PDO $pdo): bool
    {
        static $ready = null;
        if ($ready !== null) {
            return $ready;
        }
        try {
            $stmt = $pdo->query(
                "SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
                 WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'appointments'
                   AND COLUMN_NAME IN ('campaign_id','campaign_discount_amount','original_amount','final_amount')"
            );
            $ready = ((int)$stmt->fetchColumn()) === 4;
        } catch (Throwable $e) {
            error_log('[wb_campaign_appt_cols_ready] ' . $e->getMessage());
            $ready = false;
        }
        return $ready;
    }

    /** TR para formatı: tam sayıysa ondalıksız, değilse 2 hane. */
    function wb_campaign_money(float $v): string
    {
        if (abs($v - round($v)) < 0.005) {
            return (string)(int)round($v);
        }
        return number_format($v, 2, ',', '.');
    }

    /** Saat HH:MM (saniyeyi at). */
    function wb_campaign_hm(?string $t): ?string
    {
        if ($t === null || $t === '') {
            return null;
        }
        return substr($t, 0, 5);
    }

    /** days_of_week CSV -> [int]. ISO: 1=Pzt..7=Paz. */
    function wb_campaign_days(?string $csv): array
    {
        if ($csv === null || trim($csv) === '') {
            return [];
        }
        $out = [];
        foreach (explode(',', $csv) as $p) {
            $n = (int)trim($p);
            if ($n >= 1 && $n <= 7) {
                $out[$n] = $n;
            }
        }
        return array_values($out);
    }

    /** Kart rozeti: kısa, tek bakışta indirim. */
    function wb_campaign_badge(array $c): string
    {
        $kind = (string)($c['discount_kind'] ?? 'percent');
        $val  = (float)($c['discount_value'] ?? 0);
        $cond = (string)($c['condition_type'] ?? 'general');
        $st = wb_campaign_hm($c['start_time'] ?? null);
        $et = wb_campaign_hm($c['end_time'] ?? null);

        $disc = $kind === 'fixed'
            ? wb_campaign_money($val) . ' TL indirim'
            : '%' . wb_campaign_money($val) . ' indirim';

        if ($cond === 'hourly' && $st && $et) {
            return $st . '–' . $et . ' ' . ($kind === 'fixed' ? wb_campaign_money($val) . ' TL' : '%' . wb_campaign_money($val));
        }
        if ($cond === 'weekday') {
            return 'Hafta içi ' . ($kind === 'fixed' ? wb_campaign_money($val) . ' TL' : '%' . wb_campaign_money($val));
        }
        return $disc;
    }

    /** Tek satır özet (kart altı / detay bandı). */
    function wb_campaign_summary(array $c): string
    {
        $kind = (string)($c['discount_kind'] ?? 'percent');
        $val  = (float)($c['discount_value'] ?? 0);
        $cond = (string)($c['condition_type'] ?? 'general');
        $scopeAll = (string)($c['scope_type'] ?? 'all_services') === 'all_services';
        $st = wb_campaign_hm($c['start_time'] ?? null);
        $et = wb_campaign_hm($c['end_time'] ?? null);

        $disc = $kind === 'fixed'
            ? wb_campaign_money($val) . ' TL indirim'
            : '%' . wb_campaign_money($val) . ' indirim';
        $where = $scopeAll ? 'tüm hizmetlerde' : 'seçili hizmetlerde';

        if ($cond === 'weekday') {
            $base = 'Hafta içi ' . $where . ' ' . $disc;
        } elseif ($cond === 'hourly' && $st && $et) {
            $base = $st . '–' . $et . ' arasında ' . $where . ' ' . $disc;
        } else {
            $base = $where . ' ' . $disc;
            if ($st && $et) {
                $base .= ' (' . $st . '–' . $et . ')';
            }
        }
        return mb_convert_case(mb_substr($base, 0, 1), MB_CASE_UPPER, 'UTF-8') . mb_substr($base, 1);
    }

    /**
     * Bir kampanyanın verilen ana/slot zamanında "şu an geçerli" olup olmadığı.
     * Tarih + (varsa) gün + (varsa) saat koşulları PHP tarafında doğrulanır.
     */
    function wb_campaign_active_at(array $c, DateTimeImmutable $when): bool
    {
        if ((string)($c['status'] ?? '') !== 'active') {
            return false;
        }
        $date = $when->format('Y-m-d');
        if (!empty($c['start_date']) && $date < (string)$c['start_date']) {
            return false;
        }
        if (!empty($c['end_date']) && $date > (string)$c['end_date']) {
            return false;
        }
        $days = wb_campaign_days($c['days_of_week'] ?? null);
        if ($days !== [] && !in_array((int)$when->format('N'), $days, true)) {
            return false;
        }
        $st = wb_campaign_hm($c['start_time'] ?? null);
        $et = wb_campaign_hm($c['end_time'] ?? null);
        if ($st !== null && $et !== null) {
            $now = $when->format('H:i');
            if ($now < $st || $now > $et) {
                return false;
            }
        }
        return true;
    }

    /**
     * Kampanyanın uygun OLMAMA nedeni (slot için). Tarih/gün/saat uymazsa
     * müşteriye gösterilecek açıklama; uygunsa null.
     */
    function wb_campaign_reason_at(array $c, DateTimeImmutable $when): ?string
    {
        $date = $when->format('Y-m-d');
        if (!empty($c['end_date']) && $date > (string)$c['end_date']) {
            return 'Kampanyanın süresi sona ermiş.';
        }
        if (!empty($c['start_date']) && $date < (string)$c['start_date']) {
            return 'Kampanya ' . date('d.m.Y', strtotime((string)$c['start_date'])) . ' tarihinde başlıyor.';
        }
        $days = wb_campaign_days($c['days_of_week'] ?? null);
        if ($days !== [] && !in_array((int)$when->format('N'), $days, true)) {
            $names = ['', 'Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
            $lbl = implode(', ', array_map(static fn($d) => $names[$d], $days));
            return 'Bu kampanya yalnızca ' . $lbl . ' günleri geçerlidir.';
        }
        $st = wb_campaign_hm($c['start_time'] ?? null);
        $et = wb_campaign_hm($c['end_time'] ?? null);
        if ($st !== null && $et !== null) {
            $now = $when->format('H:i');
            if ($now < $st || $now > $et) {
                return 'Bu kampanya yalnızca ' . $st . '–' . $et . ' saatleri arasında geçerlidir.';
            }
        }
        return null;
    }

    /**
     * İndirim hesabı. Final fiyat asla 0/negatif olamaz (min 1 TL kuralı;
     * fiyat 1 TL altındaysa fiyatın kendisi taban). Sabit indirim fiyatı aşamaz.
     *
     * @return array{amount:float, final:float, kind:string, value:float}
     */
    function wb_campaign_compute_discount(array $c, float $price): array
    {
        $kind = (string)($c['discount_kind'] ?? 'percent');
        $value = (float)($c['discount_value'] ?? 0);
        $price = max(0.0, round($price, 2));

        if ($price <= 0) {
            return ['amount' => 0.0, 'final' => 0.0, 'kind' => $kind, 'value' => $value];
        }

        $minFinal = $price >= 1.0 ? 1.0 : $price;

        if ($kind === 'fixed') {
            $amount = max(0.0, $value);
        } else {
            $pct = max(0.0, min(100.0, $value));
            $amount = $price * $pct / 100.0;
        }
        $amount = round($amount, 2);

        // Final taban koruması
        if ($price - $amount < $minFinal) {
            $amount = round($price - $minFinal, 2);
        }
        if ($amount < 0) {
            $amount = 0.0;
        }
        $final = round($price - $amount, 2);

        return ['amount' => $amount, 'final' => $final, 'kind' => $kind, 'value' => $value];
    }

    /**
     * Verilen işletme + (opsiyonel) hizmet için DB'den AKTİF (status) ve tarih
     * aralığındaki kampanyaları çeker. Gün/saat filtreleri çağıran tarafça
     * (PHP) uygulanır. Hizmet verilirse scope (all_services / bağ tablosu) süzülür.
     *
     * @return array<int, array<string,mixed>>
     */
    function wb_campaign_fetch_candidates(PDO $pdo, int $businessId, ?int $serviceId = null): array
    {
        if (!wb_campaign_tables_ready($pdo) || $businessId < 1) {
            return [];
        }
        try {
            $sql = "SELECT c.* FROM business_campaigns c
                    WHERE c.business_id = ?
                      AND c.status = 'active'
                      AND (c.start_date IS NULL OR c.start_date <= CURDATE())
                      AND (c.end_date IS NULL OR c.end_date >= CURDATE())";
            $params = [$businessId];
            if ($serviceId !== null && $serviceId > 0) {
                $sql .= " AND (c.scope_type = 'all_services'
                              OR EXISTS (SELECT 1 FROM campaign_services cs
                                         WHERE cs.campaign_id = c.id AND cs.service_id = ?))";
                $params[] = $serviceId;
            }
            $sql .= ' ORDER BY c.created_at ASC, c.id ASC';
            $stmt = $pdo->prepare($sql);
            $stmt->execute($params);
            return $stmt->fetchAll();
        } catch (Throwable $e) {
            error_log('[wb_campaign_fetch_candidates] ' . $e->getMessage());
            return [];
        }
    }

    /**
     * Salon kartı/detayı için işletmenin "şu an geçerli" en iyi vitrin kampanyası.
     * Belirli fiyat hesaplanmaz (hizmete bağlı olabilir) — yalnız rozet/özet.
     *
     * @return array<string,mixed>|null
     */
    function wb_campaign_display_for_business(PDO $pdo, int $businessId, ?DateTimeImmutable $now = null): ?array
    {
        $now = $now ?? new DateTimeImmutable('now', new DateTimeZone('Europe/Istanbul'));
        $best = null;
        foreach (wb_campaign_fetch_candidates($pdo, $businessId) as $c) {
            if (!wb_campaign_active_at($c, $now)) {
                continue;
            }
            // Vitrin için en yüksek indirim "değeri" değil, yüzdelikleri öne al;
            // basitçe en yeni-aktif yerine en yüksek discount_value/percent tercih.
            if ($best === null) {
                $best = $c;
                continue;
            }
            if ((float)$c['discount_value'] > (float)$best['discount_value']) {
                $best = $c;
            }
        }
        if ($best === null) {
            return null;
        }
        return wb_campaign_public_payload($pdo, $best);
    }

    /**
     * Birden çok işletme için "şu an geçerli" en iyi vitrin kampanyasını tek
     * sorguda toplar (N+1 önler). Feed (salons.php) için.
     *
     * @param array<int> $businessIds
     * @return array<int, array<string,mixed>>  businessId => public payload
     */
    function wb_campaign_display_for_businesses(PDO $pdo, array $businessIds, ?DateTimeImmutable $now = null): array
    {
        if (!wb_campaign_tables_ready($pdo)) {
            return [];
        }
        $ids = array_values(array_unique(array_filter(array_map('intval', $businessIds), static fn($v) => $v > 0)));
        if ($ids === []) {
            return [];
        }
        $now = $now ?? new DateTimeImmutable('now', new DateTimeZone('Europe/Istanbul'));
        try {
            $ph = implode(',', array_fill(0, count($ids), '?'));
            $stmt = $pdo->prepare(
                "SELECT * FROM business_campaigns
                 WHERE business_id IN ($ph)
                   AND status = 'active'
                   AND (start_date IS NULL OR start_date <= CURDATE())
                   AND (end_date IS NULL OR end_date >= CURDATE())
                 ORDER BY business_id ASC, discount_value DESC, created_at ASC"
            );
            $stmt->execute($ids);
            $bestByBiz = [];
            foreach ($stmt->fetchAll() as $c) {
                if (!wb_campaign_active_at($c, $now)) {
                    continue;
                }
                $bid = (int)$c['business_id'];
                // discount_value DESC sıralı geldiği için ilk uygun = en yüksek
                if (!isset($bestByBiz[$bid])) {
                    $bestByBiz[$bid] = wb_campaign_public_payload($pdo, $c);
                }
            }
            return $bestByBiz;
        } catch (Throwable $e) {
            error_log('[wb_campaign_display_for_businesses] ' . $e->getMessage());
            return [];
        }
    }

    /** Public (customer) JSON gösterimi. */
    function wb_campaign_public_payload(PDO $pdo, array $c): array
    {
        $serviceIds = [];
        $scopeAll = (string)($c['scope_type'] ?? 'all_services') === 'all_services';
        if (!$scopeAll && wb_campaign_tables_ready($pdo)) {
            try {
                $stmt = $pdo->prepare('SELECT service_id FROM campaign_services WHERE campaign_id = ?');
                $stmt->execute([(int)$c['id']]);
                $serviceIds = array_map('intval', $stmt->fetchAll(PDO::FETCH_COLUMN));
            } catch (Throwable $e) {
                error_log('[wb_campaign_public_payload] ' . $e->getMessage());
            }
        }
        return [
            'id'                    => (string)$c['id'],
            'title'                 => (string)$c['title'],
            'description'           => $c['description'] !== null ? (string)$c['description'] : null,
            'badge'                 => wb_campaign_badge($c),
            'summary'               => wb_campaign_summary($c),
            'condition_type'        => (string)$c['condition_type'],
            'discount_kind'         => (string)$c['discount_kind'],
            'discount_value'        => (float)$c['discount_value'],
            'start_date'            => $c['start_date'] !== null ? (string)$c['start_date'] : null,
            'end_date'              => $c['end_date'] !== null ? (string)$c['end_date'] : null,
            'start_time'            => wb_campaign_hm($c['start_time'] ?? null),
            'end_time'              => wb_campaign_hm($c['end_time'] ?? null),
            'days_of_week'          => wb_campaign_days($c['days_of_week'] ?? null),
            'applies_to_all_services' => $scopeAll,
            'service_ids'           => array_map('strval', $serviceIds),
            'scope_summary'         => wb_campaign_scope_summary($pdo, $c),
            'validity_summary'      => wb_campaign_validity_summary($c),
            'eligibility_now'       => wb_campaign_active_at($c, wb_campaign_now()),
        ];
    }

    /**
     * BOOKING MOTORU — belirli hizmet + slot için uygulanacak EN AVANTAJLI kampanya.
     * Birden fazla uygunsa en yüksek indirim tutarı; eşitlikte en eski (created_at/id).
     *
     * @return array{
     *   campaign: array<string,mixed>|null,   // uygulanan kampanya quote'u
     *   reason: string|null                   // uygulanabilir aday var ama slot uymuyorsa neden
     * }
     */
    function wb_campaign_quote_for_slot(PDO $pdo, int $businessId, int $serviceId, float $price, DateTimeImmutable $slot): array
    {
        $candidates = wb_campaign_fetch_candidates($pdo, $businessId, $serviceId);
        if ($candidates === []) {
            return ['campaign' => null, 'reason' => null];
        }

        $best = null;
        $bestAmount = -1.0;
        $reason = null;

        foreach ($candidates as $c) {
            if (!wb_campaign_active_at($c, $slot)) {
                if ($reason === null) {
                    $reason = wb_campaign_reason_at($c, $slot);
                }
                continue;
            }
            $calc = wb_campaign_compute_discount($c, $price);
            if ($calc['amount'] <= 0) {
                continue;
            }
            if ($calc['amount'] > $bestAmount) {
                $bestAmount = $calc['amount'];
                $best = ['campaign' => $c, 'calc' => $calc];
            }
            // eşitlikte: created_at ASC sıralı geldiği için ilk gelen korunur (> ile değişmez)
        }

        if ($best === null) {
            return ['campaign' => null, 'reason' => $reason];
        }

        $c = $best['campaign'];
        $calc = $best['calc'];
        return [
            'campaign' => [
                'id'              => (int)$c['id'],
                'title'           => (string)$c['title'],
                'badge'           => wb_campaign_badge($c),
                'summary'         => wb_campaign_summary($c),
                'discount_kind'   => $calc['kind'],
                'discount_value'  => $calc['value'],
                'discount_amount' => $calc['amount'],
                'original_price'  => round($price, 2),
                'final_price'     => $calc['final'],
            ],
            'reason' => null,
        ];
    }

    /** İstanbul saatiyle "şimdi". Tüm tarih/gün/saat kararları bununla yapılır. */
    function wb_campaign_now(): DateTimeImmutable
    {
        return new DateTimeImmutable('now', new DateTimeZone('Europe/Istanbul'));
    }

    /** Kapsam özeti: "Tüm hizmetlerde" / "2 seçili hizmette". */
    function wb_campaign_scope_summary(PDO $pdo, array $c): string
    {
        if ((string)($c['scope_type'] ?? 'all_services') === 'all_services') {
            return 'Tüm hizmetlerde';
        }
        $count = 0;
        if (wb_campaign_tables_ready($pdo)) {
            try {
                $stmt = $pdo->prepare('SELECT COUNT(*) FROM campaign_services WHERE campaign_id = ?');
                $stmt->execute([(int)$c['id']]);
                $count = (int)$stmt->fetchColumn();
            } catch (Throwable $e) {
                error_log('[wb_campaign_scope_summary] ' . $e->getMessage());
            }
        }
        return $count > 0 ? ($count . ' seçili hizmette') : 'Seçili hizmetlerde';
    }

    /** Geçerlilik özeti: gün + saat koşulu, kısa metin. */
    function wb_campaign_validity_summary(array $c): string
    {
        $days = wb_campaign_days($c['days_of_week'] ?? null);
        $st = wb_campaign_hm($c['start_time'] ?? null);
        $et = wb_campaign_hm($c['end_time'] ?? null);
        $parts = [];
        if ($days !== []) {
            $parts[] = wb_campaign_days_label($days);
        }
        if ($st !== null && $et !== null) {
            $parts[] = $st . '–' . $et;
        }
        if ($parts === []) {
            return 'Her gün geçerli';
        }
        return implode(' · ', $parts);
    }

    /** Gün listesini okunur etikete çevirir (1..5 ardışıksa "Pzt–Cum"). */
    function wb_campaign_days_label(array $days): string
    {
        $names = ['', 'Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
        sort($days);
        if ($days === [1, 2, 3, 4, 5]) {
            return 'Pzt–Cum';
        }
        if ($days === [6, 7]) {
            return 'Hafta sonu';
        }
        if ($days === [1, 2, 3, 4, 5, 6, 7]) {
            return 'Her gün';
        }
        // Ardışık aralık ise tire ile, değilse virgülle.
        $consecutive = true;
        for ($i = 1; $i < count($days); $i++) {
            if ($days[$i] !== $days[$i - 1] + 1) {
                $consecutive = false;
                break;
            }
        }
        if ($consecutive && count($days) >= 3) {
            return $names[$days[0]] . '–' . $names[$days[count($days) - 1]];
        }
        return implode(', ', array_map(static fn($d) => $names[$d], $days));
    }

    /**
     * Kampanyanın bir sonraki "uygun olacağı" an (Europe/Istanbul). Yaklaşan veya
     * koşul bekleyen durumda doludur; şu an geçerli / sona ermiş / duraklatılmışta null.
     */
    function wb_campaign_next_eligible_at(array $c, DateTimeImmutable $now): ?DateTimeImmutable
    {
        if ((string)($c['status'] ?? '') !== 'active') {
            return null;
        }
        $tz = new DateTimeZone('Europe/Istanbul');
        $days = wb_campaign_days($c['days_of_week'] ?? null);
        $st = wb_campaign_hm($c['start_time'] ?? null);
        for ($i = 0; $i <= 31; $i++) {
            $day = $now->modify('+' . $i . ' day');
            $dateStr = $day->format('Y-m-d');
            if (!empty($c['start_date']) && $dateStr < (string)$c['start_date']) {
                continue;
            }
            if (!empty($c['end_date']) && $dateStr > (string)$c['end_date']) {
                return null;
            }
            if ($days !== [] && !in_array((int)$day->format('N'), $days, true)) {
                continue;
            }
            $candTime = $st ?? '00:00';
            $cand = DateTimeImmutable::createFromFormat('Y-m-d H:i', $dateStr . ' ' . $candTime, $tz);
            if ($cand !== false && $cand >= $now) {
                return $cand;
            }
        }
        return null;
    }

    /**
     * PROFESYONEL DURUM SİSTEMİ — tek otorite. Business kartı + müşteri görünürlüğü
     * aynı kaynaktan beslenir. Tüm kararlar Europe/Istanbul saatiyle.
     *
     * @return array<string,mixed>
     */
    function wb_campaign_status(array $c, ?DateTimeImmutable $now = null): array
    {
        $now = $now ?? wb_campaign_now();
        $status = (string)($c['status'] ?? 'active');
        $date = $now->format('Y-m-d');

        // Yaşam döngüsü: tarih aralığına göre (switch'ten bağımsız).
        if (!empty($c['end_date']) && $date > (string)$c['end_date']) {
            $lifecycle = 'expired';
        } elseif (!empty($c['start_date']) && $date < (string)$c['start_date']) {
            $lifecycle = 'upcoming';
        } else {
            $lifecycle = 'active';
        }

        $publication = $status === 'active' ? 'published'
            : ($status === 'paused' ? 'paused' : 'archived');

        $eligibleNow = wb_campaign_active_at($c, $now);
        $next = wb_campaign_next_eligible_at($c, $now);

        // Müşteri görünürlük durumu + mesajı.
        if ($status === 'archived') {
            $vis = 'ended';
            $msg = 'Bu kampanya sonlandırıldığı için müşterilere gösterilmiyor.';
        } elseif ($status === 'paused') {
            $vis = 'paused';
            $msg = 'Duraklatıldığı için müşterilere gösterilmiyor.';
        } elseif ($lifecycle === 'expired') {
            $vis = 'ended';
            $msg = 'Kampanyanın süresi doldu; müşterilere gösterilmiyor.';
        } elseif ($lifecycle === 'upcoming') {
            $vis = 'upcoming';
            $msg = $next !== null
                ? (wb_campaign_when_label($next, $now) . ' başlayacak.')
                : 'Yakında başlayacak.';
        } elseif ($eligibleNow) {
            $vis = 'visible_now';
            $msg = 'Müşterilere şu an gösteriliyor.';
        } else {
            // Tarih aralığında + switch açık ama gün/saat şu an uymuyor.
            $vis = 'waiting_for_condition';
            $msg = $next !== null
                ? (wb_campaign_when_label($next, $now) . ' müşterilere gösterilecek.')
                : 'Uygun gün/saatte müşterilere gösterilecek.';
        }

        // next_eligible_at yalnız "henüz görünmüyor ama görünecek" durumlarda anlamlı.
        $nextOut = in_array($vis, ['upcoming', 'waiting_for_condition'], true) && $next !== null
            ? $next->format('c')
            : null;

        return [
            'publication_status'         => $publication,      // published|paused|archived
            'lifecycle_status'           => $lifecycle,        // active|upcoming|expired
            'is_currently_eligible'      => $eligibleNow,
            'customer_visibility_status' => $vis,              // visible_now|waiting_for_condition|upcoming|paused|ended
            'customer_visibility_message'=> $msg,
            'next_eligible_at'           => $nextOut,
        ];
    }

    /** "Bugün 12:00'de" / "Pazartesi" / "21 Haziran" gibi okunur an etiketi. */
    function wb_campaign_when_label(DateTimeImmutable $when, DateTimeImmutable $now): string
    {
        $dayDiff = (int)$now->setTime(0, 0)->diff($when->setTime(0, 0))->format('%r%a');
        $hasTime = $when->format('H:i') !== '00:00';
        $timePart = $hasTime ? (' ' . $when->format('H:i') . '\'de') : '';
        if ($dayDiff === 0) {
            return $hasTime ? ('Bugün' . $timePart) : 'Bugün';
        }
        if ($dayDiff === 1) {
            return $hasTime ? ('Yarın' . $timePart) : 'Yarın';
        }
        if ($dayDiff > 1 && $dayDiff < 7) {
            $dayNames = ['', 'Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'];
            $lbl = $dayNames[(int)$when->format('N')];
            return $hasTime ? ($lbl . $timePart) : ($lbl . ' günü');
        }
        $months = ['', 'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
            'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];
        return (int)$when->format('j') . ' ' . $months[(int)$when->format('n')];
    }

    /**
     * GERÇEK PERFORMANS — yalnız campaign_id snapshot'lı appointment kayıtlarından.
     * Görüntülenme yok; veri yoksa sıfırlar + has_data=false döner.
     *
     * @return array<string,mixed>
     */
    function wb_campaign_performance(PDO $pdo, int $campaignId): array
    {
        $empty = [
            'has_data'             => false,
            'booking_count'        => 0,
            'completed_count'      => 0,
            'total_discount_amount'=> 0.0,
            'net_revenue_amount'   => 0.0,
            'last_booking_at'      => null,
        ];
        if (!wb_campaign_appt_cols_ready($pdo) || $campaignId < 1) {
            return $empty;
        }
        try {
            // Kampanyalı randevu = campaign_id eşleşen. İptal/red/no-show ciroya
            // ve completed sayısına girmez; toplam indirim de iptal edilenleri saymaz.
            $stmt = $pdo->prepare(
                "SELECT
                    COUNT(*) AS booking_count,
                    SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) AS completed_count,
                    COALESCE(SUM(CASE WHEN status NOT IN ('cancelled','rejected','declined','no_show')
                        THEN COALESCE(campaign_discount_amount, 0) ELSE 0 END), 0) AS total_discount,
                    COALESCE(SUM(CASE WHEN status = 'completed'
                        THEN COALESCE(final_amount, 0) ELSE 0 END), 0) AS net_revenue,
                    MAX(start_at) AS last_booking_at
                 FROM appointments
                 WHERE campaign_id = ?"
            );
            $stmt->execute([$campaignId]);
            $row = $stmt->fetch();
            $bookingCount = (int)($row['booking_count'] ?? 0);
            return [
                'has_data'             => $bookingCount > 0,
                'booking_count'        => $bookingCount,
                'completed_count'      => (int)($row['completed_count'] ?? 0),
                'total_discount_amount'=> round((float)($row['total_discount'] ?? 0), 2),
                'net_revenue_amount'   => round((float)($row['net_revenue'] ?? 0), 2),
                'last_booking_at'      => $row['last_booking_at'] ?? null,
            ];
        } catch (Throwable $e) {
            error_log('[wb_campaign_performance] ' . $e->getMessage());
            return $empty;
        }
    }

    /**
     * Toplu performans: bir işletmenin tüm kampanyaları için tek sorgu (liste özeti).
     * @return array{campaign_booking_total:int, by_campaign: array<int, array<string,mixed>>}
     */
    function wb_campaign_performance_bulk(PDO $pdo, int $businessId): array
    {
        $out = ['campaign_booking_total' => 0, 'by_campaign' => []];
        if (!wb_campaign_appt_cols_ready($pdo) || $businessId < 1) {
            return $out;
        }
        try {
            $stmt = $pdo->prepare(
                "SELECT campaign_id,
                    COUNT(*) AS booking_count,
                    SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) AS completed_count,
                    COALESCE(SUM(CASE WHEN status NOT IN ('cancelled','rejected','declined','no_show')
                        THEN COALESCE(campaign_discount_amount, 0) ELSE 0 END), 0) AS total_discount,
                    COALESCE(SUM(CASE WHEN status = 'completed'
                        THEN COALESCE(final_amount, 0) ELSE 0 END), 0) AS net_revenue,
                    MAX(start_at) AS last_booking_at
                 FROM appointments
                 WHERE business_id = ? AND campaign_id IS NOT NULL
                 GROUP BY campaign_id"
            );
            $stmt->execute([$businessId]);
            foreach ($stmt->fetchAll() as $row) {
                $cid = (int)$row['campaign_id'];
                $bc = (int)$row['booking_count'];
                $out['campaign_booking_total'] += $bc;
                $out['by_campaign'][$cid] = [
                    'has_data'             => $bc > 0,
                    'booking_count'        => $bc,
                    'completed_count'      => (int)$row['completed_count'],
                    'total_discount_amount'=> round((float)$row['total_discount'], 2),
                    'net_revenue_amount'   => round((float)$row['net_revenue'], 2),
                    'last_booking_at'      => $row['last_booking_at'] ?? null,
                ];
            }
            return $out;
        } catch (Throwable $e) {
            error_log('[wb_campaign_performance_bulk] ' . $e->getMessage());
            return $out;
        }
    }

    /**
     * Kaydetme sırasında çakışan AKTİF kampanya başlıklarını döndürür (uyarı için;
     * engel değil). Çakışma = aynı işletme + tarih aralığı kesişiyor + kapsam
     * (tüm hizmetler ya da ortak seçili hizmet) örtüşüyor.
     *
     * @param array<int> $serviceIds
     * @return array<int, string>  çakışan kampanya başlıkları
     */
    function wb_campaign_conflicts(PDO $pdo, int $businessId, bool $scopeAll, array $serviceIds, ?int $excludeId, ?string $startDate, ?string $endDate): array
    {
        if (!wb_campaign_tables_ready($pdo) || $businessId < 1) {
            return [];
        }
        try {
            $stmt = $pdo->prepare(
                "SELECT * FROM business_campaigns
                 WHERE business_id = ? AND status = 'active'" .
                ($excludeId !== null ? ' AND id <> ?' : '')
            );
            $stmt->execute($excludeId !== null ? [$businessId, $excludeId] : [$businessId]);
            $rows = $stmt->fetchAll();
            $titles = [];
            foreach ($rows as $r) {
                // Tarih aralığı kesişimi (null = sınırsız).
                $aStart = $startDate ?: '0000-01-01';
                $aEnd   = $endDate ?: '9999-12-31';
                $bStart = $r['start_date'] ?: '0000-01-01';
                $bEnd   = $r['end_date'] ?: '9999-12-31';
                if ($aStart > $bEnd || $bStart > $aEnd) {
                    continue; // tarih örtüşmüyor
                }
                // Kapsam örtüşmesi.
                $rScopeAll = (string)$r['scope_type'] === 'all_services';
                $overlap = false;
                if ($scopeAll || $rScopeAll) {
                    $overlap = true;
                } elseif ($serviceIds !== []) {
                    $rsStmt = $pdo->prepare('SELECT service_id FROM campaign_services WHERE campaign_id = ?');
                    $rsStmt->execute([(int)$r['id']]);
                    $rIds = array_map('intval', $rsStmt->fetchAll(PDO::FETCH_COLUMN));
                    $overlap = array_intersect($serviceIds, $rIds) !== [];
                }
                if ($overlap) {
                    $titles[] = (string)$r['title'];
                }
            }
            return $titles;
        } catch (Throwable $e) {
            error_log('[wb_campaign_conflicts] ' . $e->getMessage());
            return [];
        }
    }
}
