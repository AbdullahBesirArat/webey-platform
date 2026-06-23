<?php
declare(strict_types=1);
/**
 * api/mobile/customer/appointments/deposit-sent.php
 * POST — Müşteri kaporayı işletmenin IBAN'ına gönderdiğini bildirir.
 *
 * Body (JSON):
 *   appointment_id : int (zorunlu)
 *
 * Akış (manuel IBAN kapora):
 *   - appointments.deposit_status = 'customer_marked_sent' yapılır.
 *   - İşletmeye in-app bildirim (notifications tablosu, type 'deposit_sent')
 *     + best-effort FCM push gider.
 *   - Randevu status'u değişmez (pending kalır); işletme onaylayınca approved olur.
 *
 * Mevcut iyzico/online ödeme akışını etkilemez — yalnızca manuel IBAN kapora
 * için kullanılır.
 *
 * Yanıt:
 *   success            : bool
 *   deposit_status     : string
 *   appointment_status : string
 *   message            : string
 */

require_once __DIR__ . '/../../_bootstrap.php';
require_once __DIR__ . '/../../_auth.php';

wb_method('POST');

$session = mobile_auth($pdo, 'customer');
$userId  = (int)$session['user_id'];

$in            = wb_body();
$appointmentId = (int)($in['appointment_id'] ?? 0);

if ($appointmentId <= 0) {
    wb_err('appointment_id zorunlu', 400, 'missing_param');
}

if (!mobile_table_has_column($pdo, 'appointments', 'deposit_status')) {
    wb_err('Kapora takibi servisi şu an kullanılamıyor', 503, 'deposit_unavailable');
}

$hasDepositCols = mobile_table_has_column($pdo, 'appointments', 'deposit_required');

