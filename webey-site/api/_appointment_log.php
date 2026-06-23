<?php
declare(strict_types=1);
/**
 * api/_appointment_log.php — Randevu Log Yardımcısı
 * ══════════════════════════════════════════════════
 * appointment_logs tablosuna güvenli şekilde kayıt atar.
 * setStatus.php, update-appointment.php ve calendar endpoint'leri kullanır.
 *
 * Kullanım:
 *   require_once __DIR__ . '/../_appointment_log.php';
 *   wb_appt_log($pdo, $appointmentId, 'status_changed', 'pending', 'approved', $actorUserId);
 *   wb_appt_log($pdo, $appointmentId, 'attended_marked', null, null, $actorUserId);
 */

if (!function_exists('wb_appt_log')) {

    /**
     * appointment_logs tablosuna bir kayıt atar.
     * Hata olursa sessizce loglar — ana akışı asla kesmez.
     *
     * @param PDO         $pdo
     * @param int|string  $appointmentId
     * @param string      $action        'status_changed' | 'attended_marked' | 'cancelled_by_user' | vb.
     * @param string|null $prevStatus    Önceki durum (status değişikliğinde)
     * @param string|null $newStatus     Yeni durum (status değişikliğinde)
     * @param int|null    $actorUserId   İşlemi yapan kullanıcı ID (null = müşteri/anonim)
     */
    function wb_appt_log(
        PDO    $pdo,
        mixed  $appointmentId,
        string $action,
        ?string $prevStatus   = null,
        ?string $newStatus    = null,
        ?int    $actorUserId  = null
    ): void {
        try {
            $pdo->prepare("
                INSERT INTO appointment_logs
                    (appointment_id, action, prev_status, new_status, actor_user_id, created_at)
                VALUES (?, ?, ?, ?, ?, NOW())
            ")->execute([
                (int)$appointmentId,
                $action,
                $prevStatus,
                $newStatus,
                $actorUserId,
            ]);
        } catch (Throwable $e) {
            // Log kaydı başarısız olursa ana akışı kesme — sadece error_log'a yaz
            error_log('[wb_appt_log] appointment_id=' . $appointmentId . ' action=' . $action . ' — ' . $e->getMessage());
        }
    }

    /**
     * Randevunun mevcut durumunu çeker (log için önceki durum).
     * Hata olursa null döner.
     */
    function wb_appt_current_status(PDO $pdo, mixed $appointmentId): ?string
    {
        try {
            $stmt = $pdo->prepare("SELECT status FROM appointments WHERE id = ? LIMIT 1");
            $stmt->execute([(int)$appointmentId]);
            $row = $stmt->fetch();
            return $row ? (string)$row['status'] : null;
        } catch (Throwable) {
            return null;
        }
    }
}