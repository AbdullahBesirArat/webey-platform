<?php
declare(strict_types=1);
/**
 * Kampanya motoru birim testleri (PDO gerektirmeyen saf fonksiyonlar).
 * Çalıştır: php webey-site/tests/campaigns_engine_test.php
 */
require_once __DIR__ . '/../api/mobile/_campaigns.php';

$tz = new DateTimeZone('Europe/Istanbul');
$pass = 0; $fail = 0;
function check(string $name, $got, $exp): void {
    global $pass, $fail;
    $ok = $got === $exp;
    if (!$ok && is_float($exp) && is_float($got)) { $ok = abs($got - $exp) < 0.005; }
    if ($ok) { $pass++; echo "  PASS  $name\n"; }
    else { $fail++; echo "  FAIL  $name | got=" . var_export($got, true) . " exp=" . var_export($exp, true) . "\n"; }
}

echo "== compute_discount ==\n";
// %15 of 450 = 67.5 -> final 382.5
$r = wb_campaign_compute_discount(['discount_kind'=>'percent','discount_value'=>15], 450.0);
check('percent 15% amount', $r['amount'], 67.5);
check('percent 15% final', $r['final'], 382.5);
// fixed 100 off 450 -> 350
$r = wb_campaign_compute_discount(['discount_kind'=>'fixed','discount_value'=>100], 450.0);
check('fixed 100 amount', $r['amount'], 100.0);
check('fixed 100 final', $r['final'], 350.0);
// fixed exceeding price clamps so final >= 1
$r = wb_campaign_compute_discount(['discount_kind'=>'fixed','discount_value'=>500], 450.0);
check('fixed >price final min 1', $r['final'], 1.0);
check('fixed >price amount = price-1', $r['amount'], 449.0);
// percent 100 -> final min 1
$r = wb_campaign_compute_discount(['discount_kind'=>'percent','discount_value'=>100], 200.0);
check('percent 100 final min 1', $r['final'], 1.0);
// percent out-of-range clamps to 100 (defensive)
$r = wb_campaign_compute_discount(['discount_kind'=>'percent','discount_value'=>150], 200.0);
check('percent 150 clamped final', $r['final'], 1.0);

echo "== active_at (date/day/time) ==\n";
$base = ['status'=>'active','start_date'=>null,'end_date'=>null,'days_of_week'=>null,'start_time'=>null,'end_time'=>null];
$mon = new DateTimeImmutable('2026-06-22 13:00', $tz); // Pazartesi
$sun = new DateTimeImmutable('2026-06-21 13:00', $tz); // Pazar
check('general always active', wb_campaign_active_at($base, $mon), true);
check('paused not active', wb_campaign_active_at(array_merge($base,['status'=>'paused']), $mon), false);
// weekday Mon-Fri (1..5)
$wd = array_merge($base, ['days_of_week'=>'1,2,3,4,5']);
check('weekday on monday', wb_campaign_active_at($wd, $mon), true);
check('weekday on sunday', wb_campaign_active_at($wd, $sun), false);
// hourly 12:00-17:00
$hr = array_merge($base, ['start_time'=>'12:00:00','end_time'=>'17:00:00']);
check('hourly in range', wb_campaign_active_at($hr, new DateTimeImmutable('2026-06-22 13:00',$tz)), true);
check('hourly out of range', wb_campaign_active_at($hr, new DateTimeImmutable('2026-06-22 18:00',$tz)), false);
// expired
$exp = array_merge($base, ['end_date'=>'2026-06-01']);
check('expired not active', wb_campaign_active_at($exp, $mon), false);

echo "== reason_at ==\n";
check('weekday reason on sunday', is_string(wb_campaign_reason_at($wd, $sun)), true);
check('hourly reason out of range', str_contains((string)wb_campaign_reason_at($hr, new DateTimeImmutable('2026-06-22 18:00',$tz)), '12:00'), true);
check('no reason when valid', wb_campaign_reason_at($wd, $mon), null);

echo "== badge / summary ==\n";
check('badge percent weekday', wb_campaign_badge(['discount_kind'=>'percent','discount_value'=>15,'condition_type'=>'weekday']), 'Hafta içi %15');
check('badge fixed general', wb_campaign_badge(['discount_kind'=>'fixed','discount_value'=>100,'condition_type'=>'general']), '100 TL indirim');
check('badge hourly', wb_campaign_badge(['discount_kind'=>'fixed','discount_value'=>100,'condition_type'=>'hourly','start_time'=>'12:00:00','end_time'=>'17:00:00']), '12:00–17:00 100 TL');

echo "== days parse ==\n";
check('days csv parse', wb_campaign_days('1,2,3,4,5'), [1,2,3,4,5]);
check('days empty', wb_campaign_days(''), []);
check('days invalid filtered', wb_campaign_days('1,9,3,0'), [1,3]);

echo "== kapora + salonda kalan (book.php mantığı) ==\n";
// book.php inline mantığını birebir yansıtan yardımcı.
$quote = static function (array $c, float $price): float {
    $r = wb_campaign_compute_discount($c, $price);
    return $r['final'];
};
$depositRemaining = static function (float $finalPrice, string $mode, float $rateOrAmount): array {
    // mode: 'percent' (rateOrAmount = oran) | 'fixed' (rateOrAmount = sabit tutar)
    $deposit = $mode === 'percent'
        ? round($finalPrice * $rateOrAmount / 100)
        : $rateOrAmount;
    $deposit = round(max(0.0, min($deposit, $finalPrice)), 2); // clamp (Senaryo D)
    $remaining = round(max(0.0, $finalPrice - $deposit), 2);   // negatif olmaz
    return ['deposit' => $deposit, 'remaining' => $remaining];
};

