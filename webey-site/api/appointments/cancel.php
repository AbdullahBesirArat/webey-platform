<?php
declare(strict_types=1);
/**
 * api/appointments/cancel.php — Müşteri iptal talebi
 * POST JSON: { id, reason?, phone? }
 *
 * GÜVENLİK:
 *   - Giriş yapmış kullanıcı → customer_user_id veya telefon eşleşmesi zorunlu
 *   - Misafir kullanıcı → telefon numarası zorunlu (appointment.customer_phone eşleşmeli)
 *   - Hiçbiri yoksa 403 döner — anonim iptal artık YASAK
 *
 * BUG FIX 1: Önceki sürüm oturumsuz kullanıcının herhangi bir randevuyu
 *             sadece ID göndererek iptal etmesine izin veriyordu.
 * BUG FIX 2: appointment_logs'a prev_status yazılmıyordu →
 *             reject-cancellation.php hep 'approved' e döndürüyordu.
 * BUG FIX 3: Rate limiting + geçmiş randevu kontrolü eklendi.
 */

require_once __DIR__ . '/../_public_bootstrap.php';
wb_method('POST');

// ── Rate Limiting: 1 dk'da 10 iptal denemesi ────────────────────────────────
$ip      = trim(explode(',', $_SERVER['HTTP_X_FORWARDED_FOR'] ?? $_SERVER['REMOTE_ADDR'] ?? '0.0.0.0')[0]);
$rateKey = 'cancel:' . md5($ip);
try {
    $pdo->prepare('DELETE FROM api_rate_limits WHERE cache_key = ? AND expires_at < NOW()')->execute([$rateKey]);
    $rStmt = $pdo->prepare('SELECT hits FROM api_rate_limits WHERE cache_key = ? LIMIT 1');
    $rStmt->execute([$rateKey]);
    $hits = (int)($rStmt->fetchColumn() ?: 0);
    if ($hits >= 10) {
        wb_err('Çok fazla istek gönderildi. Lütfen 1 dakika bekleyin.', 429, 'rate_limited');
    }
    if ($hits === 0) {
        $pdo->prepare('INSERT INTO api_rate_limits (cache_key, hits, expires_at) VALUES (?, 1, DATE_ADD(NOW(), INTERVAL 60 SECOND))')->execute([$rateKey]);
    } else {
        $pdo->prepare('UPDATE api_rate_limits SET hits = hits + 1 WHERE cache_key = ?')->execute([$rateKey]);
    }
} catch (Throwable) {}
// ────────────────────────────────────────────────────────────────────────────

$data       = wb_body();
$apptId     = (int)($data['id'] ?? 0);
$reason     = trim($data['reason'] ?? 'user_cancel');
$guestPhone = preg_replace('/\D/', '', trim($data['phone'] ?? ''));

if (!$apptId) {
    wb_err('Eksik parametre: id zorunlu', 400, 'missing_param');
}

// ── Yetkilendirme ────────────────────────────────────────────────────────────
$sessionUserId = (int)($_SESSION['user_id'] ?? 0);
$sessionPhone  = preg_replace('/\D/', '', $_SESSION['user_phone'] ?? '');

// En az biri olmalı: aktif oturum VEYA telefon numarası
if (!$sessionUserId && !$guestPhone) {
    wb_err(
        'Bu işlem için giriş yapmanız ya da rezervasyon telefonunuzu belirtmeniz gerekiyor.',
        401,
        'unauthorized'
    );
}
// ────────────────────────────────────────────────────────────────────────────

