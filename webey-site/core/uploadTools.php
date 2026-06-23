<?php
/*
 * Resim yükleme & optimize etme helper
 *
 * Klasör yapısı:
 *   /public_html/uploads/original/
 *   /public_html/uploads/optimized/
 */

require_once __DIR__ . '/response.php';

if (!function_exists('processImageUpload')) {
    /**
     * @param array $file  $_FILES['file'] içeriği
     * @return array
     *
     *  [
     *    "originalUrl"       => "...",
     *    "optimizedUrl"      => "...",
     *    "relativeOriginal"  => "original/xxx.jpg",
     *    "relativeOptimized" => "optimized/xxx.jpg",
     *    "cdnOptimizedUrl"   => "..."   // şimdilik optimizedUrl ile aynı
     *  ]
     */
    function processImageUpload(array $file): array
    {
        if ($file['error'] !== UPLOAD_ERR_OK) {
            jsonResponse(false, 'Dosya yüklenirken hata oluştu (code: ' . $file['error'] . ')', null, 400);
        }

        $tmpPath  = $file['tmp_name'];
        $mimeType = mime_content_type($tmpPath);

        $allowed = ['image/jpeg', 'image/png', 'image/webp'];
        if (!in_array($mimeType, $allowed, true)) {
            jsonResponse(false, 'Sadece JPEG, PNG veya WEBP yüklenebilir.', null, 400);
        }

        // Base upload klasörü
        $baseUploadDir = realpath(__DIR__ . '/../../uploads');
        if ($baseUploadDir === false) {
            // Klasör yoksa oluşturmaya çalış
            $root = __DIR__ . '/../../uploads';
            if (!is_dir($root) && !mkdir($root, 0775, true)) {
                jsonResponse(false, 'uploads klasörü oluşturulamadı.', null, 500);
            }
            $baseUploadDir = realpath($root);
        }

        $origDir = $baseUploadDir . '/original';
        $optDir  = $baseUploadDir . '/optimized';

        if (!is_dir($origDir)) mkdir($origDir, 0775, true);
        if (!is_dir($optDir))  mkdir($optDir, 0775, true);

        // Benzersiz isim
        $ext = '.jpg';
        if ($mimeType === 'image/png')  $ext = '.png';
        if ($mimeType === 'image/webp') $ext = '.webp';

        $filename = uniqid('img_', true) . $ext;

        $origPath = $origDir . '/' . $filename;
        $optPath  = $optDir  . '/' . $filename;

        // Orijinali kaydet
        if (!move_uploaded_file($tmpPath, $origPath)) {
            jsonResponse(false, 'Geçici dosya taşınamadı.', null, 500);
        }

        // ------------ OPTIMIZE (GD ile) ------------
        $maxWidth  = 800;
        $maxHeight = 800;
        $qualityJpg = 80; // 0-100

        switch ($mimeType) {
            case 'image/jpeg':
                $src = imagecreatefromjpeg($origPath);
                break;
            case 'image/png':
                $src = imagecreatefrompng($origPath);
                break;
            case 'image/webp':
                $src = imagecreatefromwebp($origPath);
                break;
            default:
                $src = null;
        }

        if (!$src) {
            jsonResponse(false, 'Görsel okunamadı.', null, 500);
        }

        $w = imagesx($src);
        $h = imagesy($src);

        $ratio = min($maxWidth / $w, $maxHeight / $h, 1); // büyütme yok
        $newW = (int)floor($w * $ratio);
        $newH = (int)floor($h * $ratio);

        $dst = imagecreatetruecolor($newW, $newH);

        // PNG / WEBP için şeffaflık
        if ($mimeType === 'image/png' || $mimeType === 'image/webp') {
            imagealphablending($dst, false);
            imagesavealpha($dst, true);
            $transparent = imagecolorallocatealpha($dst, 0, 0, 0, 127);
            imagefilledrectangle($dst, 0, 0, $newW, $newH, $transparent);
        }

        imagecopyresampled($dst, $src, 0, 0, 0, 0, $newW, $newH, $w, $h);

        // Dosyaya yaz
        $ok = false;
        if ($mimeType === 'image/jpeg') {
            $ok = imagejpeg($dst, $optPath, $qualityJpg);
        } elseif ($mimeType === 'image/png') {
            // 0 (en iyi)–9 (en kötü) => kaliteyi 2-3 gibi tut
            $ok = imagepng($dst, $optPath, 3);
        } elseif ($mimeType === 'image/webp') {
            $ok = imagewebp($dst, $optPath, 80);
        }

        imagedestroy($src);
        imagedestroy($dst);

        if (!$ok) {
            jsonResponse(false, 'Optimize görsel yazılamadı.', null, 500);
        }

        // URL üret
        $scheme = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ? 'https' : 'http';
        $host   = $_SERVER['HTTP_HOST'] ?? 'webey.com.tr';
        $baseUrl = $scheme . '://' . $host;

        $relativeOriginal  = 'original/'  . $filename;
        $relativeOptimized = 'optimized/' . $filename;

        $originalUrl  = $baseUrl . '/uploads/' . $relativeOriginal;
        $optimizedUrl = $baseUrl . '/uploads/' . $relativeOptimized;

        // Şimdilik CDN yoksa optimizedUrl ile aynı
        $cdnOptimizedUrl = $optimizedUrl;

        return [
            "originalUrl"       => $originalUrl,
            "optimizedUrl"      => $optimizedUrl,
            "relativeOriginal"  => $relativeOriginal,
            "relativeOptimized" => $relativeOptimized,
            "cdnOptimizedUrl"   => $cdnOptimizedUrl,
        ];
    }
}
