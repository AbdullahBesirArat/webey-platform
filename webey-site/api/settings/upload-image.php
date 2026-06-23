<?php
declare(strict_types=1);
/**
 * api/settings/upload-image.php
 * POST (multipart/form-data) - Isletme gorseli yukle
 *
 * Beklenen form alanlari:
 *   file  - gorsel dosya (jpeg/png/webp/gif/heic, max 10MB)
 *   kind  - "cover" | "salon" | "model"
 *
 * NOT: CSRF token X-CSRF-Token header'i olarak gonderilmeli
 *      (wb-api-shim.js'deki apiUpload bunu otomatik ekler)
 */

require_once __DIR__ . '/../admin/_bootstrap.php';
wb_method('POST');

const WB_MAX_TOTAL_IMAGES = 10;
const WB_MAX_NON_COVER_IMAGES = 9;

function wb_detect_uploaded_image(array $file): ?array
{
    $mimeCandidates = [];

    if (!empty($file['tmp_name']) && is_file($file['tmp_name'])) {
        if (class_exists('finfo')) {
            $finfoMime = (new finfo(FILEINFO_MIME_TYPE))->file($file['tmp_name']);
            if (is_string($finfoMime) && $finfoMime !== '') {
                $mimeCandidates[] = strtolower($finfoMime);
            }
        }

        $fallbackMime = @mime_content_type($file['tmp_name']);
        if (is_string($fallbackMime) && $fallbackMime !== '') {
            $mimeCandidates[] = strtolower($fallbackMime);
        }
    }

    $clientMime = strtolower(trim((string)($file['type'] ?? '')));
    if ($clientMime !== '') {
        $mimeCandidates[] = $clientMime;
    }

    $ext = strtolower(pathinfo((string)($file['name'] ?? ''), PATHINFO_EXTENSION));

    $mimeToFormat = [
        'image/jpeg' => 'jpeg',
        'image/jpg' => 'jpeg',
        'image/pjpeg' => 'jpeg',
        'image/png' => 'png',
        'image/webp' => 'webp',
        'image/gif' => 'gif',
        'image/heic' => 'heic',
        'image/heif' => 'heic',
        'image/heic-sequence' => 'heic',
        'image/heif-sequence' => 'heic',
    ];

    foreach ($mimeCandidates as $mime) {
        if (isset($mimeToFormat[$mime])) {
            return [
                'format' => $mimeToFormat[$mime],
                'mime' => $mime,
                'extension' => $ext,
            ];
        }
    }

    $extToFormat = [
        'jpg' => 'jpeg',
        'jpeg' => 'jpeg',
        'png' => 'png',
        'webp' => 'webp',
        'gif' => 'gif',
        'heic' => 'heic',
        'heif' => 'heic',
    ];

    if (isset($extToFormat[$ext])) {
        return [
            'format' => $extToFormat[$ext],
            'mime' => '',
            'extension' => $ext,
        ];
    }

    return null;
}

function wb_convert_heic_upload_to_jpeg(string $sourcePath, string $targetPath): void
{
    if (!class_exists('Imagick')) {
        wb_err(
            'Telefonunuzun cektigi HEIC/HEIF formatini sunucu su an donusturemiyor. Kameradan "En Uyumlu/JPEG" formatinda tekrar deneyin.',
            415,
            'unsupported_mime'
        );
    }

    try {
        $imagick = new Imagick();
        $imagick->readImage($sourcePath);
        $imagick->setIteratorIndex(0);

        $frame = $imagick->getImage();
        $frame->autoOrient();
        $frame->setImageFormat('jpeg');
        $frame->setImageCompressionQuality(88);
        $frame->stripImage();

        if (!$frame->writeImage($targetPath)) {
            throw new RuntimeException('write_failed');
        }

        $frame->clear();
        $frame->destroy();
        $imagick->clear();
        $imagick->destroy();
    } catch (Throwable $e) {
        error_log('[settings/upload-image] HEIC conversion failed: ' . $e->getMessage());
        wb_err('Telefon fotografi donusumu basarisiz oldu. JPEG veya PNG ile tekrar deneyin.', 415, 'unsupported_mime');
    }
}

function wb_auto_orient_jpeg(string $path): void
{
    if (!function_exists('exif_read_data') || !function_exists('imagecreatefromjpeg')) {
        return;
    }

    $exif = @exif_read_data($path);
    $orientation = (int)($exif['Orientation'] ?? 1);
    if (!in_array($orientation, [3, 6, 8], true)) {
        return;
    }

    $src = @imagecreatefromjpeg($path);
    if (!$src) {
        return;
    }

    $angle = match ($orientation) {
        3 => 180,
        6 => -90,
        8 => 90,
        default => 0,
    };

    if ($angle !== 0) {
        $rotated = imagerotate($src, $angle, 0);
        if ($rotated !== false) {
            imagejpeg($rotated, $path, 90);
            imagedestroy($rotated);
        }
    }

    imagedestroy($src);
}

