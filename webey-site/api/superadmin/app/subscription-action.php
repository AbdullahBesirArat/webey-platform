<?php
declare(strict_types=1);
/**
 * api/superadmin/app/subscription-action.php
 * POST — Superadmin abonelik YAZMA aksiyonları (Faz 2).
 *
 * Güvenlik: superadmin auth + CSRF (api/superadmin/_bootstrap.php üzerinden),
 * tüm yazmalar transaction içinde, prepared statement, her aksiyon audit'e yazılır.
 * Eski web/iyzico `subscriptions` tablosuna DOKUNMAZ. Silme YOK.
 *
 * Body (JSON):
 *   business_id : int (zorunlu)
 *   action      : start_trial|activate|record_payment|mark_overdue|suspend|cancel|update_note
 *   opsiyonel   : amount, method, paid_at, period_start, period_end, reference, notes
 *
 * Yanıt: { ok:true, data:{ message, business_id, status, subscription_id } }
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/_helpers.php';
wb_method('POST');

const SA_SUB_ACTIONS = ['start_trial', 'activate', 'record_payment', 'mark_overdue', 'suspend', 'cancel', 'update_note'];
const SA_SUB_METHODS = ['manual_iban', 'cash', 'card_manual', 'free', 'comped'];

$in         = wb_body();
$businessId = (int)($in['business_id'] ?? 0);
$action     = trim((string)($in['action'] ?? ''));
$actorId    = (int)($user['user_id'] ?? 0);

if ($businessId <= 0) {
    wb_err('Geçersiz işletme id', 422, 'invalid_business_id');
}
if (!in_array($action, SA_SUB_ACTIONS, true)) {
    wb_err('Geçersiz aksiyon', 422, 'invalid_action');
}

// ── Girdi alanları + ön validasyon (transaction DIŞINDA) ─────────────────────
$notes       = isset($in['notes'])     ? mb_substr(trim((string)$in['notes']), 0, 2000)    : null;
$reference   = isset($in['reference']) ? mb_substr(trim((string)$in['reference']), 0, 160)  : null;
$method      = trim((string)($in['method'] ?? ''));
$amount      = (isset($in['amount']) && $in['amount'] !== '') ? (float)$in['amount'] : null;
$paidAtIn    = trim((string)($in['paid_at'] ?? ''));
$periodStart = trim((string)($in['period_start'] ?? ''));
$periodEnd   = trim((string)($in['period_end'] ?? ''));

if ($amount !== null && $amount < 0) {
    wb_err('Tutar negatif olamaz', 422, 'invalid_amount');
}
if ($periodStart !== '' && $periodEnd !== '' && strtotime($periodEnd) < strtotime($periodStart)) {
    wb_err('Dönem bitişi başlangıçtan önce olamaz', 422, 'invalid_period');
}
if ($action === 'record_payment') {
    if ($method === '') {
        $method = 'manual_iban';
    }
    if (!in_array($method, SA_SUB_METHODS, true)) {
        wb_err('Geçersiz ödeme yöntemi', 422, 'invalid_method');
    }
}

try {
    // İşletme gerçekten var mı?
    $biz = sa_row($pdo, "SELECT id, name, status FROM businesses WHERE id = ?", [$businessId]);
    if (!$biz) {
        wb_err('İşletme bulunamadı', 404, 'business_not_found');
    }

    // Plan (webey_business) — fiyat/trial referansı.
    $plan = sa_row($pdo, "SELECT id, monthly_price, trial_days FROM business_subscription_plans
                          WHERE code = 'webey_business' AND is_active = 1 LIMIT 1");
    if (!$plan) {
        wb_err('Abonelik planı bulunamadı', 500, 'plan_missing');
    }
    $planId    = (int)$plan['id'];
    $planPrice = (float)$plan['monthly_price'];
    $trialDays = (int)$plan['trial_days'];

    if ($action === 'record_payment' && $amount === null) {
        $amount = $planPrice;
    }

    $pdo->beginTransaction();

    // İşletmenin en güncel abonelik kaydı (kilitli).
    $sub        = sa_row($pdo, "SELECT * FROM business_subscriptions WHERE business_id = ? ORDER BY id DESC LIMIT 1 FOR UPDATE", [$businessId]);
    $fromStatus = $sub['status'] ?? null;
    $now        = date('Y-m-d H:i:s');

    // Mevcut kayıt gerektiren aksiyonlar.
    if (in_array($action, ['mark_overdue', 'suspend', 'cancel', 'update_note'], true) && !$sub) {
        $pdo->rollBack();
        wb_err('Bu işletmenin aboneliği yok. Önce deneme başlatın veya ödeme kaydedin.', 422, 'no_subscription');
    }

    $existingMonthly = ($sub && $sub['monthly_price'] !== null) ? (float)$sub['monthly_price'] : $planPrice;
    $toStatus        = $fromStatus;
    $subId           = $sub ? (int)$sub['id'] : 0;
    $payload         = ['action' => $action];

    switch ($action) {
        case 'start_trial': {
            $trialEnd = date('Y-m-d H:i:s', time() + $trialDays * 86400);
            if ($sub) {
                $pdo->prepare(
                    "UPDATE business_subscriptions
                     SET status='trial', plan_id=?, monthly_price=?, trial_started_at=?, trial_ends_at=?,
                         current_period_start=?, current_period_end=?, next_payment_due_at=?,
                         payment_method=NULL, updated_by=?, updated_at=NOW()
                     WHERE id=?"
                )->execute([$planId, $planPrice, $now, $trialEnd, $now, $trialEnd, $trialEnd, $actorId, $subId]);
            } else {
                $pdo->prepare(
                    "INSERT INTO business_subscriptions
                        (business_id, plan_id, status, monthly_price, trial_started_at, trial_ends_at,
                         current_period_start, current_period_end, next_payment_due_at, created_by, updated_by, created_at, updated_at)
                     VALUES (?,?, 'trial', ?,?,?,?,?,?,?,?, NOW(), NOW())"
                )->execute([$businessId, $planId, $planPrice, $now, $trialEnd, $now, $trialEnd, $trialEnd, $actorId, $actorId]);
                $subId = (int)$pdo->lastInsertId();
            }
            $toStatus = 'trial';
            $payload['trial_ends_at'] = $trialEnd;
            break;
        }

        case 'activate': {
            $ps = $periodStart !== '' ? $periodStart : $now;
            $pe = $periodEnd   !== '' ? $periodEnd   : date('Y-m-d H:i:s', strtotime($ps . ' +1 month'));
            if ($sub) {
                $pdo->prepare(
                    "UPDATE business_subscriptions
                     SET status='active', plan_id=?, monthly_price=?, current_period_start=?, current_period_end=?,
                         next_payment_due_at=?, updated_by=?, updated_at=NOW()
                     WHERE id=?"
                )->execute([$planId, $existingMonthly, $ps, $pe, $pe, $actorId, $subId]);
            } else {
                $pdo->prepare(
                    "INSERT INTO business_subscriptions
                        (business_id, plan_id, status, monthly_price, current_period_start, current_period_end,
                         next_payment_due_at, created_by, updated_by, created_at, updated_at)
                     VALUES (?,?, 'active', ?,?,?,?,?,?, NOW(), NOW())"
                )->execute([$businessId, $planId, $planPrice, $ps, $pe, $pe, $actorId, $actorId]);
                $subId = (int)$pdo->lastInsertId();
            }
            $toStatus = 'active';
            $payload['current_period_end'] = $pe;
            break;
        }

        case 'record_payment': {
            $pAt = $paidAtIn    !== '' ? $paidAtIn    : $now;
            $ps  = $periodStart !== '' ? $periodStart : $now;
            $pe  = $periodEnd   !== '' ? $periodEnd   : date('Y-m-d H:i:s', strtotime($ps . ' +1 month'));
            // Abonelik kaydı yoksa oluştur, varsa aktif et. monthly_price = plan/mevcut (ödeme tutarı DEĞİL).
            if ($sub) {
                $pdo->prepare(
                    "UPDATE business_subscriptions
                     SET status='active', plan_id=?, monthly_price=?, current_period_start=?, current_period_end=?,
                         last_payment_at=?, next_payment_due_at=?, payment_method=?, updated_by=?, updated_at=NOW()
                     WHERE id=?"
                )->execute([$planId, $existingMonthly, $ps, $pe, $pAt, $pe, $method, $actorId, $subId]);
            } else {
                $pdo->prepare(
                    "INSERT INTO business_subscriptions
                        (business_id, plan_id, status, monthly_price, current_period_start, current_period_end,
                         last_payment_at, next_payment_due_at, payment_method, created_by, updated_by, created_at, updated_at)
                     VALUES (?,?, 'active', ?,?,?,?,?,?,?,?, NOW(), NOW())"
                )->execute([$businessId, $planId, $planPrice, $ps, $pe, $pAt, $pe, $method, $actorId, $actorId]);
                $subId = (int)$pdo->lastInsertId();
            }
            // Manuel ödeme defterine kayıt.
            $pdo->prepare(
                "INSERT INTO business_subscription_payments
                    (subscription_id, business_id, amount, paid_at, method, period_start, period_end, reference, notes, recorded_by, created_at)
                 VALUES (?,?,?,?,?,?,?,?,?,?, NOW())"
            )->execute([$subId, $businessId, $amount, $pAt, $method, $ps, $pe, $reference, $notes, $actorId]);
            $toStatus = 'active';
            $payload += ['amount' => $amount, 'method' => $method, 'period_start' => $ps, 'period_end' => $pe];
            break;
        }

        case 'mark_overdue': {
            $pdo->prepare("UPDATE business_subscriptions SET status='overdue', updated_by=?, updated_at=NOW() WHERE id=?")
                ->execute([$actorId, $subId]);
            $toStatus = 'overdue';
            break;
        }

        case 'suspend':
        case 'cancel': {
            $newStatus = $action === 'suspend' ? 'suspended' : 'cancelled';
            if ($notes !== null && $notes !== '') {
                $pdo->prepare("UPDATE business_subscriptions SET status=?, notes=?, updated_by=?, updated_at=NOW() WHERE id=?")
                    ->execute([$newStatus, $notes, $actorId, $subId]);
            } else {
                $pdo->prepare("UPDATE business_subscriptions SET status=?, updated_by=?, updated_at=NOW() WHERE id=?")
                    ->execute([$newStatus, $actorId, $subId]);
            }
            $toStatus = $newStatus;
            break;
        }

        case 'update_note': {
            $pdo->prepare("UPDATE business_subscriptions SET notes=?, updated_by=?, updated_at=NOW() WHERE id=?")
                ->execute([$notes, $actorId, $subId]);
            $toStatus = $fromStatus; // statü değişmez
            break;
        }
    }

    // Audit (her aksiyon).
    $pdo->prepare(
        "INSERT INTO business_subscription_audit
            (subscription_id, business_id, action, from_status, to_status, payload_json, actor_user_id, created_at)
         VALUES (?,?,?,?,?,?,?, NOW())"
    )->execute([
        $subId ?: null,
        $businessId,
        $action,
        $fromStatus,
        $toStatus,
        json_encode($payload, JSON_UNESCAPED_UNICODE),
        $actorId ?: null,
    ]);

    $pdo->commit();

    wb_ok([
        'message'         => 'İşlem başarıyla tamamlandı.',
        'business_id'     => $businessId,
        'status'          => $toStatus,
        'subscription_id' => $subId,
    ]);
} catch (Throwable $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    error_log('[superadmin/app/subscription-action] ' . $e->getMessage());
    wb_err('İşlem tamamlanamadı. Lütfen tekrar deneyin.', 500, 'action_failed');
}
