<?php
declare(strict_types=1);
// PUBLIC — müşteri iptal talebinin durumunu poll eder
require_once __DIR__ . '/../_public_bootstrap.php';

wb_method('GET');

$apptId = (int)($_GET['id'] ?? 0);
if (!$apptId) { wb_err('id parametresi zorunlu', 400, 'missing_param'); }

try {
    $stmt = $pdo->prepare("SELECT id, status FROM appointments WHERE id = ? LIMIT 1");
    $stmt->execute([$apptId]);
    $appt = $stmt->fetch();

    if (!$appt) { wb_err('Randevu bulunamadı', 404, 'not_found'); }

    $status  = $appt['status'];
    $message = match($status) {
        'cancelled'               => 'Randevunuz başarıyla iptal edilmiştir.',
        'cancellation_requested'  => 'İptal talebiniz işletmeye iletildi. Onay bekleniyor…',
        default                   => null,
    };

    wb_ok(['status' => $status, 'message' => $message]);

} catch (Throwable $e) {
    error_log('[appointments/cancellation-status.php] ' . $e->getMessage());
    wb_err('Sunucu hatası.', 500, 'internal_error');
}