try {
    // ── Müşteri telefonu (kimlik çift-kontrolü için) ───────────────────────────
    $cPhoneStmt = $pdo->prepare("SELECT phone FROM customers WHERE user_id = ? LIMIT 1");
    $cPhoneStmt->execute([$userId]);
    $rawPhone = preg_replace('/\D/', '', (string)($cPhoneStmt->fetchColumn() ?: ''));
    $phone10  = $rawPhone !== '' ? substr($rawPhone, -10) : '';

    // ── Randevuyu çek ──────────────────────────────────────────────────────────
    $depositSelect = $hasDepositCols ? ', a.deposit_required, a.deposit_amount' : '';
    if (mobile_table_has_column($pdo, 'appointments', 'deposit_reference_code')) {
        $depositSelect .= ', a.deposit_reference_code';
    }
    $apptStmt = $pdo->prepare("
        SELECT
            a.id,
            a.status,
            a.start_at,
            a.business_id,
            a.customer_phone,
            a.customer_user_id,
            a.customer_name,
            a.deposit_status {$depositSelect},
            s.name AS service_name,
            b.name AS business_name
        FROM appointments a
        LEFT JOIN services   s ON s.id = a.service_id
        LEFT JOIN businesses b ON b.id = a.business_id
        WHERE a.id = ?
        LIMIT 1
    ");
    $apptStmt->execute([$appointmentId]);
    $appt = $apptStmt->fetch();

    if (!$appt) {
        wb_err('Randevu bulunamadı', 404, 'not_found');
    }

    // ── Yetkilendirme: customer_user_id veya telefon eşleşmesi ─────────────────
    $authorized = ((int)($appt['customer_user_id'] ?? 0) === $userId);
    if (!$authorized && $phone10 !== '') {
        $apptPhone10 = substr(preg_replace('/\D/', '', (string)($appt['customer_phone'] ?? '')), -10);
        if ($apptPhone10 !== '' && $apptPhone10 === $phone10) {
            $authorized = true;
        }
    }
    if (!$authorized) {
        wb_err('Bu randevuya erişim yetkiniz yok', 403, 'forbidden');
    }

    // ── Kapora gereksinimi ─────────────────────────────────────────────────────
    $depositRequired = $hasDepositCols ? (bool)($appt['deposit_required'] ?? false) : true;
    if (!$depositRequired) {
        wb_err('Bu randevu için kapora gerekmemektedir', 422, 'deposit_not_required');
    }

    // ── Durum kontrolü ─────────────────────────────────────────────────────────
    $apptStatus    = strtolower((string)($appt['status'] ?? ''));
    $depositStatus = strtolower((string)($appt['deposit_status'] ?? 'pending'));

    if (in_array($apptStatus, ['cancelled', 'rejected', 'declined', 'no_show'], true)) {
        wb_err('Bu randevu için ödeme bildirimi yapılamaz', 409, 'appointment_not_payable');
    }
    if ($depositStatus === 'paid') {
        wb_err('Kapora ödemeniz zaten onaylanmış', 409, 'already_paid');
    }
    // İdempotent: zaten bildirilmişse tekrar bildirim oluşturma.
    if ($depositStatus === 'customer_marked_sent') {
        wb_ok([
            'success'            => true,
            'deposit_status'     => 'customer_marked_sent',
            'appointment_status' => $apptStatus,
            'message'            => 'Ödeme bildiriminiz zaten işletmeye iletilmişti. İşletme kontrol ettikten sonra randevunuz onaylanacaktır.',
        ]);
    }

    // ── IBAN kontrolü: salon IBAN eklememişse müşteri gönderemez ───────────────
    require_once __DIR__ . '/../../_payment_settings.php';
    $businessId = (int)($appt['business_id'] ?? 0);
    $ps = wb_business_payment_settings($pdo, $businessId);
    if (empty($ps['has_iban'])) {
        wb_err('Salon henüz kapora IBAN bilgisini eklememiş. Lütfen salonla iletişime geçin.', 409, 'iban_missing');
    }

    // ── Durumu güncelle ────────────────────────────────────────────────────────
    $pdo->prepare("
        UPDATE appointments
        SET deposit_status = 'customer_marked_sent', updated_at = NOW()
        WHERE id = ?
    ")->execute([$appointmentId]);

    // ── Audit log (ana akışı kesmez) ───────────────────────────────────────────
    try {
        require_once __DIR__ . '/../../../_appointment_log.php';
        wb_appt_log($pdo, $appointmentId, 'deposit_customer_marked_sent', $depositStatus, 'customer_marked_sent', $userId);
    } catch (Throwable $logEx) {
        error_log('[customer/appointments/deposit-sent.php log] ' . $logEx->getMessage());
    }

    // ── İşletme in-app bildirimi (garanti — notifications tablosu) ──────────────
    try {
        if ($businessId > 0) {
            $pdo->prepare("
                INSERT INTO notifications
                    (business_id, appointment_id, type, customer_name, customer_phone,
                     service_name, appointment_start, result, created_at)
                VALUES (?, ?, 'deposit_sent', ?, ?, ?, ?, 'pending', NOW())
            ")->execute([
                $businessId,
                $appointmentId,
                $appt['customer_name']  ?? null,
                $appt['customer_phone'] ?? null,
                $appt['service_name']   ?? null,
                $appt['start_at']       ?? null,
            ]);
        }
    } catch (Throwable $bizNotifEx) {
        error_log('[customer/appointments/deposit-sent.php biz_notif] ' . $bizNotifEx->getMessage());
    }

    // ── İşletmeye best-effort FCM push (hata ana akışı bozmaz) ──────────────────
    try {
        if ($businessId > 0) {
            require_once __DIR__ . '/../../../_fcm.php';
            require_once __DIR__ . '/../../../_appointment_push.php';

            $ownerStmt = $pdo->prepare('SELECT owner_id FROM businesses WHERE id = ? LIMIT 1');
            $ownerStmt->execute([$businessId]);
            $ownerId = (int)($ownerStmt->fetchColumn() ?: 0);

            $tokenStmt = $pdo->prepare(
                'SELECT DISTINCT token FROM mobile_device_tokens
                  WHERE is_active = 1 AND (business_id = ? OR user_id = ?)'
            );
            $tokenStmt->execute([$businessId, $ownerId]);
            $tokens = $tokenStmt->fetchAll(PDO::FETCH_COLUMN) ?: [];

            $custName = trim((string)($appt['customer_name'] ?? 'Müşteri'));
            $startLabel = (string)($appt['start_at'] ?? '');
            try {
                if ($startLabel !== '') {
                    $startDt = new DateTimeImmutable($startLabel, new DateTimeZone('Europe/Istanbul'));
                    $startLabel = $startDt->format('d.m.Y H:i');
                }
            } catch (Throwable) {
            }
            $pushTitle = 'Yeni randevu bildirimi';
            $pushBody  = $custName
                . ($startLabel !== '' ? ', ' . $startLabel . ' randevusu için' : '')
                . ' kaporayı IBAN\'a gönderdiğini bildirdi. '
                . 'Lütfen hesabınızı kontrol edip ödemeyi onaylayın.';
            $channelId = wb_push_channel_id('appointment', wb_push_preferences($pdo, 'business', null, $businessId));

            $refCode = (string)($appt['deposit_reference_code'] ?? '');
            $depAmount = $appt['deposit_amount'] ?? null;

            foreach ($tokens as $rawToken) {
                $token = trim((string)$rawToken);
                if ($token === '') {
                    continue;
                }
                $res = wb_fcm_send_to_token(
                    $token,
                    $pushTitle,
                    $pushBody,
                    [
                        'type'               => 'deposit_sent',
                        'notification_title' => $pushTitle,
                        'notification_body'  => $pushBody,
                        'appointment_id'     => (string)$appointmentId,
                        'business_id'        => (string)$businessId,
                        'customer_name'      => $custName,
                        'amount'             => $depAmount !== null ? (string)$depAmount : '',
                        'reference_code'     => $refCode,
                        'route'              => '/business/appointments',
                        'channel_id'         => $channelId,
                    ],
                    ['include_notification' => false]
                );
                if (empty($res['ok']) && !empty($res['invalid_token'])) {
                    wb_appt_deactivate_invalid_token($pdo, $token, '[customer/appointments/deposit-sent.php fcm]');
                }
            }
        }
    } catch (Throwable $fcmEx) {
        error_log('[customer/appointments/deposit-sent.php fcm] ' . $fcmEx->getMessage());
    }

    wb_ok([
        'success'            => true,
        'deposit_status'     => 'customer_marked_sent',
        'appointment_status' => $apptStatus,
        'message'            => 'Ödeme bildiriminiz işletmeye iletildi. İşletme ödemeyi kontrol ettikten sonra randevunuz onaylanacaktır.',
    ]);
} catch (Throwable $e) {
    error_log('[customer/appointments/deposit-sent.php] ' . $e->getMessage());
    wb_err('İşlem tamamlanamadı. Lütfen tekrar deneyin.', 500, 'internal_error');
}
