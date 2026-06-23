<?php
declare(strict_types=1);
/**
 * api/admin/backfill-staff-services.php
 * ═══════════════════════════════════════════════════════════════
 * Mevcut personellerin hiç hizmeti yoksa, işletmenin TÜM
 * hizmetlerini otomatik olarak atar.
 *
 * POST /api/admin/backfill-staff-services.php
 * Auth: Admin session gerekli
 *
 * Kullanım: Admin panelinden bir kez çalıştır.
 * Zaten servisi olan personellere dokunmaz (INSERT IGNORE).
 * ═══════════════════════════════════════════════════════════════
 */

require_once __DIR__ . '/../_bootstrap.php';

wb_method('POST');

$businessId = $user['business_id'];
if (!$businessId) {
    wb_err('İşletme bulunamadı', 404);
}

try {
    // İşletmenin tüm servisleri
    $svcStmt = $pdo->prepare("SELECT id FROM services WHERE business_id = ?");
    $svcStmt->execute([$businessId]);
    $allSvcIds = $svcStmt->fetchAll(PDO::FETCH_COLUMN);

    if (empty($allSvcIds)) {
        wb_ok(['message' => 'Atanacak hizmet yok', 'assigned' => 0]);
    }

    // İşletmenin tüm personeli
    $staffStmt = $pdo->prepare("SELECT id FROM staff WHERE business_id = ?");
    $staffStmt->execute([$businessId]);
    $allStaffIds = $staffStmt->fetchAll(PDO::FETCH_COLUMN);

    if (empty($allStaffIds)) {
        wb_ok(['message' => 'Personel bulunamadı', 'assigned' => 0]);
    }

    $insert = $pdo->prepare("INSERT IGNORE INTO staff_services (staff_id, service_id) VALUES (?, ?)");
    $count  = 0;

    foreach ($allStaffIds as $staffId) {
        foreach ($allSvcIds as $svcId) {
            $insert->execute([(int)$staffId, (int)$svcId]);
            $count += $pdo->rowCount();
        }
    }

    wb_ok([
        'message'  => "$count hizmet-personel ilişkisi eklendi",
        'assigned' => $count,
        'staff'    => count($allStaffIds),
        'services' => count($allSvcIds),
    ]);

} catch (Throwable $e) {
    error_log('[backfill-staff-services] ' . $e->getMessage());
    wb_err('İşlem sırasında hata oluştu', 500);
}