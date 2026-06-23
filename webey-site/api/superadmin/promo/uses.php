<?php
declare(strict_types=1);
/**
 * api/superadmin/promo/uses.php
 * GET ?promo_id=123 — promosyon kodu kullanım detayları
 */

require_once __DIR__ . '/../_bootstrap.php';
wb_method('GET');

$promoId = (int)($_GET['promo_id'] ?? 0);
if (!$promoId) { wb_err('promo_id zorunlu', 400, 'missing_param'); }

try {
    $promo = $pdo->prepare("SELECT id, code, plan, discount_type, discount_value, max_uses, used_count, expires_at, is_active, note, created_by, created_at, updated_at FROM promo_codes WHERE id=? LIMIT 1");
    $promo->execute([$promoId]);
    $code = $promo->fetch();
    if (!$code) { wb_err('Kod bulunamadı', 404, 'not_found'); }

    $usesStmt = $pdo->prepare("
        SELECT
            pcu.id,
            pcu.used_at,
            u.id         AS user_id,
            u.email      AS user_email,
            u.name       AS user_name,
            s.id         AS sub_id,
            s.plan       AS sub_plan,
            s.status     AS sub_status,
            s.price      AS sub_price,
            s.start_date AS sub_start,
            s.end_date   AS sub_end,
            b.name       AS biz_name,
            b.city       AS biz_city,
            b.phone      AS user_phone
        FROM promo_code_uses pcu
        JOIN users u ON u.id = pcu.user_id
        LEFT JOIN subscriptions s ON s.id = pcu.subscription_id
        LEFT JOIN businesses b ON b.owner_id = u.id
        WHERE pcu.promo_id = ?
        ORDER BY pcu.used_at DESC
    ");
    $usesStmt->execute([$promoId]);
    $rows = array_map(fn($r) => array_merge($r, ['sub_price' => isset($r['sub_price']) ? (float)$r['sub_price'] : null]), $usesStmt->fetchAll());

    wb_ok(['code' => $code, 'uses' => $rows, 'total' => count($rows)]);

} catch (Throwable $e) {
    error_log('[promo/uses] ' . $e->getMessage());
    wb_err('Veriler alınamadı', 500, 'internal_error');
}