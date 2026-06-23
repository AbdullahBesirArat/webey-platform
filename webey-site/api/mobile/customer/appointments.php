<?php
declare(strict_types=1);
/**
 * api/mobile/customer/appointments.php
 * GET — Token sahibi müşterinin randevularını döner (sayfalı).
 *
 * Query params:
 *   status   : upcoming | past | cancelled | all  (default: all)
 *   page     : int >= 1                            (default: 1)
 *   limit    : int 1-50                            (default: 20)
 *
 * Güvenlik: customer_user_id veya normalize edilmiş telefon eşleşmesi ile
 * sadece token sahibine ait randevular döner.
 *
 * Faz 4A — Bearer token zorunlu, customer tipi.
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';
require_once __DIR__ . '/../_payment_settings.php';
require_once __DIR__ . '/../business/_gallery_helpers.php';

wb_method('GET');

$session = mobile_auth($pdo, 'customer');
$userId  = $session['user_id'];

// ── Query parametreleri ───────────────────────────────────────────────────────
$rawStatus = mobile_param('status', 'all');
$status    = in_array($rawStatus, ['upcoming', 'past', 'cancelled', 'all'], true)
    ? $rawStatus
    : 'all';

$page   = max(1, (int)(mobile_int_param('page', 1) ?? 1));
$limit  = mobile_limit(mobile_param('limit', 20), 20, 50);
$offset = ($page - 1) * $limit;

try {
    // ── Müşterinin normalize telefon numarası ─────────────────────────────────
    // Bazı eski randevular customer_user_id olmadan sadece telefon ile kayıtlı.
    // Web endpoint ile aynı çift-kontrol mantığı uygulanıyor.
    $cPhoneStmt = $pdo->prepare("SELECT phone FROM customers WHERE user_id = ? LIMIT 1");
    $cPhoneStmt->execute([$userId]);
    $rawPhone  = preg_replace('/\D/', '', (string)($cPhoneStmt->fetchColumn() ?: ''));
    $phone10   = $rawPhone !== '' ? substr($rawPhone, -10) : '';

    // ── Kimlik koşulu ─────────────────────────────────────────────────────────
    // $identitySql ve $identityParams hiçbir kullanıcı girdisi içermiyor;
    // $userId ve $phone10 prepared statement parametresi olarak bağlanıyor.
    if ($phone10 !== '') {
        $identitySql    = "(a.customer_user_id = ? OR RIGHT(REPLACE(REPLACE(REPLACE(COALESCE(a.customer_phone,''),'+',''),' ',''),'-',''), 10) = ?)";
        $identityParams = [$userId, $phone10];
    } else {
        $identitySql    = 'a.customer_user_id = ?';
        $identityParams = [$userId];
    }

    // ── Durum filtresi ────────────────────────────────────────────────────────
    // Tüm koşullar hardcoded — kullanıcı girdisi SQL'e dahil edilmiyor.
    $statusSql = match ($status) {
        'upcoming'  => "AND a.start_at > NOW()
                        AND a.status NOT IN ('cancelled','completed','no_show','rejected','declined','cancellation_requested')",
        'past'      => "AND (
                            a.status = 'completed'
                            OR (a.start_at <= NOW() AND a.status NOT IN ('cancelled','cancellation_requested','rejected','declined','no_show'))
                        )",
        'cancelled' => "AND a.status IN ('cancelled','cancellation_requested','rejected','declined')",
        default     => 'AND a.start_at >= NOW() - INTERVAL 12 MONTH',
    };

    // ── Toplam kayıt sayısı ───────────────────────────────────────────────────
    $countSql  = "SELECT COUNT(*) FROM appointments a WHERE $identitySql $statusSql";
    $countStmt = $pdo->prepare($countSql);
    $countStmt->execute($identityParams);
    $total = (int)$countStmt->fetchColumn();

    // ── Deposit kolon / tablo varlık kontrolleri ─────────────────────────────
    $hasApptDepositCols  = mobile_table_has_column($pdo, 'appointments', 'deposit_required');
    $hasManualDeposit    = mobile_table_has_column($pdo, 'appointments', 'deposit_status');
    $hasPaymentsTable    = mobile_table_has_column($pdo, 'appointment_payments', 'id');
    $depositApptSelect   = $hasApptDepositCols
        ? ",\n            a.deposit_required,\n            a.deposit_amount"
        : '';
    // Manuel (IBAN) kapora kolonları varsa onları kullan; yoksa eski iyzico join.
    if ($hasManualDeposit) {
        $depositPaymentsSel  = ",\n            a.deposit_status,\n            a.deposit_reference_code,\n            a.deposit_paid_at";
        $depositPaymentsJoin = '';
    } elseif ($hasPaymentsTable) {
        $depositPaymentsSel  = ",\n            ap.status   AS deposit_status,\n            NULL        AS deposit_reference_code,\n            ap.paid_at  AS deposit_paid_at";
        $depositPaymentsJoin = 'LEFT JOIN appointment_payments ap ON ap.appointment_id = a.id';
    } else {
        $depositPaymentsSel  = '';
        $depositPaymentsJoin = '';
    }
    // Kampanya/fiyat snapshot kolonları (migration sonrası). Salonda kalan tutarı
    // indirim sonrası final üzerinden gösterilebilsin diye döndürülür.
    $hasApptCampaignCols = mobile_table_has_column($pdo, 'appointments', 'final_amount');
    $campaignApptSelect  = $hasApptCampaignCols
        ? ",\n            a.original_amount,\n            a.final_amount,\n            a.campaign_discount_amount,\n            a.campaign_title_snapshot"
        : '';
    $hasCancelResultCols = mobile_table_has_column($pdo, 'appointments', 'cancel_refund_amount');
    $cancelResultSelect  = $hasCancelResultCols
        ? ",\n            a.paid_deposit_amount_snapshot,\n            a.cancel_refund_amount,\n            a.cancel_retained_amount,\n            a.cancel_rule_result"
        : '';
    $hasReviewsTable     = mobile_table_has_column($pdo, 'reviews', 'id');
    $reviewSelect        = $hasReviewsTable ? ",\n            r.id AS review_id" : '';
    $reviewJoin          = $hasReviewsTable
        ? 'LEFT JOIN reviews r ON r.appointment_id = a.id'
        : '';

    // ── Ana sorgu ─────────────────────────────────────────────────────────────
    $mainSql = "
        SELECT
            a.id,
            a.status,
            a.start_at,
            a.end_at,
            a.notes,
            b.id            AS biz_id,
            b.name          AS biz_name,
            b.slug          AS biz_slug,
            b.city,
            b.district,
            b.address_line,
            b.images_json,
            s.id            AS svc_id,
            s.name          AS svc_name,
            s.price         AS svc_price,
            s.duration_min  AS svc_duration,
            st.id           AS staff_row_id,
            st.name         AS staff_name
            $depositApptSelect
            $depositPaymentsSel
            $campaignApptSelect
            $cancelResultSelect
            $reviewSelect
        FROM appointments a
        LEFT JOIN businesses b  ON b.id  = a.business_id
        LEFT JOIN services   s  ON s.id  = a.service_id
        LEFT JOIN staff      st ON st.id = a.staff_id
        $depositPaymentsJoin
        $reviewJoin
        WHERE $identitySql
        $statusSql
        ORDER BY a.start_at DESC
        LIMIT ? OFFSET ?
    ";
    $mainStmt = $pdo->prepare($mainSql);
    $mainStmt->execute(array_merge($identityParams, [(int)$limit, (int)$offset]));
    $rows = $mainStmt->fetchAll();

    // ── Salon IBAN/kapora ayarları (sadece kaporalı randevular için) ──────────
    // Müşteri yalnızca kendi randevularını gördüğü için IBAN burada gösterilebilir.
    $paymentByBusiness = [];
    $bizIdsForPayment = [];
    foreach ($rows as $r) {
        if (!empty($r['deposit_required']) && $r['biz_id'] !== null) {
            $bizIdsForPayment[(int)$r['biz_id']] = true;
        }
    }
    foreach (array_keys($bizIdsForPayment) as $bizId) {
        $paymentByBusiness[$bizId] = wb_business_payment_settings($pdo, (int)$bizId);
    }

    $bizIds = [];
    foreach ($rows as $r) {
        if ($r['biz_id'] !== null) {
            $bizIds[(int)$r['biz_id']] = true;
        }
    }

    $coverByBusiness = [];
    $coverIds = array_keys($bizIds);
    if ($coverIds !== [] && mobile_gallery_table_exists($pdo)) {
        $placeholders = implode(',', array_fill(0, count($coverIds), '?'));
        $coverStmt = $pdo->prepare("
            SELECT bp.*
            FROM business_photos bp
            INNER JOIN (
                SELECT business_id, MAX(id) AS id
                FROM business_photos
                WHERE business_id IN ($placeholders)
                  AND status = 'active'
                  AND is_visible = 1
                  AND is_cover = 1
                GROUP BY business_id
            ) picked ON picked.id = bp.id
        ");
        $coverStmt->execute($coverIds);
        foreach ($coverStmt->fetchAll() as $coverRow) {
            $coverByBusiness[(int)$coverRow['business_id']] = mobile_gallery_item($coverRow);
        }
    }

    $hasManualDepositFlag = $hasManualDeposit;

    // ── Satırları formatla ────────────────────────────────────────────────────
    $items = array_map(static function (array $r) use (
        $hasApptDepositCols,
        $hasPaymentsTable,
        $hasManualDepositFlag,
        $hasReviewsTable,
        $hasCancelResultCols,
        $paymentByBusiness,
        $coverByBusiness
    ): array {
        $images = mobile_images($r['images_json'] ?? null);
        $coverItem = $r['biz_id'] !== null ? ($coverByBusiness[(int)$r['biz_id']] ?? null) : null;
        $coverUrl = $coverItem['medium_url'] ?? $coverItem['large_url'] ?? $coverItem['url'] ?? $images['cover_image_url'];

        // Süre: service'den al, yoksa start/end farkından hesapla
        $durationMin = null;
        if (!empty($r['svc_duration'])) {
            $durationMin = (int)$r['svc_duration'];
        } elseif (!empty($r['start_at']) && !empty($r['end_at'])) {
            try {
                $tStart = strtotime((string)$r['start_at']);
                $tEnd   = strtotime((string)$r['end_at']);
                if ($tStart !== false && $tEnd !== false && $tEnd > $tStart) {
                    $durationMin = (int)round(($tEnd - $tStart) / 60);
                }
            } catch (Throwable) {
            }
        }

        // Tarih / saat ayrıştır
        $dateStr = '';
        $timeStr = '';
        try {
            if (!empty($r['start_at'])) {
                $dt      = new DateTimeImmutable((string)$r['start_at']);
                $dateStr = $dt->format('Y-m-d');
                $timeStr = $dt->format('H:i');
            }
        } catch (Throwable) {
        }

        // İptal edilebilirlik: sadece pending/approved ve gelecek randevular
        $apptStatus = strtolower((string)($r['status'] ?? ''));
        $canCancel  = in_array($apptStatus, ['pending', 'approved'], true)
            && !empty($r['start_at'])
            && strtotime((string)$r['start_at']) > time();

        return [
            'id'               => (string)$r['id'],
            'status'           => $apptStatus,
            'starts_at'        => (string)($r['start_at'] ?? ''),
            'ends_at'          => (string)($r['end_at'] ?? ''),
            'date'             => $dateStr,
            'time'             => $timeStr,
            'duration_minutes' => $durationMin,
            'salon'            => [
                'id'              => $r['biz_id'] !== null ? (string)$r['biz_id'] : null,
                'slug'            => $r['biz_slug']     ?? null,
                'name'            => $r['biz_name']     ?? null,
                'city'            => $r['city']         ?? null,
                'district'        => $r['district']     ?? null,
                'address'         => $r['address_line'] ?? null,
                'cover_image_url' => $coverUrl,
                'image_url'       => $coverUrl,
            ],
            'service'          => $r['svc_id'] !== null ? [
                'id'               => (string)$r['svc_id'],
                'name'             => $r['svc_name']     ?? null,
                'price'            => $r['svc_price'] !== null ? (float)$r['svc_price'] : null,
                'duration_minutes' => $r['svc_duration'] !== null ? (int)$r['svc_duration'] : null,
            ] : null,
            // Kampanya/fiyat snapshot — randevu oluşturulduğu andaki sabit değerler.
            // Salonda kalan = max(0, final - kapora). Snapshot yoksa null döner.
            'original_amount'  => ($hasApptCampaignCols && ($r['original_amount'] ?? null) !== null)
                ? (float)$r['original_amount'] : null,
            'final_amount'     => ($hasApptCampaignCols && ($r['final_amount'] ?? null) !== null)
                ? (float)$r['final_amount'] : null,
            'campaign_discount_amount' => ($hasApptCampaignCols && ($r['campaign_discount_amount'] ?? null) !== null)
                ? (float)$r['campaign_discount_amount'] : null,
            'campaign_title'   => ($hasApptCampaignCols && ($r['campaign_title_snapshot'] ?? null) !== null && $r['campaign_title_snapshot'] !== '')
                ? (string)$r['campaign_title_snapshot'] : null,
            'remaining_amount' => (static function () use ($r, $hasApptCampaignCols, $hasApptDepositCols): ?float {
                if (!$hasApptCampaignCols || ($r['final_amount'] ?? null) === null) {
                    return null;
                }
                $final = (float)$r['final_amount'];
                $dep = ($hasApptDepositCols && ($r['deposit_amount'] ?? null) !== null && (bool)($r['deposit_required'] ?? false))
                    ? (float)$r['deposit_amount'] : 0.0;
                $rem = $final - $dep;
                return $rem < 0 ? 0.0 : round($rem, 2);
            })(),
            'staff'            => $r['staff_row_id'] !== null ? [
                'id'   => (string)$r['staff_row_id'],
                'name' => $r['staff_name'] ?? null,
            ] : null,
            'deposit'          => (static function () use (
                $r,
                $hasApptDepositCols,
                $hasManualDepositFlag,
                $hasPaymentsTable,
                $paymentByBusiness
            ): array {
                $required = $hasApptDepositCols
                    ? (bool)($r['deposit_required'] ?? false)
                    : false;
                $hasStatusSource = $hasManualDepositFlag || $hasPaymentsTable;
                $refCode = $r['deposit_reference_code'] ?? null;
                if (($refCode === null || $refCode === '') && $required) {
                    // Eski randevular için referans kodu fallback üret.
                    $refCode = 'WEBEY-APT-' . (string)$r['id'];
                }
                $deposit = [
                    'required'       => $required,
                    'amount'         => ($hasApptDepositCols && ($r['deposit_amount'] ?? null) !== null)
                        ? (float)$r['deposit_amount']
                        : null,
                    'status'         => $hasStatusSource ? ($r['deposit_status'] ?? ($required ? 'pending' : null)) : null,
                    'reference_code' => $required ? $refCode : null,
                    'paid_at'        => $hasStatusSource ? ($r['deposit_paid_at'] ?? null) : null,
                ];
                // Salonun IBAN bilgisi yalnızca kapora gerektiren randevularda.
                if ($required && $r['biz_id'] !== null
                    && isset($paymentByBusiness[(int)$r['biz_id']])) {
                    $ps = $paymentByBusiness[(int)$r['biz_id']];
                    $deposit['payment'] = [
                        'deposit_enabled' => $ps['deposit_enabled'],
                        'has_iban'        => $ps['has_iban'],
                        'iban'            => $ps['iban'],
                        'iban_formatted'  => $ps['iban_formatted'],
                        'account_holder'  => $ps['account_holder'],
                        'bank_name'       => $ps['bank_name'],
                        'instructions'    => $ps['instructions'],
                    ];
                } else {
                    $deposit['payment'] = null;
                }
                return $deposit;
            })(),
            'cancellation'     => ($hasCancelResultCols && ($r['cancel_rule_result'] ?? null) !== null) ? [
                'paid_deposit'    => ($r['paid_deposit_amount_snapshot'] ?? null) !== null ? (float)$r['paid_deposit_amount_snapshot'] : 0.0,
                'refund_amount'   => ($r['cancel_refund_amount'] ?? null) !== null ? (float)$r['cancel_refund_amount'] : 0.0,
                'retained_amount' => ($r['cancel_retained_amount'] ?? null) !== null ? (float)$r['cancel_retained_amount'] : 0.0,
                'rule_result'     => (string)$r['cancel_rule_result'],
                'manual_refund'   => (($r['cancel_refund_amount'] ?? 0) > 0),
            ] : null,
            'can_cancel'       => $canCancel,
            'cancel_until'     => null,
            'has_review'       => $hasReviewsTable ? ($r['review_id'] !== null) : false,
        ];
    }, $rows);

    wb_ok([
        'items'      => $items,
        'pagination' => [
            'page'     => $page,
            'limit'    => $limit,
            'total'    => $total,
            'has_more' => ($offset + count($items)) < $total,
        ],
    ]);

} catch (Throwable $e) {
    error_log('[mobile/customer/appointments.php] ' . $e->getMessage());
    wb_err('Randevular alınamadı', 500, 'internal_error');
}