try {
    $stmt = $pdo->prepare("
        SELECT a.id, a.status, a.business_id, a.customer_phone, a.customer_name,
               a.customer_user_id, a.start_at, s.name AS service_name
        FROM appointments a
        LEFT JOIN services s ON s.id = a.service_id
        WHERE a.id = ? LIMIT 1
    ");
    $stmt->execute([$apptId]);
    $appt = $stmt->fetch();

    if (!$appt) {
        wb_err('Randevu bulunamadı', 404, 'not_found');
    }

    // ── Sahiplik Doğrulama ───────────────────────────────────────────────────
    $apptPhone  = substr(preg_replace('/\D/', '', $appt['customer_phone'] ?? ''), -10);
    $authorized = false;

    if ($sessionUserId) {
        if ((int)$appt['customer_user_id'] === $sessionUserId) {
            $authorized = true;
        }
        if (!$authorized && $sessionPhone && $apptPhone) {
            $authorized = substr($sessionPhone, -10) === $apptPhone;
        }
    }

    if (!$authorized && $guestPhone && strlen($guestPhone) >= 7) {
        $authorized = substr($guestPhone, -10) === $apptPhone;
    }

    if (!$authorized) {
        error_log('[cancel.php] Yetkisiz iptal denemesi: appt_id=' . $apptId . ' ip=' . $ip);
        wb_err('Bu randevuya erişim yetkiniz yok.', 403, 'forbidden');
    }
    // ────────────────────────────────────────────────────────────────────────

    if (!in_array($appt['status'], ['pending', 'approved'], true)) {
        wb_err('Bu randevu iptal edilemez (durum: ' . $appt['status'] . ')', 400, 'invalid_status');
    }

    // BUG FIX 3: Geçmiş randevuyu iptal ettirme
    if (strtotime($appt['start_at']) <= time()) {
        wb_err('Geçmiş randevu iptal edilemez.', 409, 'past_appointment');
    }

    $prevStatus = $appt['status'];
    $pdo->prepare("UPDATE appointments SET status='cancellation_requested' WHERE id=?")
        ->execute([$apptId]);

    $businessId = (int)$appt['business_id'];

    // BUG FIX 2: Log'a prev_status yaz — reject-cancellation.php bunu okuyacak
    try {
        require_once __DIR__ . '/../_appointment_log.php';
        wb_appt_log(
            $pdo,
            $apptId,
            'cancellation_requested',
            $prevStatus,
            'cancellation_requested',
            $sessionUserId ?: null
        );
    } catch (Throwable) {}

    // Bildirim kaydı
    // BUGFIX: INSERT IGNORE appointment_id UNIQUE constraint yüzünden cancellation'ı atlıyordu.
    // Mevcut booking kaydını cancellation'a çevir; yoksa yeni ekle.
    try {
        $pdo->prepare("
            UPDATE notifications
            SET type = 'cancellation', result = 'pending', is_read = 0, created_at = NOW()
            WHERE appointment_id = ? AND business_id = ? AND type = 'booking'
            LIMIT 1
        ")->execute([$apptId, $businessId]);

        $affected = (int)$pdo->query("SELECT ROW_COUNT()")->fetchColumn();
        if ($affected === 0) {
            $pdo->prepare("
                INSERT INTO notifications
                  (business_id, appointment_id, type, customer_name, customer_phone,
                   service_name, appointment_start, result, created_at)
                VALUES (?, ?, 'cancellation', ?, ?, ?, ?, 'pending', NOW())
            ")->execute([
                $businessId, $apptId,
                $appt['customer_name'],
                $appt['customer_phone'] ?? null,
                $appt['service_name']   ?? null,
                $appt['start_at']       ?? null,
            ]);
        }
    } catch (Throwable $nErr) {
        error_log('[appointments/cancel.php notification] ' . $nErr->getMessage());
    }

    wb_ok([
        'id'         => (string)$apptId,
        'status'     => 'cancellation_requested',
        'businessId' => (string)$businessId,
        'message'    => 'İptal talebiniz alındı. İşletme onayladığında randevunuz iptal edilecektir.',
    ]);

} catch (Throwable $e) {
    error_log('[appointments/cancel.php] ' . $e->getMessage());
    wb_err('İşlem tamamlanamadı.', 500, 'internal_error');
}