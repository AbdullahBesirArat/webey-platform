<?php
declare(strict_types=1);
/**
 * api/mobile/business/staff-photo-upload.php
 * POST (multipart) — Personel için TEK profil fotoğrafı yükler/değiştirir.
 *
 * Body: staff_id (zorunlu), file (zorunlu).
 * Güvenlik: galeri upload standardı (MIME + getimagesize + boyut + güvenli ad).
 * Fotoğraf işletme galerisi KOTASINA dahil değildir (business_photos'a yazılmaz).
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';
require_once __DIR__ . '/_helpers.php';
require_once __DIR__ . '/_gallery_helpers.php';

wb_method('POST');

$auth = mobile_auth($pdo, ['business', 'admin']);
$ctx = mobile_business_context($pdo, $auth);
$businessId = (int)$ctx['business_id'];

if (!mobile_table_has_column($pdo, 'staff', 'profile_photo_url')) {
    wb_err('Personel fotoğrafı servisi şu an kullanılamıyor', 503, 'staff_photo_unavailable');
}

$staffId = (int)($_POST['staff_id'] ?? 0);
if ($staffId < 1) {
    wb_err('staff_id zorunlu', 400, 'missing_staff_id');
}

// Personel bu işletmeye ait mi?
$chk = $pdo->prepare('SELECT id FROM staff WHERE id = ? AND business_id = ? LIMIT 1');
$chk->execute([$staffId, $businessId]);
if (!$chk->fetch()) {
    wb_err('Personel bulunamadı', 404, 'staff_not_found');
}

$file = $_FILES['file'] ?? null;
if (!$file) {
    wb_err('file zorunlu', 400, 'bad_request');
}

try {
    // Galeri görsel pipeline'ı (MIME/getimagesize/boyut/güvenli ad) yeniden kullanılır.
    $paths = mobile_gallery_process_upload($file, $businessId);
    $url = $paths['medium_path'] ?? $paths['original_path'] ?? null;
    if ($url === null || $url === '') {
        wb_err('Fotoğraf işlenemedi', 500, 'server_error');
    }

    $pdo->prepare(
        'UPDATE staff SET profile_photo_url = ?, profile_photo_updated_at = NOW()
         WHERE id = ? AND business_id = ?'
    )->execute([$url, $staffId, $businessId]);

    // Cache-busting için versiyon (updated_at epoch).
    $verStmt = $pdo->prepare('SELECT profile_photo_updated_at FROM staff WHERE id = ? LIMIT 1');
    $verStmt->execute([$staffId]);
    $updatedAt = (string)($verStmt->fetchColumn() ?: '');
    $version = $updatedAt !== '' ? (string)strtotime($updatedAt) : (string)time();

    wb_ok([
        'saved' => true,
        'staff' => [
            'id' => (string)$staffId,
            'profile_photo_url' => $url,
            'profile_photo_version' => $version,
        ],
    ], 201);
} catch (Throwable $e) {
    error_log('[mobile/business/staff-photo-upload.php] ' . $e->getMessage());
    wb_err('Personel fotoğrafı yüklenemedi', 500, 'server_error');
}
