<?php
declare(strict_types=1);

const WB_GALLERY_QUOTA_LIMIT = 20;
const WB_GALLERY_MAX_UPLOAD_BYTES = 10485760;
const WB_GALLERY_MAX_DIMENSION = 8000;

if (!function_exists('mobile_gallery_categories')) {
    function mobile_gallery_categories(): array
    {
        return [
            'cover' => ['label' => 'Kapak', 'limit' => 1],
            'logo' => ['label' => 'Logo', 'limit' => 1],
            'interior' => ['label' => 'İç Mekan', 'limit' => 12],
            'exterior' => ['label' => 'Dış Mekan', 'limit' => 6],
            'hair_work' => ['label' => 'Saç Çalışmaları', 'limit' => 24],
            'hair_color' => ['label' => 'Saç Renk', 'limit' => 24],
            'nail_work' => ['label' => 'Tırnak', 'limit' => 24],
            'makeup' => ['label' => 'Makyaj', 'limit' => 24],
            'skincare' => ['label' => 'Cilt Bakımı', 'limit' => 18],
            'lash_brow' => ['label' => 'Kaş & Kirpik', 'limit' => 18],
            'before_after' => ['label' => 'Öncesi-Sonrası', 'limit' => 40],
            'team' => ['label' => 'Ekip', 'limit' => 12],
            'certificate' => ['label' => 'Sertifika', 'limit' => 6],
            'campaign' => ['label' => 'Kampanya', 'limit' => 6],
        ];
    }

    function mobile_gallery_category_label(string $category): string
    {
        $categories = mobile_gallery_categories();
        return (string)($categories[$category]['label'] ?? $category);
    }

    function mobile_gallery_table_exists(PDO $pdo): bool
    {
        static $exists = null;
        if ($exists !== null) {
            return $exists;
        }
        try {
            $stmt = $pdo->query("SHOW TABLES LIKE 'business_photos'");
            $exists = (bool)$stmt->fetchColumn();
        } catch (Throwable $e) {
            error_log('[mobile_gallery_table_exists] ' . $e->getMessage());
            $exists = false;
        }
        return $exists;
    }

    function mobile_gallery_require_table(PDO $pdo): void
    {
        if (!mobile_gallery_table_exists($pdo)) {
            wb_err('Galeri tablosu hazır değil. Migration uygulanmalı.', 500, 'migration_required');
        }
    }

    function mobile_gallery_validate_category(string $category): string
    {
        $category = trim($category);
        if (!isset(mobile_gallery_categories()[$category])) {
            wb_err('Geçersiz galeri kategorisi', 422, 'validation_error');
        }
        return $category;
    }

    function mobile_gallery_nullable_int(mixed $value): ?int
    {
        if ($value === null || $value === '') {
            return null;
        }
        $int = filter_var($value, FILTER_VALIDATE_INT);
        return $int === false || $int <= 0 ? null : (int)$int;
    }

    function mobile_gallery_normalize_status(mixed $value, bool $isVisible = true): string
    {
        $status = trim((string)($value ?? ''));
        if ($status === '') {
            return $isVisible ? 'active' : 'hidden';
        }
        if (!in_array($status, ['active', 'hidden', 'flagged', 'deleted'], true)) {
            wb_err('Geçersiz fotoğraf durumu', 422, 'validation_error');
        }
        return $status;
    }

    function mobile_gallery_public_url(?string $path): ?string
    {
        $path = trim((string)$path);
        if ($path === '') {
            return null;
        }
        return $path;
    }

    function mobile_gallery_item(array $row): array
    {
        $category = (string)($row['category'] ?? '');
        $thumb = mobile_gallery_public_url($row['thumb_path'] ?? null);
        $medium = mobile_gallery_public_url($row['medium_path'] ?? null);
        $large = mobile_gallery_public_url($row['large_path'] ?? null);
        $original = mobile_gallery_public_url($row['original_path'] ?? null);

        return [
            'id' => (string)$row['id'],
            'business_id' => (string)$row['business_id'],
            'category' => $category,
            'category_label' => mobile_gallery_category_label($category),
            'title' => $row['title'] ?? null,
            'description' => $row['description'] ?? null,
            'service_id' => $row['service_id'] !== null ? (int)$row['service_id'] : null,
            'staff_id' => $row['staff_id'] !== null ? (int)$row['staff_id'] : null,
            'pair_group_id' => $row['pair_group_id'] ?? null,
            'pair_role' => $row['pair_role'] ?? null,
            'url' => $large ?? $medium ?? $original,
            'thumb_url' => $thumb ?? $medium ?? $original,
            'medium_url' => $medium ?? $large ?? $original,
            'large_url' => $large ?? $medium ?? $original,
            'original_url' => $original,
            'width' => $row['width'] !== null ? (int)$row['width'] : null,
            'height' => $row['height'] !== null ? (int)$row['height'] : null,
            'bytes' => $row['bytes'] !== null ? (int)$row['bytes'] : null,
            'is_cover' => (bool)($row['is_cover'] ?? false),
            'is_visible' => (bool)($row['is_visible'] ?? true),
            'status' => (string)($row['status'] ?? 'active'),
            'sort_order' => (int)($row['sort_order'] ?? 0),
            'created_at' => $row['created_at'] ?? null,
            'updated_at' => $row['updated_at'] ?? null,
        ];
    }

    function mobile_gallery_count(PDO $pdo, int $businessId, ?string $category = null): int
    {
        $sql = "SELECT COUNT(*) FROM business_photos
                WHERE business_id = ? AND status <> 'deleted'";
        $params = [$businessId];
        if ($category !== null) {
            $sql .= ' AND category = ?';
            $params[] = $category;
        }
        $stmt = $pdo->prepare($sql);
        $stmt->execute($params);
        return (int)$stmt->fetchColumn();
    }

    function mobile_gallery_limits_payload(PDO $pdo, int $businessId): array
    {
        $counts = [];
        if (mobile_gallery_table_exists($pdo)) {
            $stmt = $pdo->prepare("
                SELECT category, COUNT(*) AS cnt
                FROM business_photos
                WHERE business_id = ? AND status <> 'deleted'
                GROUP BY category
            ");
            $stmt->execute([$businessId]);
            foreach ($stmt->fetchAll() as $row) {
                $counts[(string)$row['category']] = (int)$row['cnt'];
            }
        }

        $items = [];
        foreach (mobile_gallery_categories() as $key => $meta) {
            $items[] = [
                'key' => $key,
                'label' => $meta['label'],
                'count' => $counts[$key] ?? 0,
                'limit' => $meta['limit'],
            ];
        }
        return $items;
    }

    function mobile_gallery_assert_quota(PDO $pdo, int $businessId, string $category, ?int $excludeId = null, bool $forUpdate = false): void
    {
        $lockSuffix = $forUpdate ? ' FOR UPDATE' : '';
        $totalSql = "SELECT id FROM business_photos
                     WHERE business_id = ? AND status <> 'deleted'";
        $totalParams = [$businessId];
        $catSql = $totalSql . ' AND category = ?';
        $catParams = [$businessId, $category];
        if ($excludeId !== null) {
            $totalSql .= ' AND id <> ?';
            $totalParams[] = $excludeId;
            $catSql .= ' AND id <> ?';
            $catParams[] = $excludeId;
        }

        $stmt = $pdo->prepare($totalSql . $lockSuffix);
        $stmt->execute($totalParams);
        if (count($stmt->fetchAll()) >= WB_GALLERY_QUOTA_LIMIT) {
            wb_err('Fotoğraf kotanız doldu. Yeni fotoğraf eklemek için mevcut bir fotoğrafı kaldırın.', 422, 'quota_exceeded');
        }

        $stmt = $pdo->prepare($catSql . $lockSuffix);
        $stmt->execute($catParams);
        $limit = (int)(mobile_gallery_categories()[$category]['limit'] ?? 0);
        if ($limit > 0 && count($stmt->fetchAll()) >= $limit) {
            wb_err('Bu kategori için fotoğraf limiti doldu', 422, 'category_limit_exceeded');
        }
    }

    function mobile_gallery_assert_service(PDO $pdo, int $businessId, ?int $serviceId): void
    {
        if ($serviceId === null) {
            return;
        }
        $stmt = $pdo->prepare('SELECT id FROM services WHERE id = ? AND business_id = ? LIMIT 1');
        $stmt->execute([$serviceId, $businessId]);
        if (!$stmt->fetch()) {
            wb_err('Hizmet bulunamadı', 422, 'validation_error');
        }
    }

    function mobile_gallery_assert_staff(PDO $pdo, int $businessId, ?int $staffId): void
    {
        if ($staffId === null) {
            return;
        }
        $stmt = $pdo->prepare('SELECT id FROM staff WHERE id = ? AND business_id = ? LIMIT 1');
        $stmt->execute([$staffId, $businessId]);
        if (!$stmt->fetch()) {
            wb_err('Personel bulunamadı', 422, 'validation_error');
        }
    }

    function mobile_gallery_fetch_photo(PDO $pdo, int $businessId, int $id, bool $forUpdate = false): array
    {
        if ($id <= 0) {
            wb_err('id zorunlu', 400, 'bad_request');
        }
        $stmt = $pdo->prepare(
            'SELECT * FROM business_photos WHERE id = ? AND business_id = ? AND status <> ? LIMIT 1'
            . ($forUpdate ? ' FOR UPDATE' : '')
        );
        $stmt->execute([$id, $businessId, 'deleted']);
        $row = $stmt->fetch();
        if (!$row) {
            wb_err('Fotoğraf bulunamadı', 404, 'not_found');
        }
        return $row;
    }

    function mobile_gallery_detect_upload(array $file): array
    {
        if (($file['error'] ?? UPLOAD_ERR_NO_FILE) !== UPLOAD_ERR_OK) {
            $map = [
                UPLOAD_ERR_INI_SIZE => 'Dosya sunucu limitini aşıyor',
                UPLOAD_ERR_FORM_SIZE => 'Dosya form limitini aşıyor',
                UPLOAD_ERR_PARTIAL => 'Dosya kısmen yüklendi',
                UPLOAD_ERR_NO_FILE => 'Dosya seçilmedi',
                UPLOAD_ERR_NO_TMP_DIR => 'Geçici dizin bulunamadı',
                UPLOAD_ERR_CANT_WRITE => 'Dosya yazılamadı',
                UPLOAD_ERR_EXTENSION => 'PHP uzantısı yüklemeyi engelledi',
            ];
            wb_err($map[$file['error'] ?? -1] ?? 'Yükleme hatası', 400, 'upload_error');
        }
        if (($file['size'] ?? 0) > WB_GALLERY_MAX_UPLOAD_BYTES) {
            wb_err('Dosya 10MB sınırını aşıyor', 413, 'file_too_large');
        }

        $tmp = (string)($file['tmp_name'] ?? '');
        if ($tmp === '' || !is_file($tmp)) {
            wb_err('Yükleme dosyası okunamadı', 400, 'upload_error');
        }

        $mime = '';
        if (class_exists('finfo')) {
            $detected = (new finfo(FILEINFO_MIME_TYPE))->file($tmp);
            $mime = is_string($detected) ? strtolower($detected) : '';
        }
        if ($mime === '') {
            $detected = @mime_content_type($tmp);
            $mime = is_string($detected) ? strtolower($detected) : '';
        }

        $map = [
            'image/jpeg' => 'jpeg',
            'image/jpg' => 'jpeg',
            'image/png' => 'png',
            'image/webp' => 'webp',
            'image/heic' => 'heic',
            'image/heif' => 'heic',
            'image/heic-sequence' => 'heic',
            'image/heif-sequence' => 'heic',
        ];
        if (!isset($map[$mime])) {
            wb_err('Desteklenmeyen dosya tipi', 415, 'unsupported_media_type');
        }
        if ($map[$mime] === 'heic' && !class_exists('Imagick')) {
            wb_err('HEIC formatı bu sunucuda desteklenmiyor. JPEG/PNG/WebP deneyin.', 415, 'unsupported_media_type');
        }

        if ($map[$mime] === 'heic') {
            try {
                $probe = new Imagick();
                $probe->pingImage($tmp);
                $size = [$probe->getImageWidth(), $probe->getImageHeight()];
                $probe->clear();
                $probe->destroy();
            } catch (Throwable $e) {
                error_log('[mobile_gallery_detect_upload_heic] ' . $e->getMessage());
                wb_err('HEIC görsel doğrulanamadı', 415, 'unsupported_media_type');
            }
        } else {
            $size = @getimagesize($tmp);
        }
        if (!is_array($size) || empty($size[0]) || empty($size[1])) {
            wb_err('Görsel doğrulanamadı', 415, 'unsupported_media_type');
        }
        $width = (int)($size[0] ?? 0);
        $height = (int)($size[1] ?? 0);
        if (($width > WB_GALLERY_MAX_DIMENSION) || ($height > WB_GALLERY_MAX_DIMENSION)) {
            wb_err('Görsel çözünürlüğü çok yüksek', 422, 'validation_error');
        }

        return [
            'tmp' => $tmp,
            'mime' => $mime,
            'format' => $map[$mime],
            'width' => $width,
            'height' => $height,
            'bytes' => (int)($file['size'] ?? 0),
        ];
    }

    function mobile_gallery_storage_dir(int $businessId): array
    {
        $root = realpath(__DIR__ . '/../../..');
        if (!$root) {
            wb_err('Dosya sistemi hazırlanamadı', 500, 'server_error');
        }
        $month = date('Ym');
        $relativeDir = 'uploads/biz/' . $businessId . '/photos/' . $month;
        $absoluteDir = $root . '/' . $relativeDir;
        if (!is_dir($absoluteDir) && !mkdir($absoluteDir, 0775, true)) {
            wb_err('Upload klasörü oluşturulamadı', 500, 'server_error');
        }
        $real = realpath($absoluteDir);
        $uploadsRoot = realpath($root . '/uploads');
        if (!$real || !$uploadsRoot || strpos($real, $uploadsRoot) !== 0) {
            wb_err('Upload klasörü güvenli değil', 500, 'server_error');
        }
        return [$absoluteDir, $relativeDir];
    }

    function mobile_gallery_random_base(): string
    {
        return bin2hex(random_bytes(16));
    }

    function mobile_gallery_gd_source(string $path, string $format)
    {
        if ($format === 'png') {
            return function_exists('imagecreatefrompng') ? @imagecreatefrompng($path) : false;
        }
        if ($format === 'webp') {
            return function_exists('imagecreatefromwebp') ? @imagecreatefromwebp($path) : false;
        }
        return function_exists('imagecreatefromjpeg') ? @imagecreatefromjpeg($path) : false;
    }

    function mobile_gallery_auto_orient_jpeg($src, string $path)
    {
        if (!function_exists('exif_read_data')) {
            return $src;
        }
        $exif = @exif_read_data($path);
        $orientation = (int)($exif['Orientation'] ?? 1);
        $angle = 0;
        if ($orientation === 3) {
            $angle = 180;
        } elseif ($orientation === 6) {
            $angle = -90;
        } elseif ($orientation === 8) {
            $angle = 90;
        }
        if ($angle === 0) {
            return $src;
        }
        $rotated = @imagerotate($src, $angle, 0);
        if ($rotated) {
            imagedestroy($src);
            return $rotated;
        }
        return $src;
    }

    function mobile_gallery_resize_gd(string $source, string $format, string $targetBase, int $maxSide, int $quality): ?string
    {
        $src = mobile_gallery_gd_source($source, $format);
        if (!$src) {
            return null;
        }
        if ($format === 'jpeg') {
            $src = mobile_gallery_auto_orient_jpeg($src, $source);
        }
        $srcW = imagesx($src);
        $srcH = imagesy($src);
        if ($srcW <= 0 || $srcH <= 0) {
            imagedestroy($src);
            return null;
        }
        $ratio = min($maxSide / max($srcW, $srcH), 1.0);
        $newW = max(1, (int)floor($srcW * $ratio));
        $newH = max(1, (int)floor($srcH * $ratio));
        $dst = imagecreatetruecolor($newW, $newH);
        imagealphablending($dst, false);
        imagesavealpha($dst, true);
        imagefilledrectangle($dst, 0, 0, $newW, $newH, imagecolorallocatealpha($dst, 255, 255, 255, 0));
        imagecopyresampled($dst, $src, 0, 0, 0, 0, $newW, $newH, $srcW, $srcH);

        $written = null;
        if (function_exists('imagewebp') && @imagewebp($dst, $targetBase . '.webp', $quality)) {
            $written = $targetBase . '.webp';
        } elseif (@imagejpeg($dst, $targetBase . '.jpg', $quality)) {
            $written = $targetBase . '.jpg';
        }
        imagedestroy($src);
        imagedestroy($dst);
        return $written;
    }

    function mobile_gallery_resize_imagick(string $source, string $targetBase, int $maxSide, int $quality): ?string
    {
        if (!class_exists('Imagick')) {
            return null;
        }
        try {
            $img = new Imagick();
            $img->readImage($source);
            $img->setIteratorIndex(0);
            if (method_exists($img, 'autoOrient')) {
                $img->autoOrient();
            } elseif (method_exists($img, 'autoOrientImage')) {
                $img->autoOrientImage();
            }
            $w = $img->getImageWidth();
            $h = $img->getImageHeight();
            if (max($w, $h) > $maxSide) {
                $img->thumbnailImage($maxSide, $maxSide, true, true);
            }
            $img->stripImage();
            $img->setImageCompressionQuality($quality);
            $target = $targetBase . '.webp';
            try {
                $img->setImageFormat('webp');
                $img->writeImage($target);
            } catch (Throwable $fallbackError) {
                $target = $targetBase . '.jpg';
                $img->setImageFormat('jpeg');
                $img->writeImage($target);
            }
            $img->clear();
            $img->destroy();
            return $target;
        } catch (Throwable $e) {
            error_log('[mobile_gallery_resize_imagick] ' . $e->getMessage());
            return null;
        }
    }

    function mobile_gallery_process_upload(array $file, int $businessId): array
    {
        $info = mobile_gallery_detect_upload($file);
        [$absoluteDir, $relativeDir] = mobile_gallery_storage_dir($businessId);
        $base = mobile_gallery_random_base();

        $format = $info['format'];
        if ($format === 'png') {
            $origExt = 'png';
        } elseif ($format === 'webp') {
            $origExt = 'webp';
        } else {
            $origExt = 'jpg';
        }
        $originalPath = $absoluteDir . '/' . $base . '_original.' . $origExt;

        if ($format === 'heic') {
            $converted = mobile_gallery_resize_imagick($info['tmp'], $absoluteDir . '/' . $base . '_original', WB_GALLERY_MAX_DIMENSION, 88);
            if (!$converted) {
                wb_err('HEIC görsel dönüştürülemedi', 415, 'unsupported_media_type');
            }
            $originalPath = $converted;
            $format = substr($converted, -5) === '.webp' ? 'webp' : 'jpeg';
        } elseif (!move_uploaded_file($info['tmp'], $originalPath)) {
            wb_err('Dosya kaydedilemedi', 500, 'server_error');
        }

        $dim = @getimagesize($originalPath);
        $width = is_array($dim) ? (int)$dim[0] : $info['width'];
        $height = is_array($dim) ? (int)$dim[1] : $info['height'];

        $variants = [];
        foreach ([
            'thumb' => [320, 78],
            'medium' => [1080, 82],
            'large' => [1600, 82],
        ] as $name => [$maxSide, $quality]) {
            $targetBase = $absoluteDir . '/' . $base . '_' . $name;
            $written = mobile_gallery_resize_imagick($originalPath, $targetBase, $maxSide, $quality)
                ?? mobile_gallery_resize_gd($originalPath, $format, $targetBase, $maxSide, $quality);
            if ($written) {
                $variants[$name] = $relativeDir . '/' . basename($written);
            }
        }
        if ($variants === []) {
            @unlink($originalPath);
            wb_err('Görsel optimize edilemedi', 500, 'server_error');
        }

        return [
            'original_path' => $relativeDir . '/' . basename($originalPath),
            'thumb_path' => $variants['thumb'] ?? null,
            'medium_path' => $variants['medium'] ?? null,
            'large_path' => $variants['large'] ?? null,
            'width' => $width,
            'height' => $height,
            'bytes' => filesize($originalPath) ?: $info['bytes'],
        ];
    }

    function mobile_gallery_cover_from_table(PDO $pdo, int $businessId): ?array
    {
        if (!mobile_gallery_table_exists($pdo)) {
            return null;
        }
        try {
            $stmt = $pdo->prepare("
                SELECT *
                FROM business_photos
                WHERE business_id = ?
                  AND status = 'active'
                  AND is_visible = 1
                  AND is_cover = 1
                ORDER BY sort_order ASC, id DESC
                LIMIT 1
            ");
            $stmt->execute([$businessId]);
            $row = $stmt->fetch();
            return $row ? mobile_gallery_item($row) : null;
        } catch (Throwable $e) {
            error_log('[mobile_gallery_cover_from_table] ' . $e->getMessage());
            return null;
        }
    }

    function mobile_gallery_public_items(PDO $pdo, int $businessId): array
    {
        if (!mobile_gallery_table_exists($pdo)) {
            return [];
        }
        try {
            $stmt = $pdo->prepare("
                SELECT *
                FROM business_photos
                WHERE business_id = ?
                  AND status = 'active'
                  AND is_visible = 1
                ORDER BY is_cover DESC, category ASC, sort_order ASC, id DESC
            ");
            $stmt->execute([$businessId]);
            return array_map('mobile_gallery_item', $stmt->fetchAll());
        } catch (Throwable $e) {
            error_log('[mobile_gallery_public_items] ' . $e->getMessage());
            return [];
        }
    }
}
