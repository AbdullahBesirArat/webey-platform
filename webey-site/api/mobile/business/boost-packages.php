<?php
declare(strict_types=1);
/**
 * api/mobile/business/boost-packages.php
 * GET — Boost paketleri + işletmenin mevcut/geçmiş boost durumu.
 *
 * Yanıt:
 *   current_boost : object|null  (aktif abonelik varsa)
 *   packages[]    : satın alınabilir paketler
 *   history[]     : geçmiş talep/abonelik kayıtları
 *
 * Auth: business/admin; yalnızca kendi işletmesi. Her durumda valid JSON.
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';
require_once __DIR__ . '/_helpers.php';

wb_method('GET');

try {
    $auth       = mobile_auth($pdo, ['business', 'admin']);
    $ctx        = mobile_business_context($pdo, $auth);
    $businessId = (int)$ctx['business_id'];

    // Boost uygunluğu (abonelik + profil tamamlanma). Müşteri sıralamasıyla ilgisi yok.
    $eligibility = mobile_boost_eligibility($pdo, $businessId, (string)($ctx['business_status'] ?? ''));

    $tableReady = mobile_table_has_column($pdo, 'boost_packages', 'id');
    if (!$tableReady) {
        // Boost sistemi henüz kurulmamış → boş ama valid JSON.
        wb_ok([
            'current_boost' => null,
            'packages' => [],
            'history' => [],
            'pending_request' => null,
            'eligible' => $eligibility['eligible'],
            'missing_requirements' => $eligibility['missing'],
        ]);
    }

    $featuresToList = static function ($raw): array {
        $s = trim((string)$raw);
        if ($s === '') {
            return [];
        }
        $decoded = json_decode($s, true);
        if (is_array($decoded)) {
            return array_values(array_filter(array_map('strval', $decoded), static fn($x) => $x !== ''));
        }
        return array_values(array_filter(array_map('trim', explode(';', $s)), static fn($x) => $x !== ''));
    };

    // Paketler.
    $pkgStmt = $pdo->query(
        "SELECT id, name, description, price, duration_days, priority_weight, features, is_active
         FROM boost_packages WHERE is_active = 1 ORDER BY sort_order ASC, price ASC"
    );
    $packages = array_map(static function (array $r) use ($featuresToList): array {
        return [
            'id'             => (int)$r['id'],
            'name'           => (string)$r['name'],
            'description'    => $r['description'] ?? null,
            'price'          => (float)$r['price'],
            'duration_days'  => (int)$r['duration_days'],
            'priority_weight' => (int)$r['priority_weight'],
            'features'       => $featuresToList($r['features'] ?? ''),
            'is_active'      => (bool)$r['is_active'],
        ];
    }, $pkgStmt->fetchAll() ?: []);

    // Mevcut aktif abonelik (varsa).
    $currentBoost = null;
    if (mobile_table_has_column($pdo, 'business_boost_subscriptions', 'id')) {
        $curStmt = $pdo->prepare(
            "SELECT s.id, s.package_id, s.status, s.starts_at, s.ends_at, s.paid_amount, s.payment_status,
                    p.name AS package_name
             FROM business_boost_subscriptions s
             LEFT JOIN boost_packages p ON p.id = s.package_id
             WHERE s.business_id = ? AND s.status = 'active'
               AND (s.ends_at IS NULL OR s.ends_at >= NOW())
             ORDER BY s.ends_at DESC, s.id DESC LIMIT 1"
        );
        $curStmt->execute([$businessId]);
        $cur = $curStmt->fetch();
        if ($cur) {
            $endsAt = $cur['ends_at'] ?? null;
            $daysLeft = null;
            if ($endsAt) {
                $diff = (strtotime((string)$endsAt) - time());
                $daysLeft = $diff > 0 ? (int)ceil($diff / 86400) : 0;
            }
            $currentBoost = [
                'id'           => (int)$cur['id'],
                'package_id'   => (int)$cur['package_id'],
                'package_name' => $cur['package_name'] ?? null,
                'status'       => (string)$cur['status'],
                'starts_at'    => $cur['starts_at'] ?? null,
                'ends_at'      => $endsAt,
                'days_left'    => $daysLeft,
                'paid_amount'  => $cur['paid_amount'] !== null ? (float)$cur['paid_amount'] : null,
            ];
        }
    }

    // Geçmiş: abonelikler + talepler (en yeni 20).
    $pendingRequest = null;
    if (mobile_table_has_column($pdo, 'business_boost_requests', 'id')) {
        $pendingStmt = $pdo->prepare(
            "SELECT r.id, r.package_id, r.status, r.note, r.created_at, p.name AS package_name
             FROM business_boost_requests r
             LEFT JOIN boost_packages p ON p.id = r.package_id
             WHERE r.business_id = ? AND r.status = 'pending'
             ORDER BY r.created_at DESC, r.id DESC LIMIT 1"
        );
        $pendingStmt->execute([$businessId]);
        $pending = $pendingStmt->fetch();
        if ($pending) {
            $pendingRequest = [
                'id' => (int)$pending['id'],
                'package_id' => (int)$pending['package_id'],
                'package_name' => $pending['package_name'] ?? null,
                'status' => (string)$pending['status'],
                'note' => $pending['note'] ?? null,
                'created_at' => $pending['created_at'] ?? null,
            ];
        }
    }

    $history = [];
    if (mobile_table_has_column($pdo, 'business_boost_subscriptions', 'id')) {
        $hStmt = $pdo->prepare(
            "SELECT s.created_at, s.status, s.paid_amount AS amount, p.name AS package_name, 'subscription' AS kind
             FROM business_boost_subscriptions s
             LEFT JOIN boost_packages p ON p.id = s.package_id
             WHERE s.business_id = ?
             ORDER BY s.created_at DESC LIMIT 20"
        );
        $hStmt->execute([$businessId]);
        foreach ($hStmt->fetchAll() ?: [] as $r) {
            $history[] = [
                'kind'         => 'subscription',
                'package_name' => $r['package_name'] ?? null,
                'date'         => $r['created_at'] ?? null,
                'amount'       => $r['amount'] !== null ? (float)$r['amount'] : null,
                'status'       => (string)($r['status'] ?? ''),
            ];
        }
    }
    if (mobile_table_has_column($pdo, 'business_boost_requests', 'id')) {
        $rStmt = $pdo->prepare(
            "SELECT r.created_at, r.status, p.name AS package_name
             FROM business_boost_requests r
             LEFT JOIN boost_packages p ON p.id = r.package_id
             WHERE r.business_id = ?
             ORDER BY r.created_at DESC LIMIT 20"
        );
        $rStmt->execute([$businessId]);
        foreach ($rStmt->fetchAll() ?: [] as $r) {
            $history[] = [
                'kind'         => 'request',
                'package_name' => $r['package_name'] ?? null,
                'date'         => $r['created_at'] ?? null,
                'amount'       => null,
                'status'       => (string)($r['status'] ?? 'pending'),
            ];
        }
    }
    // Tarihe göre sırala (yeni → eski).
    usort($history, static fn($a, $b) => strcmp((string)($b['date'] ?? ''), (string)($a['date'] ?? '')));

    wb_ok([
        'current_boost' => $currentBoost,
        'packages'      => $packages,
        'history'       => $history,
        'pending_request' => $pendingRequest,
        'eligible' => $eligibility['eligible'],
        'missing_requirements' => $eligibility['missing'],
    ]);
} catch (Throwable $e) {
    error_log('[mobile/business/boost-packages.php] ' . $e->getMessage());
    wb_err('Boost paketleri alınamadı. Lütfen tekrar deneyin.', 500, 'internal_error');
}
