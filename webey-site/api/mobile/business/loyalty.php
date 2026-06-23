<?php
declare(strict_types=1);
/**
 * api/mobile/business/loyalty.php
 * GET  — Salon sadakat programı + üye ilerlemesi + özet.
 * POST — Sadakat programını upsert eder.
 *
 * Mock veri YOK. Tablolar yoksa boş default + persisted:false döner.
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';
require_once __DIR__ . '/_helpers.php';
require_once __DIR__ . '/../_loyalty.php';

$method = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');
if ($method !== 'GET' && $method !== 'POST') {
    wb_err('Yöntem desteklenmiyor', 405, 'method_not_allowed');
}

$auth = mobile_auth($pdo, ['business', 'admin']);
$ctx = mobile_business_context($pdo, $auth);
$businessId = (int)$ctx['business_id'];

$tablesReady = wb_loyalty_tables_ready($pdo);

if ($method === 'GET') {
    $program = wb_loyalty_program($pdo, $businessId);
    $summary = [
        'active_members' => 0,
        'earned_this_month' => 0,
        'rewards_used' => 0,
    ];
    $members = [];

    if ($tablesReady) {
        try {
            $tz = new DateTimeZone('Europe/Istanbul');
            $monthStart = (new DateTimeImmutable('now', $tz))->format('Y-m-01 00:00:00');

            $aStmt = $pdo->prepare(
                'SELECT COUNT(*) FROM business_loyalty_progress
                   WHERE business_id = ? AND (visits_count > 0 OR rewards_earned > 0)'
            );
            $aStmt->execute([$businessId]);
            $summary['active_members'] = (int)$aStmt->fetchColumn();

            $eStmt = $pdo->prepare(
                "SELECT COUNT(*) FROM business_loyalty_events
                   WHERE business_id = ? AND event_type = 'reward_earned'
                     AND created_at >= ?"
            );
            $eStmt->execute([$businessId, $monthStart]);
            $summary['earned_this_month'] = (int)$eStmt->fetchColumn();

            $uStmt = $pdo->prepare(
                "SELECT COALESCE(SUM(rewards_used), 0) FROM business_loyalty_progress
                   WHERE business_id = ?"
            );
            $uStmt->execute([$businessId]);
            $summary['rewards_used'] = (int)$uStmt->fetchColumn();

            $mStmt = $pdo->prepare(
                'SELECT id, customer_name, customer_phone, visits_count,
                        rewards_earned, rewards_used, last_visit_at
                   FROM business_loyalty_progress
                  WHERE business_id = ?
                  ORDER BY last_visit_at DESC, id DESC
                  LIMIT 100'
            );
            $mStmt->execute([$businessId]);
            $required = max(1, (int)$program['required_visits']);
            foreach ($mStmt->fetchAll() ?: [] as $row) {
                $visits = (int)$row['visits_count'];
                $earned = (int)$row['rewards_earned'];
                $used = (int)$row['rewards_used'];
                $available = max(0, $earned - $used);
                $remaining = max(0, $required - $visits);
                $members[] = [
                    'id' => (int)$row['id'],
                    'customer_name' => (string)($row['customer_name'] ?? ''),
                    'customer_phone' => $row['customer_phone'] ?? null,
                    'visits_count' => $visits,
                    'rewards_earned' => $earned,
                    'rewards_used' => $used,
                    'rewards_available' => $available,
                    'required_visits' => $required,
                    'remaining_visits' => $remaining,
                    'reward_ready' => $available > 0,
                    'last_visit_at' => $row['last_visit_at'] ?? null,
                ];
            }
        } catch (Throwable $e) {
            error_log('[mobile/business/loyalty.php GET] ' . $e->getMessage());
        }
    }

    wb_ok([
        'program' => $program,
        'summary' => $summary,
        'members' => $members,
        'persisted' => $tablesReady,
    ]);
}

// ── POST: program upsert ─────────────────────────────────────────────────────
if (!$tablesReady) {
    wb_err('Sadakat servisi şu an kullanılamıyor', 503, 'loyalty_unavailable');
}

$in = wb_body();
$isActive = ($in['is_active'] ?? false) === true
    || ($in['is_active'] ?? null) === 1
    || ($in['is_active'] ?? null) === '1';
$requiredVisits = max(1, min(99, (int)($in['required_visits'] ?? 5)));
$rewardTitle = mb_substr(trim((string)($in['reward_title'] ?? '')), 0, 160);
$rewardDescRaw = (string)($in['reward_description'] ?? '');
$rewardDesc = mb_substr(trim($rewardDescRaw), 0, 1000);

if ($isActive && $rewardTitle === '') {
    wb_err('Programı aktif etmek için ödül başlığı zorunlu.', 422, 'reward_title_required');
}

try {
    $pdo->prepare(
        'INSERT INTO business_loyalty_programs
            (business_id, is_active, required_visits, reward_title, reward_description, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, NOW(), NOW())
         ON DUPLICATE KEY UPDATE
            is_active = VALUES(is_active),
            required_visits = VALUES(required_visits),
            reward_title = VALUES(reward_title),
            reward_description = VALUES(reward_description),
            updated_at = NOW()'
    )->execute([
        $businessId,
        $isActive ? 1 : 0,
        $requiredVisits,
        $rewardTitle,
        $rewardDesc !== '' ? $rewardDesc : null,
    ]);
} catch (Throwable $e) {
    error_log('[mobile/business/loyalty.php POST] ' . $e->getMessage());
    wb_err('Sadakat programı kaydedilemedi.', 500, 'internal_error');
}

wb_ok([
    'program' => wb_loyalty_program($pdo, $businessId),
    'persisted' => true,
    'message' => 'Sadakat programı kaydedildi.',
]);