// A. Kampanyasız + %50 kapora: 400 → 200 / 200
$r = $depositRemaining(400.0, 'percent', 50);
check('A deposit', $r['deposit'], 200.0);
check('A remaining', $r['remaining'], 200.0);

// B. %15 kampanya + %50 kapora: final 340 → 170 / 170
$fB = $quote(['discount_kind'=>'percent','discount_value'=>15], 400.0);
$r = $depositRemaining($fB, 'percent', 50);
check('B final', $fB, 340.0);
check('B deposit', $r['deposit'], 170.0);
check('B remaining', $r['remaining'], 170.0);

// C. 100 TL kampanya + sabit 150 kapora: final 300 → 150 / 150
$fC = $quote(['discount_kind'=>'fixed','discount_value'=>100], 400.0);
$r = $depositRemaining($fC, 'fixed', 150.0);
check('C final', $fC, 300.0);
check('C deposit', $r['deposit'], 150.0);
check('C remaining', $r['remaining'], 150.0);

// D. Sabit kapora (200) final tutarı (150) aşıyor → kapora 150, salonda kalan 0
$fD = $quote(['discount_kind'=>'fixed','discount_value'=>100], 250.0);
$r = $depositRemaining($fD, 'fixed', 200.0);
check('D final', $fD, 150.0);
check('D deposit clamped', $r['deposit'], 150.0);
check('D remaining not negative', $r['remaining'], 0.0);

// E. Kampanya koşulu geçersiz (cumartesi 18:00) → indirim yok, normal fiyat
$wd = ['status'=>'active','start_date'=>null,'end_date'=>null,'days_of_week'=>'1,2,3,4,5','start_time'=>'12:00:00','end_time'=>'17:00:00','discount_kind'=>'percent','discount_value'=>15];
$sat = new DateTimeImmutable('2026-06-20 18:00', $tz); // Cumartesi 18:00
check('E campaign not active', wb_campaign_active_at($wd, $sat), false);
$r = $depositRemaining(400.0, 'percent', 50); // indirim yok → 400 üzerinden
check('E deposit on full price', $r['deposit'], 200.0);
check('E remaining on full price', $r['remaining'], 200.0);

echo "== profesyonel durum sistemi (wb_campaign_status) ==\n";
// Sabit "şimdi": 2026-06-20 Cumartesi 13:00 (Istanbul)
$nowSat = new DateTimeImmutable('2026-06-20 13:00', $tz);
$mk = static function (array $over) : array {
    return array_merge([
        'status'=>'active','start_date'=>null,'end_date'=>null,
        'days_of_week'=>null,'start_time'=>null,'end_time'=>null,
        'discount_kind'=>'percent','discount_value'=>15,
    ], $over);
};

// 1. Gelecek başlangıç → Yaklaşan, next_eligible_at dolu
$s = wb_campaign_status($mk(['start_date'=>'2026-06-22','end_date'=>'2026-07-10']), $nowSat);
check('upcoming lifecycle', $s['lifecycle_status'], 'upcoming');
check('upcoming visibility', $s['customer_visibility_status'], 'upcoming');
check('upcoming not eligible', $s['is_currently_eligible'], false);
check('upcoming next set', $s['next_eligible_at'] !== null, true);

// 2. Tarih aralığında ama hafta içi kampanyası cumartesi → Koşul bekliyor
$s = wb_campaign_status($mk(['days_of_week'=>'1,2,3,4,5','start_date'=>'2026-06-01','end_date'=>'2026-07-31']), $nowSat);
check('waiting visibility', $s['customer_visibility_status'], 'waiting_for_condition');
check('waiting not eligible', $s['is_currently_eligible'], false);
check('waiting next = monday', substr((string)$s['next_eligible_at'],0,10), '2026-06-22');

// 3. Her koşul uygun (cumartesi, gün yok, saat yok) → Şu an geçerli
$s = wb_campaign_status($mk(['start_date'=>'2026-06-01','end_date'=>'2026-07-31']), $nowSat);
check('visible_now', $s['customer_visibility_status'], 'visible_now');
check('visible_now eligible', $s['is_currently_eligible'], true);
check('visible_now next null', $s['next_eligible_at'], null);

// 4. Duraklatılmış
$s = wb_campaign_status($mk(['status'=>'paused']), $nowSat);
check('paused visibility', $s['customer_visibility_status'], 'paused');
check('paused publication', $s['publication_status'], 'paused');

// 5. Sona ermiş
$s = wb_campaign_status($mk(['end_date'=>'2026-06-01']), $nowSat);
check('ended visibility', $s['customer_visibility_status'], 'ended');
check('ended lifecycle', $s['lifecycle_status'], 'expired');

// 6. Saat bazlı, saat penceresi henüz başlamamış (now 13:00, pencere 15:00-18:00) → bugün 15:00
$s = wb_campaign_status($mk(['start_time'=>'15:00:00','end_time'=>'18:00:00','start_date'=>'2026-06-01','end_date'=>'2026-07-31']), $nowSat);
check('hourly waiting today', $s['customer_visibility_status'], 'waiting_for_condition');
check('hourly next today 15:00', substr((string)$s['next_eligible_at'],0,16), '2026-06-20T15:00');

echo "== validity / days label ==\n";
check('days label weekday', wb_campaign_days_label([1,2,3,4,5]), 'Pzt–Cum');
check('days label weekend', wb_campaign_days_label([6,7]), 'Hafta sonu');
check('validity weekday+saat', wb_campaign_validity_summary($mk(['days_of_week'=>'1,2,3,4,5','start_time'=>'09:00:00','end_time'=>'18:00:00'])), 'Pzt–Cum · 09:00–18:00');

echo "\nRESULT: $pass passed, $fail failed\n";
exit($fail === 0 ? 0 : 1);
