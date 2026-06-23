<?php
declare(strict_types=1);
/**
 * api/appointments/book.php
 * POST JSON: { businessId, staffId, serviceId, dayStr, startMin, durationMin,
 *              customer:{uid,name,phoneE164}, status, source, notes }
 * PUBLIC — profile.js persistBookingAndGo() tarafından kullanılır
 * Döner: { ok:true, data:{ id, rid } }
 */

require_once __DIR__ . '/../_public_bootstrap.php';
require_once __DIR__ . '/../_user_notifications.php';
wb_method('POST');

// ── IP Tabanlı Rate Limiting: 1 dakikada 10 randevu denemesi ─────────────────
$ip      = trim(explode(',', $_SERVER['HTTP_X_FORWARDED_FOR'] ?? $_SERVER['REMOTE_ADDR'] ?? '0.0.0.0')[0]);
$rateKey = 'book:' . md5($ip);
$rateWindow = 60;
$rateMax    = 10;

try {
    $pdo->prepare('DELETE FROM api_rate_limits WHERE cache_key = ? AND expires_at < NOW()')
        ->execute([$rateKey]);
    $rStmt = $pdo->prepare('SELECT hits FROM api_rate_limits WHERE cache_key = ? LIMIT 1');
    $rStmt->execute([$rateKey]);
    $hits = (int)($rStmt->fetchColumn() ?: 0);
    if ($hits >= $rateMax) {
        wb_err('Çok fazla istek gönderildi. Lütfen 1 dakika bekleyin.', 429, 'rate_limited');
    }
    if ($hits === 0) {
        $pdo->prepare('INSERT INTO api_rate_limits (cache_key, hits, expires_at) VALUES (?, 1, DATE_ADD(NOW(), INTERVAL ? SECOND))')
            ->execute([$rateKey, $rateWindow]);
    } else {
        $pdo->prepare('UPDATE api_rate_limits SET hits = hits + 1 WHERE cache_key = ?')
            ->execute([$rateKey]);
    }
} catch (Throwable) { /* Tablo yoksa devam et */ }
// ─────────────────────────────────────────────────────────────────────────────


$data = wb_body();
if (!is_array($data)) { wb_err('Geçersiz JSON', 400); }

$businessId   = (int)($data['businessId']  ?? 0);
$staffIdRaw   = trim($data['staffId']      ?? 'any');
$serviceIdRaw = trim($data['serviceId']    ?? '');
$dayStr       = trim($data['dayStr']       ?? '');
$startMin     = (int)($data['startMin']    ?? -1);
$durationMin  = (int)($data['durationMin'] ?? 0);
$statusIn     = trim($data['status']       ?? 'pending');
$sourceIn     = trim($data['source']       ?? 'web');
$notes        = trim($data['notes']        ?? '');
// Müşterinin slot seçiminde aldığı kilit token'ı (opsiyonel ama önerilir)
$lockToken    = trim($data['lockToken']    ?? '');

$customer  = is_array($data['customer'] ?? null) ? $data['customer'] : [];
$custName  = trim($customer['name']      ?? '');
$custPhone = trim($customer['phoneE164'] ?? $customer['phone'] ?? '');
$custEmail = trim($customer['email'] ?? '');
if ($custEmail && !filter_var($custEmail, FILTER_VALIDATE_EMAIL)) $custEmail = '';

// Validasyon
if (!$businessId || !$dayStr || $startMin < 0 || $durationMin <= 0) {
    wb_err('businessId, dayStr, startMin, durationMin zorunlu', 400);
}
if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $dayStr)) {
    wb_err('dayStr YYYY-MM-DD formatında olmalı', 400);
}
if ($custName === '') {
    wb_err('Müşteri adı zorunlu', 400);
}

function wb_book_time_to_minutes(string $hhmm): int {
    [$h, $m] = array_map('intval', explode(':', $hhmm));
    return ($h * 60) + $m;
}

function wb_book_day_key(string $date): string {
    $map = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];
    $idx = (int)(new DateTimeImmutable($date, new DateTimeZone('Europe/Istanbul')))->format('w');
    return $map[$idx] ?? 'sun';
}

