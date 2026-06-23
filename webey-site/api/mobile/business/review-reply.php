<?php
declare(strict_types=1);
/**
 * api/mobile/business/review-reply.php
 * POST — İşletme bir yoruma cevap yazar / cevabı günceller / siler.
 *
 * Body (JSON):
 *   review_id : int    (zorunlu)
 *   reply     : string (boş gönderilirse cevap temizlenir)
 *
 * Yetki: business/admin; yorum bu işletmeye ait olmalı (aksi 404).
 *
 * Yanıt: success, review_id, business_reply, business_reply_at
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';
require_once __DIR__ . '/_helpers.php';

wb_method('POST');

$auth       = mobile_auth($pdo, ['business', 'admin']);
$ctx        = mobile_business_context($pdo, $auth);
$businessId = (int)$ctx['business_id'];

if (!mobile_table_has_column($pdo, 'reviews', 'business_reply')) {
    wb_err('Yorum yanıtlama servisi şu an kullanılamıyor', 503, 'reviews_reply_unavailable');
}

$in       = wb_body();
$reviewId = (int)($in['review_id'] ?? 0);
$reply    = mb_substr(trim((string)($in['reply'] ?? '')), 0, 2000);

if ($reviewId <= 0) {
    wb_err('review_id zorunlu', 422, 'missing_review_id');
}

// Yorum bu işletmeye ait mi?
$own = $pdo->prepare('SELECT id FROM reviews WHERE id = ? AND business_id = ? LIMIT 1');
$own->execute([$reviewId, $businessId]);
if ($own->fetchColumn() === false) {
    wb_err('Yorum bulunamadı', 404, 'review_not_found');
}

try {
    if ($reply === '') {
        $pdo->prepare(
            'UPDATE reviews SET business_reply = NULL, business_reply_at = NULL
             WHERE id = ? AND business_id = ?'
        )->execute([$reviewId, $businessId]);
        $replyAt = null;
    } else {
        $pdo->prepare(
            'UPDATE reviews SET business_reply = ?, business_reply_at = NOW()
             WHERE id = ? AND business_id = ?'
        )->execute([$reply, $reviewId, $businessId]);
        $replyAt = date('Y-m-d H:i:s');
    }
} catch (Throwable $e) {
    error_log('[mobile/business/review-reply.php] ' . $e->getMessage());
    wb_err('Yorum yanıtı kaydedilemedi', 500, 'internal_error');
}

wb_ok([
    'success'           => true,
    'review_id'         => (string)$reviewId,
    'business_reply'    => $reply !== '' ? $reply : null,
    'business_reply_at' => $replyAt,
    'message'           => $reply !== '' ? 'Yanıtınız kaydedildi.' : 'Yanıt kaldırıldı.',
]);
