<?php
declare(strict_types=1);

/**
 * Kullanıcıya site içi randevu bildirimi yaz.
 * - customer_user_id varsa onu kullanır
 * - yoksa customer_phone -> customers.user_id eşlemesi dener
 */
function wbResolveAppointmentUserId(PDO $pdo, array $apptRow): ?int
{
    $uid = $apptRow['customer_user_id'] ?? null;
    if ($uid !== null && (int)$uid > 0) {
        return (int)$uid;
    }

    $phone = trim((string)($apptRow['customer_phone'] ?? ''));
    if ($phone === '') {
        return null;
    }

    $stmt = $pdo->prepare('SELECT user_id FROM customers WHERE phone = ? LIMIT 1');
    $stmt->execute([$phone]);
    $row = $stmt->fetch();
    if (!$row) {
        return null;
    }
    return (int)$row['user_id'];
}

/**
 * @param string $status appointment status
 * @return array{type:string,title:string,message:string}
 */
function wbUserNotifFromStatus(string $status, string $bizName, string $startAt, string $serviceName = ''): array
{
    $s = strtolower(trim($status));
    $dtText = $startAt;
    try {
        $dt = new DateTimeImmutable($startAt, new DateTimeZone('Europe/Istanbul'));
        $dtText = $dt->format('d.m.Y H:i');
    } catch (Throwable) {
    }

    $svc = $serviceName !== '' ? (' - ' . $serviceName) : '';

    if ($s === 'approved') {
        return [
            'type' => 'appt_approved',
            'title' => 'Randevunuz onaylandi',
            'message' => $bizName . ' - ' . $dtText . $svc . '. Randevularinizi profil sayfanizdan gorebilirsiniz.',
        ];
    }
    if (in_array($s, ['cancelled', 'canceled'], true)) {
        return [
            'type' => 'appt_cancelled',
            'title' => 'Randevunuz iptal edildi',
            'message' => $bizName . ' - ' . $dtText . $svc . ' randevusu iptal edildi.',
        ];
    }
    if (in_array($s, ['rejected', 'declined'], true)) {
        return [
            'type' => 'appt_rejected',
            'title' => 'Randevunuz reddedildi',
            'message' => $bizName . ' - ' . $dtText . $svc . ' randevusu reddedildi.',
        ];
    }
    if ($s === 'cancellation_requested') {
        return [
            'type' => 'info',
            'title' => 'Iptal talebiniz iletildi',
            'message' => $bizName . ' randevunuz icin iptal talebiniz alindi. Sonuc bildirilecektir.',
        ];
    }
    if ($s === 'pending') {
        return [
            'type' => 'info',
            'title' => 'Randevunuz iletildi',
            'message' => $bizName . ' - ' . $dtText . $svc . ' randevunuz iletildi. Isletme onayladiginda bilgilendirileceksiniz.',
        ];
    }
    if ($s === 'no_show') {
        return [
            'type' => 'info',
            'title' => 'Randevu durumu guncellendi',
            'message' => $bizName . ' randevunuz gelmedi olarak isaretlendi.',
        ];
    }
    return [
        'type' => 'info',
        'title' => 'Randevu durumu guncellendi',
        'message' => $bizName . ' randevu durumunuz: ' . $status,
    ];
}

function wbInsertUserNotification(PDO $pdo, int $userId, int $appointmentId, string $type, string $title, string $message, string $bizName = ''): void
{
    $pdo->prepare(
        'INSERT INTO user_notifications (user_id, appointment_id, type, title, message, business_name, is_read, created_at) VALUES (?, ?, ?, ?, ?, ?, 0, NOW())'
    )->execute([$userId, $appointmentId, $type, $title, $message, $bizName ?: null]);
}

