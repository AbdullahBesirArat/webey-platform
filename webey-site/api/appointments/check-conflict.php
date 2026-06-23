<?php
declare(strict_types=1);
/**
 * api/appointments/check-conflict.php
 * POST JSON: { startISO, endISO }
 * PUBLIC (soft-auth) — müşterinin aynı zaman diliminde başka randevusu var mı?
 *
 * BUG FIX: Önceki sürüm tamamen ölü koddu — daima { hasConflict: false } dönüyordu.
 * Sebep: appointments.user_uid kolonu şemada yok, customer_user_id kullanılmalıydı.
 *
 * Artık:
 *   - Oturumlu müşteri → customer_user_id üzerinden çakışma kontrol edilir
 *   - Oturumsuz      → çakışma yok sayılır (anonim rezervasyonlar kontrol edilemez)
 */

require_once __DIR__ . '/../_public_bootstrap.php';
wb_method('POST');

$data     = wb_body();
$startISO = trim($data['startISO'] ?? '');
$endISO   = trim($data['endISO']   ?? '');

// Tarih yoksa veya oturum açık değilse çakışma kontrol edilemez
if (!$startISO || !$endISO) {
    wb_ok(['hasConflict' => false, 'bizName' => '', 'businessId' => '']);
}

$userId = (int)($_SESSION['user_id'] ?? 0);
$isUser = $userId && ($_SESSION['user_role'] ?? '') === 'user';

if (!$isUser) {
    // Oturumsuz veya admin → çakışma kontrolü atla
    wb_ok(['hasConflict' => false, 'bizName' => '', 'businessId' => '']);
}

try {
    $startDT = new DateTime($startISO);
    $endDT   = new DateTime($endISO);
} catch (Throwable) {
    wb_ok(['hasConflict' => false, 'bizName' => '', 'businessId' => '']);
}

if ($endDT <= $startDT) {
    wb_ok(['hasConflict' => false, 'bizName' => '', 'businessId' => '']);
}

$startDb = $startDT->format('Y-m-d H:i:s');
$endDb   = $endDT->format('Y-m-d H:i:s');

try {
    $stmt = $pdo->prepare("
        SELECT a.business_id, b.name AS biz_name
        FROM appointments a
        LEFT JOIN businesses b ON b.id = a.business_id
        WHERE a.customer_user_id = ?
          AND a.status NOT IN ('cancelled','no_show','rejected','declined')
          AND a.start_at < ?
          AND a.end_at   > ?
        LIMIT 1
    ");
    $stmt->execute([$userId, $endDb, $startDb]);
    $conflict = $stmt->fetch();

    if ($conflict) {
        wb_ok([
            'hasConflict' => true,
            'bizName'     => $conflict['biz_name'] ?? '',
            'businessId'  => (string)($conflict['business_id'] ?? ''),
        ]);
    }

    wb_ok(['hasConflict' => false, 'bizName' => '', 'businessId' => '']);

} catch (Throwable $e) {
    error_log('[check-conflict.php] ' . $e->getMessage());
    // Çakışma kontrolü başarısız olursa kullanıcıyı bloke etme
    wb_ok(['hasConflict' => false, 'bizName' => '', 'businessId' => '']);
}