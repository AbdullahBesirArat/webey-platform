<?php
declare(strict_types=1);
/**
 * api/mobile/customer/reviews.php
 * POST — Müşteri randevu değerlendirmesi (puan + opsiyonel yorum).
 *
 * Body (JSON):
 *   appointment_id : int    (zorunlu)
 *   rating         : int    (zorunlu, 1-5)
 *   comment        : string (opsiyonel, <=1000)
 *
 * Kurallar:
 *   - Bearer token zorunlu, customer tipi.
 *   - Randevu bu müşteriye ait olmalı (customer_user_id eşleşmesi).
 *   - Yalnızca 'completed' veya geçmiş tarihli 'approved' randevu değerlendirilebilir.
 *   - Her randevu yalnızca bir kez değerlendirilebilir (duplicate engellenir).
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';
require_once __DIR__ . '/../../_appointment_push.php';

wb_method('POST');

$session = mobile_auth($pdo, 'customer');
$userId  = $session['user_id'];

$in            = wb_body();
$appointmentId = (int)($in['appointment_id'] ?? 0);
$rating        = (int)($in['rating'] ?? 0);
$comment       = trim((string)($in['comment'] ?? ''));

if ($appointmentId <= 0) {
    wb_err('appointment_id zorunlu', 400, 'missing_param');
}
if ($rating < 1 || $rating > 5) {
    wb_err('Puan 1 ile 5 arasında olmalı', 422, 'invalid_rating');
}
if (mb_strlen($comment) > 1000) {
    $comment = mb_substr($comment, 0, 1000);
}

// reviews tablosu yoksa (migration uygulanmamış) net hata dön.
if (!mobile_table_has_column($pdo, 'reviews', 'id')) {
    error_log('[mobile/customer/reviews.php] reviews table missing');
    wb_err('Değerlendirme servisi şu an kullanılamıyor', 503, 'reviews_unavailable');
}

try {
    // ── Randevuyu çek + sahiplik kontrolü ─────────────────────────────────
    $apptStmt = $pdo->prepare(
        'SELECT a.id, a.status, a.start_at, a.business_id, a.service_id, a.staff_id,
                a.customer_user_id, a.customer_name,
                b.owner_id, b.name AS business_name,
                s.name AS service_name
           FROM appointments a
           LEFT JOIN businesses b ON b.id = a.business_id
           LEFT JOIN services s ON s.id = a.service_id
          WHERE a.id = ?
          LIMIT 1'
    );
    $apptStmt->execute([$appointmentId]);
    $appt = $apptStmt->fetch();

    if (!$appt) {
        wb_err('Randevu bulunamadı', 404, 'not_found');
    }
    if ((int)($appt['customer_user_id'] ?? 0) !== $userId) {
        wb_err('Bu randevuya erişim yetkiniz yok', 403, 'forbidden');
    }

    $dupStmt = $pdo->prepare('SELECT id FROM reviews WHERE appointment_id = ? LIMIT 1');
    $dupStmt->execute([$appointmentId]);
    if ($dupStmt->fetch()) {
        wb_err('Bu randevu için daha önce değerlendirme yapılmış.', 409, 'already_reviewed');
    }

    // ── Uygunluk: completed VEYA geçmiş tarihli approved ──────────────────
    $status   = strtolower((string)($appt['status'] ?? ''));
    $isPast   = !empty($appt['start_at']) && strtotime((string)$appt['start_at']) <= time();
    $eligible = ($status === 'completed') || ($status === 'approved' && $isPast);
    if (!$eligible) {
        $reason = match (true) {
            !$isPast => 'Randevu saati henüz geçmediği için değerlendirme yapılamaz.',
            in_array($status, ['cancelled', 'cancellation_requested', 'rejected', 'declined'], true)
                => 'İptal edilen randevular değerlendirilemez.',
            $status === 'no_show' => 'Gelmedi olarak işaretlenen randevular değerlendirilemez.',
            in_array($status, ['pending', 'approved'], true)
                => 'İşletme bu randevuyu henüz tamamlandı olarak işaretlemediği için değerlendirme yapamazsınız.',
            default => 'Bu randevu şu anda değerlendirme için uygun değil.',
        };
        wb_err($reason, 422, 'not_reviewable');
    }

    // ── İlişki alanları (business kesin; staff/service nullable) ───────────
    $businessId = (int)($appt['business_id'] ?? 0);
    $serviceId  = ($appt['service_id'] ?? null) !== null ? (int)$appt['service_id'] : null;
    $staffId    = ($appt['staff_id'] ?? null) !== null ? (int)$appt['staff_id'] : null;
    $hasStaffCol  = mobile_table_has_column($pdo, 'reviews', 'staff_id');
    $hasStatusCol = mobile_table_has_column($pdo, 'reviews', 'status');

    // ── Duplicate kontrolü ────────────────────────────────────────────────
    // ── Kaydet (kolon varlığına göre dinamik) ─────────────────────────────
    $cols = ['appointment_id', 'business_id', 'customer_user_id', 'service_id', 'rating', 'comment'];
    $args = [$appointmentId, $businessId, $userId, $serviceId, $rating, $comment !== '' ? $comment : null];
    if ($hasStaffCol) {
        $cols[] = 'staff_id';
        $args[] = $staffId;
    }
    if ($hasStatusCol) {
        $cols[] = 'status';
        $args[] = 'active';
    }
    $cols[] = 'created_at';
    $placeholders = implode(', ', array_fill(0, count($cols) - 1, '?')) . ', NOW()';
    $insertSql = 'INSERT INTO reviews (' . implode(', ', $cols) . ') VALUES (' . $placeholders . ')';

    try {
        $pdo->prepare($insertSql)->execute($args);
    } catch (PDOException $dupEx) {
        // UNIQUE(appointment_id) yarış durumu — duplicate olarak ele al.
        if ((int)($dupEx->errorInfo[1] ?? 0) === 1062) {
            wb_err('Bu randevu zaten değerlendirildi', 409, 'already_reviewed');
        }
        throw $dupEx;
    }

    $reviewId = (int)$pdo->lastInsertId();

    try {
        $customerName = trim((string)($appt['customer_name'] ?? ''));
        if ($customerName === '') {
            $customerName = 'Müşteri';
        }
        $serviceName = trim((string)($appt['service_name'] ?? ''));
        $reviewService = $serviceName !== '' ? $serviceName : 'randevu deneyimi';
        $reviewBody = $customerName . ', ' . $reviewService . ' için ' . $rating . ' yıldız verdi.';

        $notifStmt = $pdo->prepare(
            "INSERT INTO notifications
             (business_id, appointment_id, type, customer_name, service_name,
              appointment_start, result, is_read, created_at)
             VALUES (?, ?, 'review', ?, ?, ?, 'info', 0, NOW())"
        );
        $notifStmt->execute([
            $businessId,
            $appointmentId,
            $customerName,
            $serviceName !== '' ? $serviceName : null,
            $appt['start_at'] ?? null,
        ]);

        $ownerId = (int)($appt['owner_id'] ?? 0);
        $pushPrefs = wb_push_preferences($pdo, 'business', null, $businessId);
        $channelId = wb_push_channel_id('review', $pushPrefs);
        if ($ownerId > 0 && mobile_table_has_column($pdo, 'mobile_device_tokens', 'token')) {
            $tokenStmt = $pdo->prepare(
                'SELECT DISTINCT token
                   FROM mobile_device_tokens
                  WHERE is_active = 1
                    AND (business_id = ? OR user_id = ?)'
            );
            $tokenStmt->execute([$businessId, $ownerId]);
            $attempted = 0;
            $sent = 0;
            if (!wb_push_enabled($pushPrefs, 'review')) {
                error_log('[mobile/customer/reviews.php push] skipped by prefs review_id=' . $reviewId . ' business_id=' . $businessId);
                $tokensForPush = [];
            } else {
                $tokensForPush = $tokenStmt->fetchAll(PDO::FETCH_COLUMN);
            }
            foreach ($tokensForPush as $rawToken) {
                $token = trim((string)$rawToken);
                if ($token === '') {
                    continue;
                }
                $attempted++;
                $pushResult = wb_fcm_send_to_token(
                    $token,
                    'Yeni yorum aldınız',
                    $reviewBody,
                    [
                        'type' => 'review',
                        'review_id' => (string)$reviewId,
                        'appointment_id' => (string)$appointmentId,
                        'business_id' => (string)$businessId,
                        'rating' => (string)$rating,
                    ],
                    ['android_channel_id' => $channelId]
                );
                if (!empty($pushResult['ok'])) {
                    $sent++;
                } elseif (!empty($pushResult['invalid_token'])) {
                    try {
                        $pdo->prepare(
                            'UPDATE mobile_device_tokens SET is_active = 0, updated_at = NOW() WHERE token = ?'
                        )->execute([$token]);
                    } catch (Throwable $deactivateEx) {
                        error_log('[mobile/customer/reviews.php push deactivate] ' . $deactivateEx->getMessage());
                    }
                }
            }
            error_log('[mobile/customer/reviews.php push] review_id=' . $reviewId . ' business_id=' . $businessId . ' attempted=' . $attempted . ' sent=' . $sent);
        }
    } catch (Throwable $notifyEx) {
        error_log('[mobile/customer/reviews.php notify] ' . $notifyEx->getMessage());
    }

    wb_ok([
        'review' => [
            'id'             => $reviewId,
            'appointment_id' => $appointmentId,
            'business_id'    => $businessId,
            'staff_id'       => $staffId,
            'service_id'     => $serviceId,
            'rating'         => $rating,
            'comment'        => $comment !== '' ? $comment : null,
        ],
        'reviewed'       => true,
        'appointment_id' => (string)$appointmentId,
        'rating'         => $rating,
        'message'        => 'Değerlendirmeniz için teşekkürler.',
    ]);

} catch (Throwable $e) {
    error_log('[mobile/customer/reviews.php] ' . $e->getMessage());
    wb_err('Değerlendirme kaydedilemedi. Lütfen tekrar deneyin.', 500, 'internal_error');
}