function wb_book_extract_ranges(array $rows): array {
    $ranges = [];
    foreach ($rows as $row) {
        if ((int)($row['is_open'] ?? 0) !== 1) {
            continue;
        }
        $open  = substr((string)($row['open_time'] ?? ''), 0, 5);
        $close = substr((string)($row['close_time'] ?? ''), 0, 5);
        if (!preg_match('/^\d{2}:\d{2}$/', $open) || !preg_match('/^\d{2}:\d{2}$/', $close)) {
            continue;
        }
        $startMin = wb_book_time_to_minutes($open);
        $endMin   = wb_book_time_to_minutes($close);
        if ($endMin > $startMin) {
            $ranges[] = ['start' => $startMin, 'end' => $endMin];
        }
    }
    return $ranges;
}

// ── Abonelik kontrolü: işletme sahibinin aboneliği aktif mi? ──────────────────
require_once __DIR__ . '/../_subscription_check.php';
$subStatus = getBusinessSubscriptionStatus($pdo, $businessId);
if (!$subStatus['active']) {
    wb_err('Bu işletme şu anda randevu kabul edemiyor.', 403, 'subscription_expired');
}
// ─────────────────────────────────────────────────────────────────────────────

// startMin → datetime
$startH   = (int)floor($startMin / 60);
$startM   = $startMin % 60;
$startStr = sprintf('%s %02d:%02d:00', $dayStr, $startH, $startM);
$endMin   = $startMin + $durationMin;
$endH     = (int)floor($endMin / 60);
$endM     = $endMin % 60;
$endStr   = sprintf('%s %02d:%02d:00', $dayStr, $endH, $endM);

$tz            = new DateTimeZone('Europe/Istanbul');
$startDateTime = DateTimeImmutable::createFromFormat('Y-m-d H:i:s', $startStr, $tz);
$endDateTime   = DateTimeImmutable::createFromFormat('Y-m-d H:i:s', $endStr, $tz);
$nowDateTime   = new DateTimeImmutable('now', $tz);
if (!$startDateTime || !$endDateTime || $endDateTime <= $startDateTime) {
    wb_err('Geçersiz tarih veya saat aralığı', 400, 'invalid_datetime');
}
if ($startDateTime < $nowDateTime) {
    wb_err('Geçmiş zamana randevu oluşturulamaz.', 400, 'past_time');
}

// Personel
$staffId = null;
if ($staffIdRaw && $staffIdRaw !== 'any' && is_numeric($staffIdRaw)) {
    $staffId = (int)$staffIdRaw;
}

// Servis ID
$serviceId = null;
if (is_numeric($serviceIdRaw) && (int)$serviceIdRaw > 0) {
    $serviceId = (int)$serviceIdRaw;
} elseif ($serviceIdRaw !== '' && $serviceIdRaw !== 'general') {
    $svcStmt = $pdo->prepare("SELECT id FROM services WHERE business_id = ? AND (name = ? OR LOWER(REPLACE(name,' ','-')) = ?) LIMIT 1");
    $svcStmt->execute([$businessId, $serviceIdRaw, strtolower($serviceIdRaw)]);
    $svcRow = $svcStmt->fetch();
    if ($svcRow) $serviceId = (int)$svcRow['id'];
}

// BUG FIX 1: 'confirmed' appointments.status enum'unda yok — DB strict mode'da
// Admin session'ı varsa istediği status'u kullanabilir (approved dahil).
// Misafir/müşteri sadece 'pending' ile başlayabilir.
$isAdminSession = !empty($_SESSION['user_id']) && !empty($_SESSION['business_id']);
$allowedStatuses = ['pending', 'approved', 'cancelled', 'no_show', 'completed', 'rejected', 'declined', 'cancellation_requested'];
if ($isAdminSession && in_array($statusIn, $allowedStatuses, true)) {
    $finalStatus = $statusIn;
} else {
    $finalStatus = 'pending';
}
$isAdminQuickBooking = $isAdminSession && $sourceIn === 'admin';

