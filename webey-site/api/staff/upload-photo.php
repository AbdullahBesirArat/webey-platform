<?php
declare(strict_types=1);
/**
 * api/staff/upload-photo.php
 * POST (multipart/form-data) — Personel avatar yükle
 *
 * Form alanları:
 *   photo   — görsel dosya (jpeg/png/webp/gif, max 5MB)
 *   staffId — personel ID
 *
 * GD varsa: 200×200 WebP kare avatar üretir
 * GD yoksa: orijinali direkt kaydeder
 */

require_once __DIR__ . '/../admin/_bootstrap.php';
wb_method('POST');

$bid = $user['business_id'];
if (!$bid) wb_err('İşletme bulunamadı', 404, 'business_not_found');

$staffId = (int)($_POST['staffId'] ?? 0);
if (!$staffId) wb_err('staffId zorunlu', 400, 'missing_staff_id');

try {
    $chk = $pdo->prepare('SELECT id FROM staff WHERE id = ? AND business_id = ?');
    $chk->execute([$staffId, $bid]);
    if (!$chk->fetch()) wb_err('Personel bulunamadı', 403, 'forbidden');

    $file = $_FILES['photo'] ?? null;
    if (!$file || $file['error'] !== UPLOAD_ERR_OK) {
        $errMap = [
            UPLOAD_ERR_INI_SIZE   => 'Dosya sunucu limitini aştı',
            UPLOAD_ERR_FORM_SIZE  => 'Dosya form limitini aştı',
            UPLOAD_ERR_PARTIAL    => 'Dosya yarım yüklendi',
            UPLOAD_ERR_NO_FILE    => 'Dosya seçilmedi',
            UPLOAD_ERR_NO_TMP_DIR => 'Geçici dizin bulunamadı',
            UPLOAD_ERR_CANT_WRITE => 'Diske yazılamadı',
        ];
        wb_err($errMap[$file['error'] ?? -1] ?? 'Yükleme hatası', 400, 'upload_error');
    }

    $allowedMimes = ['image/jpeg', 'image/png', 'image/webp', 'image/gif'];
    $mime         = mime_content_type($file['tmp_name']);
    if (!in_array($mime, $allowedMimes, true)) wb_err('Sadece JPG, PNG, WEBP veya GIF desteklenir', 415, 'unsupported_mime');
    if ($file['size'] > 5 * 1024 * 1024)      wb_err('Dosya 5MB sınırını aşıyor', 413, 'file_too_large');

    $webeyRoot = realpath(__DIR__ . '/../..');
    $subDir    = 'staff_' . $staffId;
    $origDir   = $webeyRoot . '/uploads/biz/'       . $bid . '/' . $subDir . '/';
    $optDir    = $webeyRoot . '/uploads/optimized/' . $bid . '/' . $subDir . '/';

    foreach ([$origDir, $optDir] as $dir) {
        if (!is_dir($dir) && !mkdir($dir, 0775, true)) {
            wb_err('Klasör oluşturulamadı', 500, 'dir_error');
        }
    }

    $ext = match($mime) {
        'image/png'  => 'png',
        'image/webp' => 'webp',
        'image/gif'  => 'gif',
        default      => 'jpg',
    };

    foreach (glob($origDir . 'original.*') ?: [] as $old) @unlink($old);

    $origFile = $origDir . 'original.' . $ext;
    if (!move_uploaded_file($file['tmp_name'], $origFile)) wb_err('Dosya kaydedilemedi', 500, 'save_error');

    $origUrl = 'uploads/biz/' . $bid . '/' . $subDir . '/original.' . $ext;
    $optUrl  = null;
    $hasGD   = function_exists('imagecreatefromjpeg');

    // ── GD: 200×200 kare avatar ────────────────────────────────────────────
    if ($hasGD && $mime !== 'image/gif') {
        try {
            $src = match($mime) {
                'image/png'  => imagecreatefrompng($origFile),
                'image/webp' => function_exists('imagecreatefromwebp') ? imagecreatefromwebp($origFile) : false,
                default      => imagecreatefromjpeg($origFile),
            };

            if ($src) {
                $srcW     = imagesx($src);
                $srcH     = imagesy($src);
                $cropSize = min($srcW, $srcH);
                $cropX    = (int)(($srcW - $cropSize) / 2);
                $cropY    = (int)(($srcH - $cropSize) / 2);

                $dst = imagecreatetruecolor(200, 200);
                imagealphablending($dst, false);
                imagesavealpha($dst, true);
                imagefilledrectangle($dst, 0, 0, 200, 200, imagecolorallocatealpha($dst, 0, 0, 0, 127));
                imagecopyresampled($dst, $src, 0, 0, $cropX, $cropY, 200, 200, $cropSize, $cropSize);

                foreach (glob($optDir . 'avatar.*') ?: [] as $old) @unlink($old);

                if (function_exists('imagewebp')) {
                    imagewebp($dst, $optDir . 'avatar.webp', 82);
                    $optUrl = 'uploads/optimized/' . $bid . '/' . $subDir . '/avatar.webp';
                } else {
                    imagejpeg($dst, $optDir . 'avatar.jpg', 85);
                    $optUrl = 'uploads/optimized/' . $bid . '/' . $subDir . '/avatar.jpg';
                }

                imagedestroy($src);
                imagedestroy($dst);
            }
        } catch (Throwable $gdErr) {
            error_log('[staff/upload-photo] GD hata: ' . $gdErr->getMessage());
            $optUrl = null;
        }
    }

    $finalOptUrl = $optUrl ?? $origUrl;

    // ── DB güncelle ────────────────────────────────────────────────────────
    try {
        $pdo->query('SELECT photo_url FROM staff LIMIT 1');
    } catch (PDOException) {
        $pdo->exec('ALTER TABLE `staff` ADD COLUMN `photo_url` VARCHAR(500) DEFAULT NULL AFTER `color`');
        $pdo->exec('ALTER TABLE `staff` ADD COLUMN `photo_opt` VARCHAR(500) DEFAULT NULL AFTER `photo_url`');
    }

    $pdo->prepare('UPDATE staff SET photo_url = ?, photo_opt = ? WHERE id = ? AND business_id = ?')
        ->execute([$origUrl, $finalOptUrl, $staffId, $bid]);

    wb_ok([
        'url'    => $origUrl,
        'optUrl' => $finalOptUrl,
        'gdUsed' => $hasGD,
    ]);

} catch (Throwable $e) {
    error_log('[staff/upload-photo] ' . $e->getMessage());
    wb_err('Fotoğraf yüklenemedi', 500, 'internal_error');
}