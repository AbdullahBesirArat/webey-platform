<?php
declare(strict_types=1);
/**
 * api/staff/remove-photo.php
 * POST — Personel profil fotoğrafını sil (dosya + DB)
 */

require_once __DIR__ . '/../admin/_bootstrap.php';
wb_method('POST');

$bid = $user['business_id'];
if (!$bid) wb_err('İşletme bulunamadı', 404, 'business_not_found');

$in      = wb_body();
$staffId = (int)($in['staffId'] ?? 0);
if (!$staffId) wb_err('staffId zorunlu', 400, 'missing_staff_id');

try {
    $chk = $pdo->prepare('SELECT id, photo_url, photo_opt FROM staff WHERE id = ? AND business_id = ?');
    $chk->execute([$staffId, $bid]);
    $staff = $chk->fetch();
    if (!$staff) wb_err('Personel bulunamadı', 403, 'forbidden');

    $webeyRoot = realpath(__DIR__ . '/../..');

    foreach (['photo_url', 'photo_opt'] as $field) {
        if (!empty($staff[$field])) {
            $path     = $webeyRoot . '/' . ltrim($staff[$field], '/');
            $realPath = realpath($path);
            if ($realPath && strpos($realPath, $webeyRoot . DIRECTORY_SEPARATOR) === 0) {
                @unlink($realPath);
            }
        }
    }

    // Boş dizinleri temizle
    $subDir = 'staff_' . $staffId;
    foreach ([
        $webeyRoot . '/uploads/biz/'       . $bid . '/' . $subDir,
        $webeyRoot . '/uploads/optimized/' . $bid . '/' . $subDir,
    ] as $dir) {
        if (is_dir($dir) && count(glob("$dir/*") ?: []) === 0) @rmdir($dir);
    }

    try {
        $pdo->prepare('UPDATE staff SET photo_url = NULL, photo_opt = NULL WHERE id = ? AND business_id = ?')
            ->execute([$staffId, $bid]);
    } catch (PDOException) {
        // Kolon yoksa sessizce geç
    }

    wb_ok(['removed' => true]);

} catch (Throwable $e) {
    error_log('[staff/remove-photo] ' . $e->getMessage());
    wb_err('Fotoğraf silinemedi', 500, 'internal_error');
}