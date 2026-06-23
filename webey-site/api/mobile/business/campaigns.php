<?php
declare(strict_types=1);
/**
 * api/mobile/business/campaigns.php
 * GET - Token sahibi işletmenin kampanyaları (archived hariç).
 * Türetilmiş state: active | paused | upcoming | expired (chip filtresi için).
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';
require_once __DIR__ . '/_helpers.php';
require_once __DIR__ . '/../_campaigns.php';

wb_method('GET');

$auth = mobile_auth($pdo, ['business', 'admin']);
$ctx = mobile_business_context($pdo, $auth);
$businessId = (int)$ctx['business_id'];

if (!wb_campaign_tables_ready($pdo)) {
    wb_ok(['items' => [], 'summary' => ['active' => 0, 'paused' => 0, 'upcoming' => 0, 'expired' => 0, 'total' => 0]]);
}

try {
    $tz = new DateTimeZone('Europe/Istanbul');
    $today = (new DateTimeImmutable('now', $tz))->format('Y-m-d');

    $stmt = $pdo->prepare(
        "SELECT * FROM business_campaigns
         WHERE business_id = ? AND status <> 'archived'
         ORDER BY created_at DESC, id DESC"
    );
    $stmt->execute([$businessId]);
    $rows = $stmt->fetchAll();

    // Seçili hizmet adlarını toplu çek
    $ids = array_map(static fn($r) => (int)$r['id'], $rows);
    $serviceMap = [];
    if ($ids !== []) {
        $ph = implode(',', array_fill(0, count($ids), '?'));
        $svcStmt = $pdo->prepare(
            "SELECT cs.campaign_id, cs.service_id, s.name
             FROM campaign_services cs
             LEFT JOIN services s ON s.id = cs.service_id
             WHERE cs.campaign_id IN ($ph)"
        );
        $svcStmt->execute($ids);
        foreach ($svcStmt->fetchAll() as $sr) {
            $cid = (int)$sr['campaign_id'];
            $serviceMap[$cid][] = [
                'id' => (string)$sr['service_id'],
                'name' => (string)($sr['name'] ?? ''),
            ];
        }
    }

    $now = wb_campaign_now();
    // Tüm kampanyalar için gerçek performans (tek sorgu).
    $perf = wb_campaign_performance_bulk($pdo, $businessId);

    // Özet sayaçları (chip + üst özet).
    $summary = [
        'now_eligible' => 0, // Şu an geçerli (yeşil)
        'waiting'      => 0, // Koşul bekliyor (altın)
        'upcoming'     => 0, // Yaklaşan
        'paused'       => 0, // Duraklatılmış
        'expired'      => 0, // Geçmiş
        'published'    => 0, // Yayında sekmesi = now_eligible + waiting
    ];
    $items = [];
    foreach ($rows as $c) {
        $status = (string)$c['status'];
        $st = wb_campaign_status($c, $now);
        $vis = $st['customer_visibility_status'];

        // Chip grubu: published (yayında) | upcoming | paused | expired
        if ($vis === 'visible_now') {
            $summary['now_eligible']++;
            $summary['published']++;
            $filterGroup = 'published';
        } elseif ($vis === 'waiting_for_condition') {
            $summary['waiting']++;
            $summary['published']++;
            $filterGroup = 'published';
        } elseif ($vis === 'upcoming') {
            $summary['upcoming']++;
            $filterGroup = 'upcoming';
        } elseif ($vis === 'paused') {
            $summary['paused']++;
            $filterGroup = 'paused';
        } else { // ended
            $summary['expired']++;
            $filterGroup = 'expired';
        }

        // Geriye dönük uyum için eski "state" alanını da koru.
        $legacyState = match ($vis) {
            'paused' => 'paused',
            'upcoming' => 'upcoming',
            'ended' => 'expired',
            default => 'active',
        };

        $scopeAll = (string)$c['scope_type'] === 'all_services';
        $svcList = $scopeAll ? [] : ($serviceMap[(int)$c['id']] ?? []);
        $items[] = [
            'id'             => (string)$c['id'],
            'title'          => (string)$c['title'],
            'description'    => $c['description'] !== null ? (string)$c['description'] : null,
            'condition_type' => (string)$c['condition_type'],
            'discount_kind'  => (string)$c['discount_kind'],
            'discount_value' => (float)$c['discount_value'],
            'scope_type'     => (string)$c['scope_type'],
            'applies_to_all_services' => $scopeAll,
            'services'       => $svcList,
            'service_ids'    => $scopeAll ? [] : array_map(static fn($s) => $s['id'], $svcList),
            'selected_services_count' => $scopeAll ? 0 : count($svcList),
            'scope_summary'  => wb_campaign_scope_summary($pdo, $c),
            'validity_summary' => wb_campaign_validity_summary($c),
            'start_date'     => $c['start_date'] !== null ? (string)$c['start_date'] : null,
            'end_date'       => $c['end_date'] !== null ? (string)$c['end_date'] : null,
            'start_time'     => wb_campaign_hm($c['start_time'] ?? null),
            'end_time'       => wb_campaign_hm($c['end_time'] ?? null),
            'days_of_week'   => wb_campaign_days($c['days_of_week'] ?? null),
            'status'         => $status,
            'state'          => $legacyState,
            'filter_group'   => $filterGroup,
            'is_active'      => $status === 'active',
            'badge'          => wb_campaign_badge($c),
            'summary'        => wb_campaign_summary($c),
            'created_at'     => (string)$c['created_at'],
            // Profesyonel durum sistemi alanları
            'publication_status'         => $st['publication_status'],
            'lifecycle_status'           => $st['lifecycle_status'],
            'is_currently_eligible'      => $st['is_currently_eligible'],
            'customer_visibility_status' => $st['customer_visibility_status'],
            'customer_visibility_message'=> $st['customer_visibility_message'],
            'next_eligible_at'           => $st['next_eligible_at'],
            // Gerçek performans (snapshot)
            'performance'    => $perf['by_campaign'][(int)$c['id']] ?? [
                'has_data' => false,
                'booking_count' => 0,
                'completed_count' => 0,
                'total_discount_amount' => 0.0,
                'net_revenue_amount' => 0.0,
                'last_booking_at' => null,
            ],
        ];
    }
    $summary['total'] = count($items);
    $summary['campaign_booking_total'] = $perf['campaign_booking_total'];

    wb_ok(['items' => $items, 'summary' => $summary]);
} catch (Throwable $e) {
    error_log('[mobile/business/campaigns.php] ' . $e->getMessage());
    wb_err('Kampanyalar alınamadı', 500, 'internal_error');
}