try {
    $pdo->beginTransaction();

    // Suresi dolan kilitleri temizle
    try { $pdo->prepare('DELETE FROM slot_locks WHERE expires_at < NOW()')->execute(); } catch (Throwable) {}

    // Kilit dogrulama
    $lockVerified = false;
    if ($lockToken !== '') {
        try {
            $lkStmt = $pdo->prepare('SELECT id FROM slot_locks WHERE lock_token = ? AND business_id = ? AND day_str = ? AND start_min = ? AND expires_at >= NOW() LIMIT 1');
            $lkStmt->execute([$lockToken, $businessId, $dayStr, $startMin]);
            $lockVerified = (bool)$lkStmt->fetch();
        } catch (Throwable) {}
    }

    if (!$lockVerified) {
        $dayKey = wb_book_day_key($dayStr);

        $bizHoursStmt = $pdo->prepare('SELECT is_open, open_time, close_time FROM business_hours WHERE business_id = ? AND day = ?');
        $bizHoursStmt->execute([$businessId, $dayKey]);
        $bizRanges = wb_book_extract_ranges($bizHoursStmt->fetchAll());

        if (!$bizRanges) {
            $pdo->rollBack();
            wb_err('Seçilen gün ve saatte dükkan kapalı olduğu için randevu oluşturulamaz.', 400, 'outside_working_hours');
        }

        $effectiveRanges = $bizRanges;
        if ($staffId) {
            $staffHoursStmt = $pdo->prepare('SELECT is_open, open_time, close_time FROM staff_hours WHERE business_id = ? AND staff_id = ? AND day = ?');
            $staffHoursStmt->execute([$businessId, $staffId, $dayKey]);
            $staffRows = $staffHoursStmt->fetchAll();
            if ($staffRows) {
                $effectiveRanges = wb_book_extract_ranges($staffRows);
            }
        }

        if (!$effectiveRanges) {
            $pdo->rollBack();
            wb_err('Seçilen gün ve saatte personel kapalı olduğu için randevu oluşturulamaz.', 400, 'outside_working_hours');
        }

        $insideWorkingHours = false;
        foreach ($effectiveRanges as $range) {
            if ($startMin >= $range['start'] && $endMin <= $range['end']) {
                $insideWorkingHours = true;
                break;
            }
        }
        if (!$insideWorkingHours) {
            $pdo->rollBack();
            wb_err('Seçilen saat aralığı çalışma saatleri dışında olduğu için randevu oluşturulamaz.', 400, 'outside_working_hours');
        }

        // BUG FIX 3 (TOCTOU): SELECT ... FOR UPDATE ile satırı kilitle.
        // Kilit olmadan iki eş zamanlı istek aynı boş slotu görüp çift randevu
        // oluşturabiliyordu. FOR UPDATE, transaction boyunca diğer işlemleri bloklar.
        //
        // BUG FIX 4: staffId = null olduğunda çakışma kontrolü tamamen atlanıyordu.
        // "Herhangi personel" randevuları da işletme bazlı kontrol edilmeli.
        if ($staffId) {
            // Belirli personel için çakışma kontrolü
            $cfStmt = $pdo->prepare("
                SELECT id, status, customer_name FROM appointments
                WHERE business_id = ?
                  AND staff_id = ?
                  AND status NOT IN ('cancelled','no_show','rejected','declined','cancellation_requested')
                  AND start_at < ?
                  AND end_at   > ?
                LIMIT 1
                FOR UPDATE
            ");
            $cfStmt->execute([$businessId, $staffId, $endStr, $startStr]);
        } else {
            // BUG FIX 4: staffId seçilmemişse işletme geneli çakışma kontrolü.
            // Tüm aktif personellerin o saatte müsait olup olmadığını kontrol et.
            $cfStmt = $pdo->prepare("
                SELECT a.id, a.status, a.customer_name FROM appointments a
                JOIN staff s ON s.id = a.staff_id AND s.business_id = ? AND s.is_active = 1
                WHERE a.business_id = ?
                  AND a.status NOT IN ('cancelled','no_show','rejected','declined','cancellation_requested')
                  AND a.start_at < ?
                  AND a.end_at   > ?
                LIMIT 1
                FOR UPDATE
            ");
            $cfStmt->execute([$businessId, $businessId, $endStr, $startStr]);
        }

        $conflictRow = $cfStmt->fetch();
        if ($conflictRow) {
            $pdo->rollBack();
            $isBlockedConflict = (($conflictRow['status'] ?? '') === 'blocked') || (($conflictRow['customer_name'] ?? '') === '[DOLU]');
            if ($isBlockedConflict) {
                $errMsg = 'Bu saat aralığı dolu gösterilmiş. Önce dolu işaretini kaldırın.';
                wb_err($errMsg, 409, 'blocked_conflict');
            }
            $errMsg = $isAdminSession
                ? 'Bu saat aralığında randevu var. Önce mevcut randevuyu iptal edin, sonra tekrar deneyin.'
                : 'Bu saat dolu';
            wb_err($errMsg, 409, 'time_conflict');
        }
    }

    // BUG FIX 2: customer.uid artık request body'sinden ALINMIYOR.
    // Eski kod: body'deki uid doğrudan DB'ye yazılıyordu.
    // Saldırı örneği: {"customer":{"uid":"1"}} göndererek randevuyu
    // başka bir kullanıcıya bağlamak mümkündü.
    // Güvenli sıralama: önce session (doğrulanmış), sonra telefon ile lookup.
    $customerUserId = null;
    if (!empty($_SESSION['user_id']) && ($_SESSION['user_role'] ?? '') === 'user') {
        // Giriş yapmış müşteri — session her zaman önceliklidir
        $customerUserId = (int)$_SESSION['user_id'];
    } elseif ($custPhone) {
        // Misafir randevusu: telefon numarasıyla mevcut müşteri hesabına bağla
        try {
            $cuStmt = $pdo->prepare("SELECT user_id FROM customers WHERE phone = ? LIMIT 1");
            $cuStmt->execute([$custPhone]);
            $cuRow = $cuStmt->fetch();
            if ($cuRow) $customerUserId = (int)$cuRow['user_id'];
        } catch (Throwable) {}
    }

    // Schema'ya göre sabit kolon listesi
    $fields  = ['business_id','staff_id','service_id','customer_name','customer_phone','customer_email','customer_user_id','start_at','end_at','status','notes','created_at'];
    $values  = [$businessId, $staffId, $serviceId, $custName, $custPhone ?: null, $custEmail ?: null, $customerUserId, $startStr, $endStr, $finalStatus, $notes ?: null, date('Y-m-d H:i:s')];
    $holders = array_fill(0, count($fields), '?');

    $sql = 'INSERT INTO appointments (' . implode(',', $fields) . ') VALUES (' . implode(',', $holders) . ')';
    $pdo->prepare($sql)->execute($values);

    $newId = (string)$pdo->lastInsertId();

    // Kilit kaldir: randevu basariyla olusturuldu, lock artik gerekli degil
    if ($lockToken !== '') {
        try {
            $pdo->prepare('DELETE FROM slot_locks WHERE lock_token = ?')->execute([$lockToken]);
        } catch (Throwable) {}
    }

    // ── Bildirim kaydı ──────────────────────────────────────────────────────
    try {
        $svcName  = null;
        $stfName  = null;
        if ($serviceId) {
            $tmp = $pdo->prepare("SELECT name FROM services WHERE id=? LIMIT 1");
            $tmp->execute([$serviceId]);
            $svcName = $tmp->fetchColumn() ?: null;
        }
        if ($staffId) {
            $tmp = $pdo->prepare("SELECT name FROM staff WHERE id=? LIMIT 1");
            $tmp->execute([$staffId]);
            $stfName = $tmp->fetchColumn() ?: null;
        }
        // Sadece pending randevular için bildirim oluştur (admin approved eklerse bildirim gereksiz)
        if (!$isAdminQuickBooking && $finalStatus === 'pending') {
            $pdo->prepare("
                INSERT IGNORE INTO notifications
                  (business_id,appointment_id,type,customer_name,customer_phone,
                   service_name,staff_name,appointment_start,result,created_at)
                VALUES (?,?,'booking',?,?,?,?,?,'pending',NOW())
            ")->execute([$businessId, (int)$newId, $custName, $custPhone ?: null,
                         $svcName, $stfName, $startStr]);
        }

        // Kullanıcı paneli için site içi bildirim
        $userNotifId = wbResolveAppointmentUserId($pdo, [
            'customer_user_id' => $customerUserId,
            'customer_phone'   => $custPhone,
        ]);
        if ($userNotifId && !$isAdminQuickBooking) {
            $bizNameForNotif = '';
            try {
                $bNameStmt = $pdo->prepare('SELECT name FROM businesses WHERE id = ? LIMIT 1');
                $bNameStmt->execute([$businessId]);
                $bizNameForNotif = (string)($bNameStmt->fetchColumn() ?: '');
            } catch (Throwable) {
            }
            $notif = wbUserNotifFromStatus($finalStatus, $bizNameForNotif ?: 'Isletme', $startStr, (string)($svcName ?? ''));
            wbInsertUserNotification(
                $pdo,
                (int)$userNotifId,
                (int)$newId,
                $notif['type'],
                $notif['title'],
                $notif['message'],
                $bizNameForNotif
            );
        }
    } catch (Throwable $nErr) {
        error_log('[book.php notification] ' . $nErr->getMessage());
    }
    // ────────────────────────────────────────────────────────────────────────

    $pdo->commit();

    // ── Email verisini önceden hazırla (SMS de kullanıyor) ──────────────────────
    // BUG FIX: $emailData daha önce email try/catch içinde tanımlanıyordu.
    // Email bloğu exception atarsa $emailData undefined kalıyor, SMS bloğu patlar.
    // Artık veri yükleme ayrı yapılıyor.
    $emailData = [];
    try {
        require_once __DIR__ . '/../_mailer.php';
        require_once __DIR__ . '/../_email_templates.php';
        $apptRow = [
            'id'             => $newId,
            'business_id'    => $businessId,
            'staff_id'       => $staffId,
            'service_id'     => $serviceId,
            'customer_name'  => $custName,
            'customer_phone' => $custPhone,
            'customer_email' => $custEmail ?? '',
            'customer_user_id' => $customerUserId,
            'start_at'       => $startStr,
            'end_at'         => $endStr,
            'status'         => $finalStatus,
        ];
        $emailData = wbApptToEmailData($apptRow, $pdo);
    } catch (Throwable $edEx) {
        error_log('[book.php emailData] ' . $edEx->getMessage());
    }

    // ── Email Bildirimleri ──────────────────────────────────────────────
    try {
        if (!$isAdminQuickBooking && !empty($custEmail) && !empty($emailData)) {
            [$subj, $html] = wbEmailApptConfirm($emailData);
            wbMail($custEmail, $custName, $subj, $html);
        }
        if (!$isAdminQuickBooking && !empty($emailData['ownerEmail'])) {
            [$subj, $html] = wbEmailNewApptBiz($emailData);
            wbMail($emailData['ownerEmail'], $emailData['bizName'], $subj, $html);
        }
    } catch (Throwable $mailEx) {
        error_log('[book.php mail] ' . $mailEx->getMessage());
    }

    // ── SMS Bildirimi (Randevu alındı → müşteriye) ──────────────────
    try {
        if (!$isAdminQuickBooking) {
            require_once __DIR__ . '/../_sms.php';
        }
        if (!$isAdminQuickBooking && !empty($custPhone)) {
            $dt          = new DateTimeImmutable($startStr, new DateTimeZone('Europe/Istanbul'));
            $bizNameSms  = $emailData['bizName'] ?? 'İşletme';
            queueSms(
                $pdo,
                $custPhone,
                smsApptBooked($bizNameSms, $dt->format('d.m.Y'), $dt->format('H:i')),
                'booking',
                (int)$newId
            );
        }
    } catch (Throwable $smsEx) {
        error_log('[book.php sms] ' . $smsEx->getMessage());
    }
    // ── SMS sonu ────────────────────────────────────────────────────

    // ── Web Push (işletme sahibine anlık bildirim) ───────────────────
    try {
        if (!$isAdminQuickBooking) {
            require_once __DIR__ . '/../_push.php';
        $dt       = new DateTimeImmutable($startStr, new DateTimeZone('Europe/Istanbul'));
            sendPushToBusiness(
            $pdo,
            $businessId,
            '🔔 Yeni Randevu',
            $custName . ' — ' . $dt->format('d.m.Y H:i'),
            '/calendar.html',
            'new-booking'
            );
        }
    } catch (Throwable $pushEx) {
        error_log('[book.php push] ' . $pushEx->getMessage());
    }
    // ── Push sonu ────────────────────────────────────────────────────

    wb_ok([
        'id'      => $newId,
        'rid'     => $newId,
        'status'  => $finalStatus,
        'startAt' => $startStr,
        'endAt'   => $endStr,
    ]);

} catch (Throwable $e) {
    if ($pdo->inTransaction()) $pdo->rollBack();
    error_log('[book.php] ' . $e->getMessage());
    wb_err('Randevu oluşturulamadı. Lütfen tekrar deneyin.', 500);
}
