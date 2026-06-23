<?php
declare(strict_types=1);
/**
 * api/staff/save-services.php
 * POST — Personele atanan hizmetleri kaydet
 */

require_once __DIR__ . '/../admin/_bootstrap.php';
wb_method('POST');

$bid = $user['business_id'];
if (!$bid) wb_err('İşletme bulunamadı', 404, 'business_not_found');

$in         = wb_body();
$staffId    = (int)($in['staffId'] ?? 0);
$serviceIds = is_array($in['serviceIds'] ?? null) ? $in['serviceIds'] : [];

if (!$staffId) wb_err('staffId zorunlu', 400, 'missing_staff_id');

try {
    $chk = $pdo->prepare('SELECT id FROM staff WHERE id = ? AND business_id = ?');
    $chk->execute([$staffId, $bid]);
    if (!$chk->fetch()) wb_err('Personel bulunamadı', 403, 'forbidden');

    // Sadece bu işletmeye ait servisleri kabul et
    $validIds = [];
    if (!empty($serviceIds)) {
        $placeholders = implode(',', array_fill(0, count($serviceIds), '?'));
        $params       = array_merge(array_map('intval', $serviceIds), [$bid]);
        $svcChk       = $pdo->prepare("SELECT id FROM services WHERE id IN ($placeholders) AND business_id = ?");
        $svcChk->execute($params);
        $validIds = array_column($svcChk->fetchAll(), 'id');
    }

    $pdo->prepare('DELETE FROM staff_services WHERE staff_id = ?')->execute([$staffId]);

    if (!empty($validIds)) {
        $ins = $pdo->prepare('INSERT INTO staff_services (staff_id, service_id) VALUES (?, ?)');
        foreach ($validIds as $svcId) {
            $ins->execute([$staffId, (int)$svcId]);
        }
    }

    wb_ok(['assigned' => count($validIds)]);

} catch (Throwable $e) {
    error_log('[staff/save-services] ' . $e->getMessage());
    wb_err('Servisler kaydedilemedi', 500, 'internal_error');
}