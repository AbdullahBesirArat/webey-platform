<?php
declare(strict_types=1);
/**
 * api/staff/save.php
 * POST — Personel ekle (id yok) veya güncelle (id var)
 */

require_once __DIR__ . '/../admin/_bootstrap.php';
wb_method('POST');

$bid = $user['business_id'];
if (!$bid) wb_err('İşletme bulunamadı', 404, 'business_not_found');

$in = wb_body();
wb_validate($in, ['name' => ['required', 'max:191']]);

$id       = isset($in['id']) && $in['id'] ? (int)$in['id'] : null;
$name     = trim((string)($in['name']     ?? ''));
$phone    = preg_replace('/\D+/', '', (string)($in['phone'] ?? '')) ?: null;
$color    = trim((string)($in['color']    ?? '')) ?: null;

try {
    if ($id) {
        // ── Güncelle ─────────────────────────────────────────────────────────
        $stmt = $pdo->prepare('UPDATE staff SET name=?, phone=?, color=? WHERE id=? AND business_id=?');
        $stmt->execute([$name, $phone, $color, $id, $bid]);
        wb_ok(['updated' => true, 'id' => (string)$id]);
    } else {
        // ── Yeni ekle ────────────────────────────────────────────────────────
        $stmt = $pdo->prepare('INSERT INTO staff (business_id, name, phone, color) VALUES (?,?,?,?)');
        $stmt->execute([$bid, $name, $phone, $color]);
        $newId = (int)$pdo->lastInsertId();

        // Yeni personele işletme saatlerini kopyala
        $bh = $pdo->prepare('SELECT day, is_open, open_time, close_time FROM business_hours WHERE business_id = ?');
        $bh->execute([$bid]);
        $bizHours = $bh->fetchAll();

        if (!empty($bizHours)) {
            $ins = $pdo->prepare('INSERT INTO staff_hours (staff_id, business_id, day, is_open, open_time, close_time) VALUES (?,?,?,?,?,?)');
            foreach ($bizHours as $h) {
                $ins->execute([$newId, $bid, $h['day'], $h['is_open'], $h['open_time'], $h['close_time']]);
            }
        }

        // Yeni personele tüm mevcut servisleri ata
        $svcStmt = $pdo->prepare('SELECT id FROM services WHERE business_id = ?');
        $svcStmt->execute([$bid]);
        $allSvcIds = $svcStmt->fetchAll(PDO::FETCH_COLUMN);

        if (!empty($allSvcIds)) {
            $insertSvc = $pdo->prepare('INSERT IGNORE INTO staff_services (staff_id, service_id) VALUES (?, ?)');
            foreach ($allSvcIds as $svcId) {
                $insertSvc->execute([$newId, (int)$svcId]);
            }
        }

        wb_ok(['created' => true, 'id' => (string)$newId]);
    }

} catch (Throwable $e) {
    error_log('[staff/save] ' . $e->getMessage());
    wb_err('Personel kaydedilemedi', 500, 'internal_error');
}
