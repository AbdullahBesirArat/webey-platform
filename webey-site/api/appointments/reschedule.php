<?php
declare(strict_types=1);
/**
 * api/appointments/reschedule.php
 * POST { id, startAt }  — Admin randevuyu yeniden planlar
 *
 * BUG FIX 1: DateTime timezone eksikti → sunucu saatle Türkiye saati uyuşmazlığı
 * BUG FIX 2: Geçmiş tarihe yeniden planlama önlenmiyordu
 * BUG FIX 3: Müşteriye bildirim (email + SMS) gönderilmiyordu
 * BUG FIX 4: service_id NULL olduğunda süre hep 30dk — db'den saat aralığı hesaplanabilir
 */

require_once __DIR__ . '/../admin/_bootstrap.php';
require_once __DIR__ . '/../_appointment_log.php';
wb_method('POST');

$bid = (int)($user['business_id'] ?? 0);
if (!$bid) { wb_err('İşletme bulunamadı', 404, 'business_not_found'); }

$in            = wb_body();
$appointmentId = $in['id']      ?? null;
$newStartAt    = $in['startAt'] ?? null;

if (!$appointmentId || !$newStartAt) {
    wb_err('id ve startAt zorunlu', 400, 'missing_param');
}

// BUG FIX 1: Her zaman Türkiye saatini kullan
$tz = new DateTimeZone('Europe/Istanbul');

try {
    $startDT = new DateTimeImmutable($newStartAt, $tz);
} catch (Throwable) {
    wb_err('startAt geçerli bir tarih formatında olmalı (ISO 8601)', 400, 'invalid_date');
}

// BUG FIX 2: Geçmiş tarihe yeniden planlamayı engelle
if ($startDT <= new DateTimeImmutable('now', $tz)) {
    wb_err('Geçmiş bir tarihe randevu planlanamaz.', 400, 'past_date');
}

