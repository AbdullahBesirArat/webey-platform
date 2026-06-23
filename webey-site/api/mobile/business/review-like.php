<?php
declare(strict_types=1);
/**
 * api/mobile/business/review-like.php
 * POST — İşletme bir yorumu beğenir / beğeniyi kaldırır.
 *
 * Body (JSON):
 *   review_id : int  (zorunlu)
 *   liked     : bool (true: beğen, false: kaldır)
 *
 * Yetki: business/admin; yorum bu işletmeye ait olmalı (aksi 404).
 *
 * Yanıt: success, review_id, business_liked
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';
require_once __DIR__ . '/_helpers.php';

wb_method('POST');

$auth       = mobile_auth($pdo, ['business', 'admin']);
$ctx        = mobile_business_context($pdo, $auth);
$businessId = (int)$ctx['business_id'];

if (!mobile_table_has_column($pdo, 'reviews', 'business_liked')) {
    wb_err('Yorum beğeni servisi şu an kullanılamıyor', 503, 'reviews_like_unavailable');
}

$in       = wb_body();
$reviewId = (int)($in['review_id'] ?? 0);
$rawLiked = $in['liked'] ?? true;
$liked    = ($rawLiked === true) || ($rawLiked === 1) || ($rawLiked === '1')
    || (is_string($rawLiked) && strtolower($rawLiked) === 'true');

if ($reviewId <= 0) {
    wb_err('review_id zorunlu', 422, 'missing_review_id');
}

$own = $pdo->prepare('SELECT id FROM reviews WHERE id = ? AND business_id = ? LIMIT 1');
$own->execute([$reviewId, $businessId]);
if ($own->fetchColumn() === false) {
    wb_err('Yorum bulunamadı', 404, 'review_not_found');
}

try {
    $pdo->prepare(
        'UPDATE reviews
            SET business_liked = ?, business_liked_at = ' . ($liked ? 'NOW()' : 'NULL') . '
          WHERE id = ? AND business_id = ?'
    )->execute([$liked ? 1 : 0, $reviewId, $businessId]);
} catch (Throwable $e) {
    error_log('[mobile/business/review-like.php] ' . $e->getMessage());
    wb_err('Beğeni güncellenemedi', 500, 'internal_error');
}

wb_ok([
    'success'       => true,
    'review_id'     => (string)$reviewId,
    'business_liked' => $liked,
]);
