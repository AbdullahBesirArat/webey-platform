<?php
declare(strict_types=1);
/**
 * api/services/save.php
 * POST — Hizmet ekle (id yok) veya güncelle (id var)
 */

require_once __DIR__ . '/../admin/_bootstrap.php';
wb_method('POST');

$bid = $user['business_id'];
if (!$bid) wb_err('İşletme bulunamadı', 404, 'business_not_found');

$in = wb_body();
wb_validate($in, [
    'name'        => ['required', 'max:191'],
    'durationMin' => ['required', 'numeric'],
]);

$id          = isset($in['id']) && $in['id'] ? (int)$in['id'] : null;
$name        = trim((string)($in['name'] ?? ''));
$durationMin = (int)($in['durationMin'] ?? $in['duration_min'] ?? 0);
$price       = (isset($in['price']) && $in['price'] !== '' && $in['price'] !== null)
               ? (float)$in['price'] : null;

try {
    if ($id) {
        // Güncelleme — bu işletmeye ait mi kontrol et
        $chk = $pdo->prepare('SELECT id FROM services WHERE id = ? AND business_id = ? LIMIT 1');
        $chk->execute([$id, $bid]);
        if (!$chk->fetch()) wb_err('Hizmet bulunamadı', 404, 'not_found');

        $pdo->prepare('UPDATE services SET name = ?, price = ?, duration_min = ? WHERE id = ? AND business_id = ?')
            ->execute([$name, $price, $durationMin, $id, $bid]);

        wb_ok(['updated' => true, 'id' => (string)$id]);
    } else {
        $pdo->prepare('INSERT INTO services (business_id, name, price, duration_min) VALUES (?, ?, ?, ?)')
            ->execute([$bid, $name, $price, $durationMin]);

        wb_ok(['created' => true, 'id' => (string)$pdo->lastInsertId()]);
    }
} catch (Throwable $e) {
    error_log('[services/save] ' . $e->getMessage());
    wb_err('Hizmet kaydedilemedi', 500, 'internal_error');
}