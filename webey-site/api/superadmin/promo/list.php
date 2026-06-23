<?php
declare(strict_types=1);
/**
 * api/superadmin/promo/list.php
 * GET - Tum promosyon kodlarini listeler.
 */

require_once __DIR__ . '/../_bootstrap.php';

wb_method('GET');

try {
    $rows = $pdo->query("
        SELECT p.*,
               u.email AS created_by_email,
               (SELECT COUNT(*) FROM promo_code_uses WHERE promo_id = p.id) AS actual_uses,
               (SELECT MAX(pcu.used_at) FROM promo_code_uses pcu WHERE pcu.promo_id = p.id) AS last_used_at,
               (SELECT uu.email
                FROM promo_code_uses pcu2
                JOIN users uu ON uu.id = pcu2.user_id
                WHERE pcu2.promo_id = p.id
                ORDER BY pcu2.used_at DESC
                LIMIT 1) AS last_used_by_email
        FROM promo_codes p
        LEFT JOIN users u ON u.id = p.created_by
        ORDER BY p.created_at DESC
    ")->fetchAll(PDO::FETCH_ASSOC);

    $codes = array_map(static function (array $row): array {
        $actualUses = (int)$row['actual_uses'];
        $maxUses = $row['max_uses'] !== null ? (int)$row['max_uses'] : null;
        $isExpired = $row['expires_at'] && strtotime((string)$row['expires_at']) < time();
        $isExhausted = $maxUses !== null && $actualUses >= $maxUses;

        return [
            'id' => (int)$row['id'],
            'code' => $row['code'],
            'plan' => $row['plan'],
            'discount_type' => $row['discount_type'],
            'discount_value' => (float)$row['discount_value'],
            'max_uses' => $maxUses,
            'used_count' => $actualUses,
            'expires_at' => $row['expires_at'],
            'is_active' => (bool)$row['is_active'],
            'note' => $row['note'],
            'created_by' => $row['created_by_email'],
            'created_at' => $row['created_at'],
            'updated_at' => $row['updated_at'],
            'last_used_at' => $row['last_used_at'],
            'last_used_by_email' => $row['last_used_by_email'],
            'is_expired' => $isExpired,
            'is_exhausted' => $isExhausted,
            'can_delete' => $actualUses === 0,
        ];
    }, $rows);

    wb_ok(['codes' => $codes]);
} catch (Throwable $e) {
    error_log('[promo/list] ' . $e->getMessage());
    wb_err('Sunucu hatasi', 500, 'internal_error');
}