try {
    $pdo->beginTransaction();

    $stmt = $pdo->prepare("
        SELECT id, staff_id, service_id, status,
               start_at, end_at,
               customer_name, customer_phone, customer_email, customer_user_id
        FROM appointments
        WHERE id = ? AND business_id = ?
        LIMIT 1 FOR UPDATE
    ");
    $stmt->execute([$appointmentId, $bid]);
    $appt = $stmt->fetch();

    if (!$appt) {
        $pdo->rollBack();
        wb_err('Randevu bulunamadı', 404, 'not_found');
    }
    if (in_array($appt['status'], ['cancelled', 'no_show', 'rejected', 'declined'], true)) {
        $pdo->rollBack();
        wb_err('İptal edilmiş veya tamamlanmış randevu yeniden planlanamaz', 409, 'invalid_status');
    }

    // Süre: önce service tablosundan, yoksa mevcut randevudan hesapla
    $duration = 30;
    if (!empty($appt['service_id'])) {
        $svcStmt = $pdo->prepare("SELECT duration_min FROM services WHERE id = ? AND business_id = ? LIMIT 1");
        $svcStmt->execute([$appt['service_id'], $bid]);
        $svc = $svcStmt->fetch();
        if ($svc && (int)$svc['duration_min'] > 0) {
            $duration = (int)$svc['duration_min'];
        }
    } elseif ($appt['start_at'] && $appt['end_at']) {
        // BUG FIX 4: service_id yoksa mevcut randevunun süresini kullan
        $oldStart = new DateTimeImmutable($appt['start_at'], $tz);
        $oldEnd   = new DateTimeImmutable($appt['end_at'],   $tz);
        $calcDur  = (int)(($oldEnd->getTimestamp() - $oldStart->getTimestamp()) / 60);
        if ($calcDur > 0) $duration = $calcDur;
    }

    $endDT     = $startDT->modify("+{$duration} minutes");
    $startAtDb = $startDT->format('Y-m-d H:i:s');
    $endAtDb   = $endDT->format('Y-m-d H:i:s');

    // Çakışma kontrolü (kendi ID'si hariç)
    if ($appt['staff_id']) {
        $cfStmt = $pdo->prepare("
            SELECT id FROM appointments
            WHERE business_id = ? AND staff_id = ? AND id != ?
              AND status NOT IN ('cancelled','no_show','rejected','declined')
              AND start_at < ? AND end_at > ?
            FOR UPDATE
        ");
        $cfStmt->execute([$bid, $appt['staff_id'], $appointmentId, $endAtDb, $startAtDb]);
    } else {
        $cfStmt = $pdo->prepare("
            SELECT id FROM appointments
            WHERE business_id = ? AND id != ?
              AND status NOT IN ('cancelled','no_show','rejected','declined')
              AND start_at < ? AND end_at > ?
            FOR UPDATE
        ");
        $cfStmt->execute([$bid, $appointmentId, $endAtDb, $startAtDb]);
    }

    if ($cfStmt->fetch()) {
        $pdo->rollBack();
        wb_err('Seçilen saat dolu', 409, 'time_conflict');
    }

    $prevStartAt = $appt['start_at'];

    $pdo->prepare("
        UPDATE appointments SET start_at = ?, end_at = ?, updated_at = NOW()
        WHERE id = ? AND business_id = ?
    ")->execute([$startAtDb, $endAtDb, $appointmentId, $bid]);

    wb_appt_log(
        $pdo, $appointmentId, 'rescheduled',
        $prevStartAt, $startAtDb,
        (int)($_SESSION['user_id'] ?? 0) ?: null
    );

    $pdo->commit();

    // BUG FIX 3: Müşteriye yeniden planlama bildirimi gönder
    try {
        require_once __DIR__ . '/../_mailer.php';
        require_once __DIR__ . '/../_email_templates.php';

        $apptFull = $pdo->prepare("
            SELECT a.*, b.name AS business_name, b.address_line, b.city, b.district,
                   s.name AS service_name, st.name AS staff_name,
                   u.email AS owner_email
            FROM appointments a
            LEFT JOIN businesses b ON b.id = a.business_id
            LEFT JOIN services   s ON s.id = a.service_id
            LEFT JOIN staff     st ON st.id = a.staff_id
            LEFT JOIN users      u ON u.id = b.owner_id
            WHERE a.id = ? LIMIT 1
        ");
        $apptFull->execute([$appointmentId]);
        $row = $apptFull->fetch();

        if ($row) {
            $emailData = wbApptToEmailData($row, $pdo);
            $custEmail = $row['customer_email'] ?? '';
            $custName  = $row['customer_name']  ?? 'Müşteri';

            // Randevu yeniden planlama emaili (mevcut şablondan yararlan, yoksa fallback)
            if ($custEmail && filter_var($custEmail, FILTER_VALIDATE_EMAIL)) {
                if (function_exists('wbEmailApptRescheduled')) {
                    [$subj, $html] = wbEmailApptRescheduled($emailData);
                } else {
                    // Şablon henüz yoksa: onay emailini yeni tarihle gönder
                    [$subj, $html] = wbEmailApptApproved($emailData);
                    $subj = 'Randevunuz Yeniden Planlandı — ' . ($row['business_name'] ?? 'Webey');
                }
                wbMail($custEmail, $custName, $subj, $html);
            }
        }
    } catch (Throwable $mailEx) {
        error_log('[reschedule.php mail] ' . $mailEx->getMessage());
    }

    // SMS Bildirimi
    try {
        require_once __DIR__ . '/../_sms.php';
        $custPhone = $appt['customer_phone'] ?? '';
        if ($custPhone) {
            $dt      = new DateTimeImmutable($startAtDb, $tz);
            $bizName = $row['business_name'] ?? 'İşletme';
            $smsText = function_exists('smsApptRescheduled')
                ? smsApptRescheduled($bizName, $dt->format('d.m.Y'), $dt->format('H:i'))
                : "Webey: {$bizName} — randevunuz {$dt->format('d.m.Y H:i')} tarihine taşındı.";
            queueSms($pdo, $custPhone, $smsText, 'rescheduled', (int)$appointmentId);
        }
    } catch (Throwable $smsEx) {
        error_log('[reschedule.php sms] ' . $smsEx->getMessage());
    }

    wb_ok([
        'id'      => (string)$appointmentId,
        'startAt' => $startAtDb,
        'endAt'   => $endAtDb,
    ]);

} catch (Throwable $e) {
    if ($pdo->inTransaction()) $pdo->rollBack();
    error_log('[appointments/reschedule.php] ' . $e->getMessage());
    wb_err('Randevu güncellenemedi. Lütfen tekrar deneyin.', 500, 'internal_error');
}