$bid = $user['business_id'];
if (!$bid) {
    wb_err('Isletme bulunamadi', 404, 'business_not_found');
}

$kind = trim((string)($_POST['kind'] ?? ''));
$allowed = ['cover', 'salon', 'model'];
if (!in_array($kind, $allowed, true)) {
    wb_err('Gecersiz kind degeri. Olasi degerler: ' . implode(', ', $allowed), 400, 'invalid_kind');
}

$file = $_FILES['file'] ?? null;
if (!$file || $file['error'] !== UPLOAD_ERR_OK) {
    $errMap = [
        UPLOAD_ERR_INI_SIZE => 'Dosya sunucu limitini asiyor',
        UPLOAD_ERR_FORM_SIZE => 'Dosya form limitini asiyor',
        UPLOAD_ERR_PARTIAL => 'Dosya kismen yuklendi',
        UPLOAD_ERR_NO_FILE => 'Dosya secilmedi',
        UPLOAD_ERR_NO_TMP_DIR => 'Gecici dizin bulunamadi',
        UPLOAD_ERR_CANT_WRITE => 'Dosya yazilamadi',
        UPLOAD_ERR_EXTENSION => 'PHP uzantisi yuklemeyi engelledi',
    ];
    $msg = $errMap[$file['error'] ?? -1] ?? 'Yukleme hatasi';
    wb_err($msg, 400, 'upload_error');
}

$imageInfo = wb_detect_uploaded_image($file);
if (!$imageInfo) {
    wb_err('Desteklenmeyen dosya tipi. Izin verilenler: JPEG, PNG, WebP, GIF, HEIC', 415, 'unsupported_mime');
}

if (($file['size'] ?? 0) > 10 * 1024 * 1024) {
    wb_err('Dosya 10MB sinirini asiyor', 413, 'file_too_large');
}

