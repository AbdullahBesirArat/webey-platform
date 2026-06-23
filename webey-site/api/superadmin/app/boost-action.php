<?php
declare(strict_types=1);
/**
 * api/superadmin/app/boost-action.php
 * POST — Superadmin boost talebi ONAY/RET (Faz 2).
 *
 * Güvenlik: superadmin auth + CSRF (superadmin/_bootstrap.php), transaction,
 * prepared statement, audit (business_subscription_audit, action=boost_approve|boost_reject).
 * Müşteri sıralaması/görünürlüğü DEĞİŞMEZ (Faz 3). Silme YOK.
 *
 * Body (JSON):
 *   action     : approve_request | reject_request (zorunlu)
 *   request_id : int (zorunlu)
 *   opsiyonel  : starts_at (approve), notes/reason
 *
 * Onayda: uygunluk yeniden kontrol edilir; aktif business_boost_subscriptions
 * oluşturulur; talep 'approved' olur. Uygun değilse 422 boost_not_eligible.
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/_helpers.php';
// Uygunluk kontrolünü business app ile AYNI kaynaktan yap (tek doğruluk kaynağı).
require_once __DIR__ . '/../../mobile/_bootstrap.php';
require_once __DIR__ . '/../../mobile/business/_helpers.php';
wb_method('POST');

$in        = wb_body();
$action    = trim((string)($in['action'] ?? ''));
$requestId = (int)($in['request_id'] ?? 0);
$actorId   = (int)($user['user_id'] ?? 0);

if (!in_array($action, ['approve_request', 'reject_request'], true)) {
    wb_err('Geçersiz aksiyon', 422, 'invalid_action');
}
if ($requestId <= 0) {
    wb_err('Geçersiz talep id', 422, 'invalid_request_id');
}

$notes = null;
if (isset($in['notes'])) {
    $notes = mb_substr(trim((string)$in['notes']), 0, 500);
} elseif (isset($in['reason'])) {
    $notes = mb_substr(trim((string)$in['reason']), 0, 500);
}
$startsAtIn = trim((string)($in['starts_at'] ?? ''));

/** Audit satırı (boost için subscription_id = NULL, business_id dolu). */
function sa_boost_audit(PDO $pdo, int $businessId, string $action, string $from, string $to, array $payload, ?int $actorId): void
{
    $pdo->prepare(
        "INSERT INTO business_subscription_audit
            (subscription_id, business_id, action, from_status, to_status, payload_json, actor_user_id, created_at)
         VALUES (NULL, ?, ?, ?, ?, ?, ?, NOW())"
    )->execute([
        $businessId, $action, $from, $to,
        json_encode($payload, JSON_UNESCAPED_UNICODE),
        $actorId ?: null,
    ]);
}

try {
    $pdo->beginTransaction();

    // Talebi kilitle.
    $req = sa_row($pdo, "SELECT * FROM business_boost_requests WHERE id = ? FOR UPDATE", [$requestId]);
    if (!$req) {
        $pdo->rollBack();
        wb_err('Talep bulunamadı', 404, 'request_not_found');
    }
    if ((string)$req['status'] !== 'pending') {
        $pdo->rollBack();
        wb_err('Bu talep zaten işlenmiş (yalnızca bekleyen talepler işlenebilir).', 409, 'request_not_pending');
    }

    $businessId = (int)$req['business_id'];
    $packageId  = (int)$req['package_id'];

    // ── REDDET ──────────────────────────────────────────────────────────────
    if ($action === 'reject_request') {
        $newNote = ($notes !== null && $notes !== '') ? $notes : ($req['note'] ?? null);
        $pdo->prepare("UPDATE business_boost_requests SET status='rejected', note=?, updated_at=NOW() WHERE id=?")
            ->execute([$newNote, $requestId]);
        sa_boost_audit($pdo, $businessId, 'boost_reject', 'pending', 'rejected',
            ['request_id' => $requestId, 'package_id' => $packageId, 'reason' => $newNote], $actorId);
        $pdo->commit();
        wb_ok(['message' => 'Talep reddedildi.', 'request_id' => $requestId, 'status' => 'rejected']);
    }

    // ── ONAYLA ──────────────────────────────────────────────────────────────
    // Paket aktif mi?
    $pkg = sa_row($pdo, "SELECT id, name, price, duration_days, is_active FROM boost_packages WHERE id = ?", [$packageId]);
    if (!$pkg) {
        $pdo->rollBack();
        wb_err('Paket bulunamadı', 404, 'package_not_found');
    }
    if ((int)$pkg['is_active'] !== 1) {
        $pdo->rollBack();
        wb_err('Paket aktif değil', 422, 'package_inactive');
    }

    // İşletme + uygunluk (business app ile aynı kurallar).
    $biz = sa_row($pdo, "SELECT id, status FROM businesses WHERE id = ?", [$businessId]);
    if (!$biz) {
        $pdo->rollBack();
        wb_err('İşletme bulunamadı', 404, 'business_not_found');
    }
    $elig = mobile_boost_eligibility($pdo, $businessId, (string)$biz['status']);
    if (!$elig['eligible']) {
        $pdo->rollBack();
        wb_err('İşletme boost için uygun değil.', 422, 'boost_not_eligible', ['missing_requirements' => $elig['missing']]);
    }

    $startsAt = $startsAtIn !== '' ? $startsAtIn : date('Y-m-d H:i:s');
    $endsAt   = date('Y-m-d H:i:s', strtotime($startsAt . ' +' . (int)$pkg['duration_days'] . ' days'));
    $price    = (float)$pkg['price'];

    // Aktif boost aboneliği oluştur.
    $pdo->prepare(
        "INSERT INTO business_boost_subscriptions
            (business_id, package_id, status, starts_at, ends_at, paid_amount, payment_status, created_at, updated_at)
         VALUES (?,?, 'active', ?,?,?, 'paid', NOW(), NOW())"
    )->execute([$businessId, $packageId, $startsAt, $endsAt, $price]);
    $boostSubId = (int)$pdo->lastInsertId();

    // Talebi onayla.
    $approveNote = ($notes !== null && $notes !== '') ? $notes : ($req['note'] ?? null);
    $pdo->prepare("UPDATE business_boost_requests SET status='approved', note=?, updated_at=NOW() WHERE id=?")
        ->execute([$approveNote, $requestId]);

    sa_boost_audit($pdo, $businessId, 'boost_approve', 'pending', 'approved', [
        'request_id'            => $requestId,
        'package_id'            => $packageId,
        'boost_subscription_id' => $boostSubId,
        'starts_at'             => $startsAt,
        'ends_at'               => $endsAt,
    ], $actorId);

    $pdo->commit();

    wb_ok([
        'message'               => 'Boost talebi onaylandı, aktif boost oluşturuldu.',
        'request_id'            => $requestId,
        'status'                => 'approved',
        'boost_subscription_id' => $boostSubId,
        'starts_at'             => $startsAt,
        'ends_at'               => $endsAt,
    ]);
} catch (Throwable $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    error_log('[superadmin/app/boost-action] ' . $e->getMessage());
    wb_err('İşlem tamamlanamadı. Lütfen tekrar deneyin.', 500, 'action_failed');
}
