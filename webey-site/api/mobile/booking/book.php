<?php
declare(strict_types=1);
/**
 * api/mobile/booking/book.php
 * POST — randevu oluşturur.
 *
 * Body (JSON):
 *   business_id      : int    (zorunlu)
 *   service_id       : int    (zorunlu)
 *   starts_at        : string (zorunlu) — "YYYY-MM-DD HH:MM" veya "YYYY-MM-DDTHH:MM:SS"
 *   staff_id         : int    (opsiyonel)
 *   duration_minutes : int    (opsiyonel — yoksa services tablosundan)
 *   lock_token       : string (opsiyonel — lock.php'den alınan kilit token)
 *   notes            : string (opsiyonel)
 *   deposit_sent     : bool   (opsiyonel) — manuel IBAN akışı: müşteri "IBAN'a
 *                      parayı attım" dedi. Randevu bu çağrıda oluşur ve
 *                      deposit_status doğrudan 'customer_marked_sent' yazılır;
 *                      işletmeye deposit_sent bildirimi + push gider.
 *                      Kapora gerekli ama salon IBAN'ı yoksa 409 iban_missing
 *                      ile randevu OLUŞTURULMAZ.
 *
 * Faz 5A — Bearer token zorunlu, customer tipi.
 * TODO: Abonelik kontrolü (_subscription_check.php web bağımlılıkları nedeniyle bu fazda atlandı).
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';
require_once __DIR__ . '/_helpers.php';
require_once __DIR__ . '/../../_appointment_log.php';
require_once __DIR__ . '/../../_appointment_push.php';
require_once __DIR__ . '/../../_fcm.php';
require_once __DIR__ . '/../../_user_notifications.php';
require_once __DIR__ . '/../_payment_settings.php';
require_once __DIR__ . '/../_campaigns.php';
require_once __DIR__ . '/../_cancellation.php';

wb_method('POST');

$sess   = mobile_auth($pdo, 'customer');
$userId = $sess['user_id'];

$in = wb_body();

$businessId  = (int)($in['business_id'] ?? 0);
$serviceId   = (int)($in['service_id']  ?? 0);
$startsAtRaw = trim((string)($in['starts_at'] ?? ''));
$staffIdRaw  = isset($in['staff_id']) ? (int)$in['staff_id'] : null;
$staffId     = ($staffIdRaw !== null && $staffIdRaw > 0) ? $staffIdRaw : null;
$durationMin = isset($in['duration_minutes']) ? (int)$in['duration_minutes'] : null;
$lockToken   = trim((string)($in['lock_token'] ?? ''));
$notes       = mb_substr(trim((string)($in['notes'] ?? '')), 0, 500);
$rawDepositSent = $in['deposit_sent'] ?? false;
$depositSent = ($rawDepositSent === true)
    || ($rawDepositSent === 1)
    || ($rawDepositSent === '1')
    || (is_string($rawDepositSent) && strtolower($rawDepositSent) === 'true');
// İstemcinin confirm ekranında gösterdiği aday açıklama kodu (opsiyonel).
// Backend doğrular; geçersiz/çakışan kod yerine kendi kodunu üretir.
$depositRefCandidate = strtoupper(trim((string)($in['deposit_reference_code'] ?? '')));

// ── Temel doğrulama ───────────────────────────────────────────────────────────
if ($businessId < 1) {
    wb_err('business_id zorunludur', 422, 'missing_business_id');
}
if ($serviceId < 1) {
    wb_err('service_id zorunludur', 422, 'missing_service_id');
}
if ($startsAtRaw === '') {
    wb_err('starts_at zorunludur', 422, 'missing_starts_at');
}

$parsed = wb_bk_validate_datetime($startsAtRaw);
if ($parsed === null) {
    wb_err('starts_at geçersiz format (YYYY-MM-DD HH:MM bekleniyor)', 422, 'invalid_starts_at');
}

$dayStr   = $parsed['day_str'];
$startMin = $parsed['start_min'];
$startsAt = $parsed['str'];

$tz = new DateTimeZone('Europe/Istanbul');
if ($parsed['dt'] <= new DateTimeImmutable('now', $tz)) {
    wb_err('Geçmiş bir saate randevu alınamaz', 422, 'past_slot');
}

if ($lockToken !== '' && !preg_match('/^[0-9a-f]{48}$/', $lockToken)) {
    wb_err('lock_token geçersiz format', 422, 'invalid_lock_token');
}

// ── İşletme doğrulama ─────────────────────────────────────────────────────────
$bizStmt = $pdo->prepare('SELECT id, name FROM businesses WHERE id = ? AND status = ? LIMIT 1');
$bizStmt->execute([$businessId, 'active']);
$bizRow = $bizStmt->fetch();
if (!$bizRow) {
    wb_err('İşletme bulunamadı veya aktif değil', 404, 'business_not_found');
}
$bizName = (string)$bizRow['name'];

// Kapora ayarı — kolonlar yoksa (migration çalışmamış) false/null fallback
$bizDepositRequired = false;
$bizDepositAmount   = null;
$bizDepositPercent  = 25;
if (mobile_table_has_column($pdo, 'businesses', 'deposit_required')) {
    $depHasAmt  = mobile_table_has_column($pdo, 'businesses', 'deposit_amount');
    $depBizStmt = $pdo->prepare(
        'SELECT deposit_required' . ($depHasAmt ? ', deposit_amount' : '')
        . ' FROM businesses WHERE id = ? LIMIT 1'
    );
    $depBizStmt->execute([$businessId]);
    $depBizRow = $depBizStmt->fetch();
    if ($depBizRow) {
        $bizDepositRequired = (bool)$depBizRow['deposit_required'];
        $bizDepositAmount   = $depHasAmt && $depBizRow['deposit_amount'] !== null
            ? (float)$depBizRow['deposit_amount']
            : null;
    }
}
$hasApptDepositCol = mobile_table_has_column($pdo, 'appointments', 'deposit_required');
$hasApptAmountCol  = mobile_table_has_column($pdo, 'appointments', 'deposit_amount');

// ── Hizmet doğrulama & süre ───────────────────────────────────────────────────
$svcStmt = $pdo->prepare(
    'SELECT id, name, duration_min, price FROM services WHERE id = ? AND business_id = ? LIMIT 1'
);
$svcStmt->execute([$serviceId, $businessId]);
$svcRow = $svcStmt->fetch();
if (!$svcRow) {
    wb_err('Hizmet bulunamadı', 404, 'service_not_found');
}
$serviceName = (string)$svcRow['name'];
$servicePrice = $svcRow['price'] !== null ? (float)$svcRow['price'] : 0.0;

if (!$durationMin || $durationMin < 1) {
    $durationMin = (int)$svcRow['duration_min'];
}
if ($durationMin < 1) {
    wb_err('Hizmet süresi geçersiz', 422, 'invalid_duration');
}

// ── Kampanya motoru (sunucu otoritesi) ───────────────────────────────────────
// İstemci aday campaign_id gönderse bile yok sayılır; seçilen hizmet + slot için
// en avantajlı geçerli kampanya sunucuda hesaplanır. İndirimli fiyat kapora ve
// snapshot için temel alınır. Kampanya yoksa orijinal fiyat kullanılır.
$campaignSnapshot = null;     // appointments snapshot için
$campaignResponse = null;     // yanıt için
$priceBase = $servicePrice;   // kapora hesabının baz aldığı (indirimli) fiyat
try {
    if ($servicePrice > 0) {
        $cq = wb_campaign_quote_for_slot($pdo, $businessId, $serviceId, $servicePrice, $parsed['dt']);
        if ($cq['campaign'] !== null) {
            $campaignSnapshot = $cq['campaign'];
            $priceBase = (float)$cq['campaign']['final_price'];
            $campaignResponse = $cq['campaign'];
        }
    }
} catch (Throwable $cmpEx) {
    error_log('[mobile/booking/book.php campaign] ' . $cmpEx->getMessage());
}

// Kapora politikasi: rate_pct > 0 yuzdelik, rate_pct = 0 + businesses.deposit_amount sabit tutar.
try {
    if (mobile_table_has_column($pdo, 'deposit_policies', 'rate_pct')) {
        $policyStmt = $pdo->prepare('SELECT rate_pct FROM deposit_policies WHERE business_id = ? LIMIT 1');
        $policyStmt->execute([$businessId]);
        $policyRateRaw = $policyStmt->fetchColumn();
        $policyRate = $policyRateRaw !== false ? (int)$policyRateRaw : 25;
        if ($policyRate > 0) {
            if (!in_array($policyRate, [25, 50, 75, 100], true)) {
                $policyRate = 25;
            }
            $bizDepositRequired = true;
            $bizDepositPercent = $policyRate;
            $bizDepositAmount = round($priceBase * $bizDepositPercent / 100);
        } elseif ($bizDepositRequired && $bizDepositAmount !== null && $bizDepositAmount > 0) {
            $bizDepositRequired = true;
            $bizDepositAmount = round($bizDepositAmount, 2);
        } else {
            $bizDepositRequired = false;
            $bizDepositAmount = null;
        }
    } elseif ($bizDepositRequired && $bizDepositAmount === null && $priceBase > 0) {
        $bizDepositAmount = round($priceBase * $bizDepositPercent / 100);
    }
} catch (Throwable $policyEx) {
    error_log('[mobile/booking/book.php deposit_policy] ' . $policyEx->getMessage());
}

// Kapora, indirim sonrası final tutarı (priceBase) AŞAMAZ. Özellikle sabit
// kapora final tutardan büyükse final tutara sınırlandırılır; salonda kalan
// asla negatif olmaz. (Senaryo D)
if ($bizDepositRequired && $bizDepositAmount !== null) {
    $bizDepositAmount = round(max(0.0, min((float)$bizDepositAmount, $priceBase)), 2);
}
// Salonda kalan = max(0, final tutar - kapora). Tek otoriter kaynak.
$remainingAtSalon = $bizDepositRequired && $bizDepositAmount !== null
    ? round(max(0.0, $priceBase - $bizDepositAmount), 2)
    : round($priceBase, 2);

// ── Salon IBAN ayarları (manuel kapora) ──────────────────────────────────────
// Kapora gerekiyorsa randevu OLUŞMADAN ÖNCE kontrol edilir: müşteri "IBAN'a
// parayı attım" diyorsa salonun IBAN'ı tanımlı olmak zorunda; yoksa randevu
// oluşturulmaz (müşteri para gönderecek hesap yok demektir).
$paymentSettings = null;
if ($bizDepositRequired) {
    $paymentSettings = wb_business_payment_settings($pdo, $businessId);
    if ($depositSent && empty($paymentSettings['has_iban'])) {
        wb_err(
            'Salonun kapora ödeme bilgileri eksik. Lütfen daha sonra tekrar deneyin.',
            409,
            'iban_missing'
        );
    }
}
// Kapora gerekmiyorsa bayrağın anlamı yok.
if (!$bizDepositRequired) {
    $depositSent = false;
}

$endMin = $startMin + $durationMin;
if ($endMin > 1440) {
    wb_err('Randevu gece yarısını geçemez', 422, 'midnight_overflow');
}

$endH   = intdiv($endMin, 60);
$endM   = $endMin % 60;
$endsAt = sprintf('%s %02d:%02d:00', $dayStr, $endH, $endM);

// ── Personel doğrulama (opsiyonel) ───────────────────────────────────────────
if ($staffId !== null) {
    $stfStmt = $pdo->prepare(
        'SELECT id FROM staff WHERE id = ? AND business_id = ? AND is_active = 1 LIMIT 1'
    );
    $stfStmt->execute([$staffId, $businessId]);
    if (!$stfStmt->fetch()) {
        wb_err('Personel bulunamadı', 404, 'staff_not_found');
    }
}

// ── Müşteri adı ve iletişim bilgisi (istemciden alınmaz — DB'den çekilir) ─────
$custStmt = $pdo->prepare(
    "SELECT u.name AS user_name, u.email,
            c.first_name, c.last_name, c.phone
     FROM users u
     LEFT JOIN customers c ON c.user_id = u.id
     WHERE u.id = ? LIMIT 1"
);
$custStmt->execute([$userId]);
$custRow = $custStmt->fetch();
if (!$custRow) {
    wb_err('Müşteri bilgisi alınamadı', 500, 'customer_not_found');
}

$firstName    = trim((string)($custRow['first_name'] ?? ''));
$lastName     = trim((string)($custRow['last_name']  ?? ''));
$customerName = trim($firstName . ' ' . $lastName);
if ($customerName === '') {
    $customerName = trim((string)($custRow['user_name'] ?? ''));
}
if ($customerName === '') {
    $customerName = 'Müşteri';
}
$customerPhone = trim((string)($custRow['phone'] ?? ''));
$customerEmail = trim((string)($custRow['email'] ?? ''));

// ── Transaction (TOCTOU koruması) ─────────────────────────────────────────────
$appointmentId = null;
$depositReferenceCode = null;

try {
    $pdo->beginTransaction();

    // 1. Süresi dolan kilitleri temizle
    $pdo->prepare('DELETE FROM slot_locks WHERE expires_at < NOW()')->execute();

    // 2. Randevu çakışması — FOR UPDATE ile eş zamanlı INSERT'e karşı kilit
    if ($staffId !== null) {
        $apptSql    = "SELECT id FROM appointments
                       WHERE business_id = ? AND staff_id = ?
                         AND status NOT IN ('cancelled','no_show','rejected','declined','cancellation_requested')
                         AND start_at < ? AND end_at > ?
                       FOR UPDATE";
        $apptParams = [$businessId, $staffId, $endsAt, $startsAt];
    } else {
        $apptSql    = "SELECT id FROM appointments
                       WHERE business_id = ?
                         AND status NOT IN ('cancelled','no_show','rejected','declined','cancellation_requested')
                         AND start_at < ? AND end_at > ?
                       FOR UPDATE";
        $apptParams = [$businessId, $endsAt, $startsAt];
    }
    $apptStmt = $pdo->prepare($apptSql);
    $apptStmt->execute($apptParams);
    if ($apptStmt->fetch()) {
        $pdo->rollBack();
        wb_err('Bu saat zaten dolu', 409, 'conflict');
    }

    // 3a. lock_token varsa doğrula
    if ($lockToken !== '') {
        $ltStmt = $pdo->prepare(
            'SELECT id, start_min, duration_min FROM slot_locks
             WHERE lock_token = ? AND business_id = ? AND day_str = ? AND expires_at >= NOW()
             LIMIT 1 FOR UPDATE'
        );
        $ltStmt->execute([$lockToken, $businessId, $dayStr]);
        $ltRow = $ltStmt->fetch();

        if (!$ltRow) {
            $pdo->rollBack();
            wb_err('Kilit süresi dolmuş veya geçersiz, lütfen slotu yeniden kilitleyin', 409, 'lock_expired');
        }

        $ltStart = (int)$ltRow['start_min'];
        $ltEnd   = $ltStart + (int)$ltRow['duration_min'];
        if ($ltStart !== $startMin || $ltEnd !== $endMin) {
            $pdo->rollBack();
            wb_err('Kilit token bu slot için geçerli değil', 409, 'lock_mismatch');
        }
    } else {
        // 3b. lock_token yok — çalışma saatlerini ve kilit çakışmalarını kontrol et
        $workingRanges = wb_bk_get_working_ranges($pdo, $businessId, $staffId, $dayStr);
        $inWorkingHours = false;
        foreach ($workingRanges as $wr) {
            if ($wr['start'] <= $startMin && $wr['end'] >= $endMin) {
                $inWorkingHours = true;
                break;
            }
        }
        if (!$inWorkingHours) {
            $pdo->rollBack();
            wb_err('Seçilen saat işletmenin çalışma saatleri dışında', 422, 'outside_working_hours');
        }

        $lockRanges = wb_bk_get_lock_ranges($pdo, $businessId, $staffId, $dayStr);
        if (wb_bk_ranges_overlap($lockRanges, $startMin, $endMin)) {
            $pdo->rollBack();
            wb_err('Bu saat şu an başka biri tarafından seçildi, lütfen daha sonra tekrar deneyin', 409, 'locked');
        }
    }

    // 4. Randevuyu oluştur (deposit snapshot: kolonlar varsa alınır, yoksa atlanır)
    // $apptCols / $apptPh tamamen iç flag'lerden üretiliyor — kullanıcı girdisi yok.
    $apptCols = 'business_id, staff_id, service_id, customer_user_id, customer_name,
                 customer_phone, customer_email, start_at, end_at, status, booking_source, notes';
    $apptPh   = "?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', 'app', ?";
    $apptArgs = [
        $businessId, $staffId, $serviceId, $userId, $customerName,
        $customerPhone ?: null, $customerEmail ?: null,
        $startsAt, $endsAt,
        $notes !== '' ? $notes : null,
    ];
    if ($hasApptDepositCol) {
        $apptCols .= ', deposit_required';
        $apptPh   .= ', ?';
        $apptArgs[] = $bizDepositRequired ? 1 : 0;
    }
    if ($hasApptAmountCol) {
        $apptCols .= ', deposit_amount';
        $apptPh   .= ', ?';
        $apptArgs[] = $bizDepositAmount;
    }
    // İptal politikası snapshot — booking anındaki kuralı sabitler (sonradan
    // politika değişse bile bu randevunun iptal/no-show kuralı değişmez).
    if (mobile_table_has_column($pdo, 'appointments', 'free_cancel_hours_snapshot')) {
        $cancelSnap = wb_cancellation_snapshot_values(wb_cancellation_policy($pdo, $businessId));
        $apptCols .= ', free_cancel_hours_snapshot, late_cancel_fee_pct_snapshot, no_show_refund_pct_snapshot';
        $apptPh   .= ', ?, ?, ?';
        $apptArgs[] = $cancelSnap['free_hours'];
        $apptArgs[] = $cancelSnap['late_fee_pct'];
        $apptArgs[] = $cancelSnap['no_show_refund_pct'];
    }
    // Kampanya + fiyat snapshot — kolonlar varsa yazılır. Kampanya sonradan
    // kapatılsa bile bu randevunun indirim/fiyat kaydı değişmez (raporlama).
    if (wb_campaign_appt_cols_ready($pdo)) {
        $apptCols .= ', campaign_id, campaign_title_snapshot, campaign_discount_kind,
                      campaign_discount_value, campaign_discount_amount, original_amount, final_amount';
        $apptPh   .= ', ?, ?, ?, ?, ?, ?, ?';
        $apptArgs[] = $campaignSnapshot !== null ? (int)$campaignSnapshot['id'] : null;
        $apptArgs[] = $campaignSnapshot !== null ? (string)$campaignSnapshot['title'] : null;
        $apptArgs[] = $campaignSnapshot !== null ? (string)$campaignSnapshot['discount_kind'] : null;
        $apptArgs[] = $campaignSnapshot !== null ? (float)$campaignSnapshot['discount_value'] : null;
        $apptArgs[] = $campaignSnapshot !== null ? (float)$campaignSnapshot['discount_amount'] : 0.0;
        $apptArgs[] = round($servicePrice, 2);
        $apptArgs[] = round($priceBase, 2);
    }
    $pdo->prepare(
        "INSERT INTO appointments ({$apptCols}, created_at, updated_at)
         VALUES ({$apptPh}, NOW(), NOW())"
    )->execute($apptArgs);

    $appointmentId = (int)$pdo->lastInsertId();

    // Manuel (IBAN) kapora takibi: müşteri "IBAN'a parayı attım" dediyse
    // randevu doğrudan 'customer_marked_sent' ile açılır (yeni akış);
    // eski istemciler bayrak göndermezse 'pending' yazılır.
    // Açıklama kodu benzersiz üretilir: WEBEY-{ISLETME}-{RASTGELE}.
    if ($bizDepositRequired
        && mobile_table_has_column($pdo, 'appointments', 'deposit_status')) {
        $depositReferenceCode = wb_generate_unique_deposit_reference(
            $pdo, $bizName, $depositRefCandidate, $appointmentId
        );
        $pdo->prepare(
            'UPDATE appointments
                SET deposit_status = ?, deposit_reference_code = ?
              WHERE id = ?'
        )->execute([
            $depositSent ? 'customer_marked_sent' : 'pending',
            $depositReferenceCode,
            $appointmentId,
        ]);
    }

    // 5. Kilidi sil (varsa)
    if ($lockToken !== '') {
        $pdo->prepare('DELETE FROM slot_locks WHERE lock_token = ?')->execute([$lockToken]);
    }

    $pdo->commit();

} catch (Throwable $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    error_log('[mobile/booking/book.php] ' . $e->getMessage());
    wb_err('Randevu oluşturulamadı, lütfen tekrar deneyin', 500, 'internal_error');
}

// ── Commit sonrası: audit log + bildirimler (ana akışı kesmez) ────────────────
try {
    wb_appt_log($pdo, $appointmentId, 'created', null, 'pending', $userId);
    if ($depositSent) {
        wb_appt_log(
            $pdo, $appointmentId, 'deposit_customer_marked_sent',
            null, 'customer_marked_sent', $userId
        );
    }
} catch (Throwable $logEx) {
    error_log('[mobile/booking/book.php audit_log] ' . $logEx->getMessage());
}

try {
    $notif = wbUserNotifFromStatus('pending', $bizName, $startsAt, $serviceName);
    wbInsertUserNotification(
        $pdo, $userId, $appointmentId,
        $notif['type'], $notif['title'], $notif['message'],
        $bizName
    );
} catch (Throwable $notifEx) {
    error_log('[mobile/booking/book.php user_notif] ' . $notifEx->getMessage());
}

try {
    // Yeni akışta (deposit_sent) randevu bildirimi doğrudan 'deposit_sent'
    // tipiyle açılır: işletme listede "IBAN ödeme bildirimi" görür ve
    // "Para geldi" onayına yönlenir. Eski akışta 'booking' tipi korunur.
    $pdo->prepare(
        "INSERT INTO notifications
             (business_id, appointment_id, type, customer_name, customer_phone,
              service_name, appointment_start, result, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', NOW())"
    )->execute([
        $businessId,
        $appointmentId,
        $depositSent ? 'deposit_sent' : 'booking',
        $customerName,
        $customerPhone ?: null,
        $serviceName,
        $startsAt,
    ]);
} catch (Throwable $bizNotifEx) {
    error_log('[mobile/booking/book.php biz_notif] ' . $bizNotifEx->getMessage());
}

try {
    $ownerStmt = $pdo->prepare('SELECT owner_id FROM businesses WHERE id = ? LIMIT 1');
    $ownerStmt->execute([$businessId]);
    $ownerId = (int)($ownerStmt->fetchColumn() ?: 0);

    $tokenStmt = $pdo->prepare(
        'SELECT DISTINCT token
           FROM mobile_device_tokens
          WHERE is_active = 1
            AND (business_id = ? OR user_id = ?)'
    );
    $tokenStmt->execute([$businessId, $ownerId]);
    $tokens = $tokenStmt->fetchAll(PDO::FETCH_COLUMN);
    if ($depositSent) {
        $startLabel = $startsAt;
        try {
            $startDt = new DateTimeImmutable($startsAt, new DateTimeZone('Europe/Istanbul'));
            $startLabel = $startDt->format('d.m.Y H:i');
        } catch (Throwable) {
        }
        $pushTitle = 'Yeni randevu bildirimi';
        $pushBody = $customerName . ', ' . $startLabel
            . ' randevusu için kaporayı IBAN\'a gönderdiğini bildirdi. '
            . 'Lütfen hesabınızı kontrol edip ödemeyi onaylayın.';
    } else {
        $pushTitle = 'Yeni randevunuz var';
        $pushBody = wb_appt_business_push_body($customerName, $serviceName, $startsAt);
    }
    $approveToken = wb_appt_action_token($appointmentId, $businessId, 'approve');
    $rejectToken = wb_appt_action_token($appointmentId, $businessId, 'reject');
    $pushPrefs = wb_push_preferences($pdo, 'business', null, $businessId);
    $channelId = wb_push_channel_id('appointment', $pushPrefs);
    if (!wb_push_enabled($pushPrefs, 'appointment')) {
        error_log('[mobile/booking/book.php fcm] skipped by prefs appointment_id=' . $appointmentId . ' business_id=' . $businessId);
        $tokens = [];
    }

    // Diagnostik log — gizli token/secret değerleri yazılmaz, sadece varlık durumu.
    error_log(
        '[mobile/booking/book.php fcm] appointment_id=' . $appointmentId
        . ' tokens_in_db=' . count($tokens)
        . ' title_nonempty=' . ($pushTitle !== '' ? '1' : '0')
        . ' body_nonempty=' . ($pushBody !== '' ? '1' : '0')
        . ' approve_token_present=' . ($approveToken !== '' ? '1' : '0')
        . ' reject_token_present=' . ($rejectToken !== '' ? '1' : '0')
    );

    $attempted = 0;
    $sent = 0;
    foreach ($tokens as $rawToken) {
        $token = trim((string)$rawToken);
        if ($token === '') {
            continue;
        }

        $attempted++;
        $result = wb_fcm_send_to_token(
            $token,
            $pushTitle,
            $pushBody,
            [
                'type' => $depositSent ? 'deposit_sent' : 'booking',
                'notification_title' => $pushTitle,
                'notification_body' => $pushBody,
                'appointment_id' => (string)$appointmentId,
                'business_id' => (string)$businessId,
                'service_name' => $serviceName,
                'customer_name' => $customerName,
                'appointment_start' => $startsAt,
                'amount' => $bizDepositAmount !== null ? (string)$bizDepositAmount : '',
                'reference_code' => (string)($depositReferenceCode ?? ''),
                'route' => '/business/appointments',
                'channel_id' => $channelId,
                'approve_token' => $approveToken,
                'reject_token' => $rejectToken,
                'action_endpoint' => '/api/mobile/business/appointment-action.php',
            ],
            ['include_notification' => false]
        );

        if (!empty($result['ok'])) {
            $sent++;
            continue;
        }

        error_log(
            '[mobile/booking/book.php fcm] send failed appointment_id=' . $appointmentId
            . ' business_id=' . $businessId
            . ' status=' . (int)($result['status'] ?? 0)
            . ' error=' . (string)($result['error'] ?? 'unknown')
        );

        if (!empty($result['invalid_token'])) {
            $pdo->prepare(
                'UPDATE mobile_device_tokens
                    SET is_active = 0, updated_at = NOW()
                  WHERE token = ?'
            )->execute([$token]);
        }
    }

    error_log(
        '[mobile/booking/book.php fcm] attempted=' . $attempted
        . ' sent=' . $sent
        . ' business_id=' . $businessId
        . ' appointment_id=' . $appointmentId
    );
} catch (Throwable $fcmEx) {
    error_log('[mobile/booking/book.php fcm] ' . $fcmEx->getMessage());
}

// ── Kapora bilgisi (IBAN talimatı) — kapora gerekiyorsa ──────────────────────
$depositBlock = [
    'required'       => $bizDepositRequired,
    'mode'           => $bizDepositRequired ? 'manual_iban' : null,
    'percent'        => $bizDepositRequired ? $bizDepositPercent : null,
    'amount'         => $bizDepositAmount,
    'remaining_amount' => $remainingAtSalon,
    'status'         => $bizDepositRequired
        ? ($depositSent ? 'customer_marked_sent' : 'pending')
        : null,
    'reference_code' => $bizDepositRequired
        ? ($depositReferenceCode ?? wb_deposit_reference_code($appointmentId))
        : null,
    'paid_at'        => null,
    'awaiting_iban'  => false,
    'iban'           => null,
    'iban_formatted' => null,
    'account_holder' => null,
    'bank_name'      => null,
    'instructions'   => null,
    'payment'        => null,
];
if ($bizDepositRequired) {
    $ps = $paymentSettings ?? wb_business_payment_settings($pdo, $businessId);
    $depositBlock['awaiting_iban'] = !$ps['has_iban'];
    $depositBlock['iban'] = $ps['iban'];
    $depositBlock['iban_formatted'] = $ps['iban_formatted'];
    $depositBlock['account_holder'] = $ps['account_holder'];
    $depositBlock['bank_name'] = $ps['bank_name'];
    $depositBlock['instructions'] = $ps['has_iban']
        ? $ps['instructions']
        : 'Salon kapora odeme bilgilerini henuz eklememis.';
    $depositBlock['payment'] = [
        'deposit_enabled' => $ps['deposit_enabled'],
        'has_iban'        => $ps['has_iban'],
        'iban'            => $ps['iban'],
        'iban_formatted'  => $ps['iban_formatted'],
        'account_holder'  => $ps['account_holder'],
        'bank_name'       => $ps['bank_name'],
        'instructions'    => $ps['instructions'],
    ];
}

wb_ok([
    'appointment' => [
        'id'               => (string)$appointmentId,
        'status'           => 'pending',
        'starts_at'        => $startsAt,
        'ends_at'          => $endsAt,
        'business_id'      => $businessId,
        'service_id'       => $serviceId,
        'staff_id'         => $staffId,
        'deposit_required' => $bizDepositRequired,
        'deposit_amount'   => $bizDepositAmount,
        'deposit'          => $depositBlock,
        'original_amount'  => round($servicePrice, 2),
        'final_amount'     => round($priceBase, 2),
        'remaining_amount' => $remainingAtSalon,
        'campaign'         => $campaignResponse,
    ],
]);
