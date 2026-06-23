<?php
declare(strict_types=1);
/**
 * api/settings/delete-image.php
 * POST — İşletme görselini sil
 */

require_once __DIR__ . '/../admin/_bootstrap.php';
wb_method('POST');

$bid = $user['business_id'];
if (!$bid) wb_err('İşletme bulunamadı', 404, 'business_not_found');

$in   = wb_body();
$url  = trim((string)($in['url']  ?? ''));
$kind = trim((string)($in['kind'] ?? ''));

wb_validate(['url' => $url, 'kind' => $kind], [
    'url'  => ['required'],
    'kind' => ['required', 'in:cover,salon,model'],
]);

try {
    $stmt = $pdo->prepare('SELECT images_json FROM businesses WHERE id = ?');
    $stmt->execute([$bid]);
    $row    = $stmt->fetch();
    $images = json_decode($row['images_json'] ?? 'null', true)
        ?: ['cover' => [], 'salon' => [], 'model' => []];

    $optKey   = $kind . '_opt';
    $origList = is_array($images[$kind]   ?? null) ? $images[$kind]   : [];
    $optList  = is_array($images[$optKey] ?? null) ? $images[$optKey] : [];

    // Orijinal URL ile eşleşen pozisyonu bul; opt URL'si aynı indekste
    $pos    = array_search($url, $origList, true);
    $optUrl = null;

    if ($pos !== false) {
        $optUrl = $optList[$pos] ?? null;
        array_splice($origList, $pos, 1);
        if ($optUrl) array_splice($optList, $pos, 1);
    } else {
        $origList = array_values(array_filter($origList, fn($u) => $u !== $url));
    }

    $images[$kind]   = $origList;
    $images[$optKey] = $optList;

    $pdo->prepare('UPDATE businesses SET images_json = ? WHERE id = ?')
        ->execute([json_encode($images), $bid]);

    // ── Fiziksel dosyaları sil ────────────────────────────────────────────────
    $webeyRoot  = realpath(__DIR__ . '/../..');
    $deleteUrls = array_filter([$url, $optUrl]);

    foreach ($deleteUrls as $delUrl) {
        $clean    = ltrim(preg_replace('#^(/[^/]+)?/uploads/#', 'uploads/', (string)$delUrl), '/');
        $filePath = $webeyRoot . '/' . $clean;
        // Güvenlik: uploads/ dizini dışına çıkma
        $realDir  = realpath(dirname($filePath)) ?: '';
        if ($webeyRoot && str_starts_with($realDir, $webeyRoot . '/uploads')) {
            if (file_exists($filePath)) @unlink($filePath);
        }
    }

    wb_ok(['images' => $images]);

} catch (Throwable $e) {
    error_log('[settings/delete-image] ' . $e->getMessage());
    wb_err('Görsel silinemedi', 500, 'internal_error');
}