try {
    $webeyRoot = realpath(__DIR__ . '/../..');
    $uploadDir = $webeyRoot . '/uploads/biz/' . $bid . '/';
    if (!is_dir($uploadDir)) {
        mkdir($uploadDir, 0775, true);
    }

    $sourceFormat = $imageInfo['format'];
    $sourceMime = match ($sourceFormat) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        'gif' => 'image/gif',
        default => 'image/jpeg',
    };
    $ext = match ($sourceFormat) {
        'png' => 'png',
        'webp' => 'webp',
        'gif' => 'gif',
        default => 'jpg',
    };

    $filename = $kind . '_' . uniqid() . '.' . $ext;
    $target = $uploadDir . $filename;

    if ($sourceFormat === 'heic') {
        wb_convert_heic_upload_to_jpeg($file['tmp_name'], $target);
    } elseif (!move_uploaded_file($file['tmp_name'], $target)) {
        wb_err('Dosya kaydedilemedi', 500, 'save_error');
    }

    if ($sourceMime === 'image/jpeg') {
        wb_auto_orient_jpeg($target);
    }

    $url = 'uploads/biz/' . $bid . '/' . $filename;
    $optUrl = null;

    // cover  -> max 1400x934 WebP q84
    // salon/model -> max 1600x1200 WebP q82
    if (function_exists('imagecreatefromjpeg') && $sourceMime !== 'image/gif') {
        try {
            $src = match ($sourceMime) {
                'image/png' => imagecreatefrompng($target),
                'image/webp' => function_exists('imagecreatefromwebp') ? imagecreatefromwebp($target) : false,
                default => imagecreatefromjpeg($target),
            };

            if ($src) {
                $srcW = imagesx($src);
                $srcH = imagesy($src);
                [$maxW, $maxH, $quality] = $kind === 'cover' ? [1400, 934, 84] : [1600, 1200, 82];

                $ratio = min($maxW / $srcW, $maxH / $srcH, 1.0);
                $newW = max(1, (int) floor($srcW * $ratio));
                $newH = max(1, (int) floor($srcH * $ratio));

                $dst = imagecreatetruecolor($newW, $newH);
                imagealphablending($dst, false);
                imagesavealpha($dst, true);
                imagefilledrectangle($dst, 0, 0, $newW, $newH, imagecolorallocatealpha($dst, 255, 255, 255, 0));
                imagecopyresampled($dst, $src, 0, 0, 0, 0, $newW, $newH, $srcW, $srcH);

                $optFilename = 'opt_' . pathinfo($filename, PATHINFO_FILENAME) . '.webp';
                $optTarget = $uploadDir . $optFilename;

                if (function_exists('imagewebp') && imagewebp($dst, $optTarget, $quality)) {
                    $optUrl = 'uploads/biz/' . $bid . '/' . $optFilename;
                } elseif (imagejpeg($dst, $optTarget . '.jpg', $quality)) {
                    $optUrl = 'uploads/biz/' . $bid . '/' . $optFilename . '.jpg';
                }

                imagedestroy($src);
                imagedestroy($dst);
            }
        } catch (Throwable $gdErr) {
            error_log('[settings/upload-image] GD hata: ' . $gdErr->getMessage());
            $optUrl = null;
        }
    }

    $stmt = $pdo->prepare('SELECT images_json FROM businesses WHERE id = ?');
    $stmt->execute([$bid]);
    $row = $stmt->fetch();
    $images = json_decode($row['images_json'] ?? 'null', true) ?: ['cover' => [], 'salon' => [], 'model' => []];

    $coverCount = is_array($images['cover'] ?? null) ? count(array_filter($images['cover'])) : 0;
    $salonCount = is_array($images['salon'] ?? null) ? count(array_filter($images['salon'])) : 0;
    $modelCount = is_array($images['model'] ?? null) ? count(array_filter($images['model'])) : 0;
    $nonCoverCount = $salonCount + $modelCount;
    $totalCount = $coverCount + $nonCoverCount;

    if ($kind !== 'cover' && $nonCoverCount >= WB_MAX_NON_COVER_IMAGES) {
        if (file_exists($target)) {
            @unlink($target);
        }
        if ($optUrl) {
            $cleanOpt = ltrim(preg_replace('#^(/[^/]+)?/uploads/#', 'uploads/', (string)$optUrl), '/');
            $optPath = $webeyRoot . '/' . $cleanOpt;
            if (file_exists($optPath)) {
                @unlink($optPath);
            }
        }
        wb_err('En fazla 10 gorsel yukleyebilirsiniz: 1 kapak + 9 diger gorsel.', 400, 'image_limit_reached');
    }

    if ($kind === 'cover' && $coverCount >= 1) {
        $totalCount -= 1;
    }
    if ($totalCount >= WB_MAX_TOTAL_IMAGES && $kind !== 'cover') {
        if (file_exists($target)) {
            @unlink($target);
        }
        if ($optUrl) {
            $cleanOpt = ltrim(preg_replace('#^(/[^/]+)?/uploads/#', 'uploads/', (string)$optUrl), '/');
            $optPath = $webeyRoot . '/' . $cleanOpt;
            if (file_exists($optPath)) {
                @unlink($optPath);
            }
        }
        wb_err('En fazla 10 gorsel yukleyebilirsiniz: 1 kapak + 9 diger gorsel.', 400, 'image_limit_reached');
    }

    $optKey = $kind . '_opt';

    if ($kind === 'cover') {
        $toDelete = array_merge(
            is_array($images['cover'] ?? null) ? $images['cover'] : [],
            is_array($images['cover_opt'] ?? null) ? $images['cover_opt'] : []
        );

        foreach ($toDelete as $oldUrl) {
            $clean = ltrim(preg_replace('#^(/[^/]+)?/uploads/#', 'uploads/', (string) $oldUrl), '/');
            $oldPath = $webeyRoot . '/' . $clean;
            if ($oldPath !== $target && file_exists($oldPath)) {
                @unlink($oldPath);
            }
        }

        $images['cover'] = [$url];
        $images['cover_opt'] = $optUrl ? [$optUrl] : [];
    } else {
        if (!is_array($images[$kind] ?? null)) {
            $images[$kind] = [];
        }
        if (!is_array($images[$optKey] ?? null)) {
            $images[$optKey] = [];
        }

        $images[$kind][] = $url;
        if ($optUrl) {
            $images[$optKey][] = $optUrl;
        }
    }

    $pdo->prepare('UPDATE businesses SET images_json = ?, updated_at = NOW() WHERE id = ?')
        ->execute([json_encode($images), $bid]);

    wb_ok([
        'url' => $url,
        'optUrl' => $optUrl ?? $url,
        'kind' => $kind,
        'images' => $images,
    ]);
} catch (Throwable $e) {
    error_log('[settings/upload-image] ' . $e->getMessage());
    wb_err('Gorsel yuklenemedi', 500, 'internal_error');
}
