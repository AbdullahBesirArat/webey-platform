<?php
declare(strict_types=1);
/**
 * api/superadmin/app/gallery.php
 * GET — İşletme galeri sağlık raporu. READ-ONLY.
 * Sadece sayılar + thumb path; original path/büyük dosya dönmez.
 *
 * Filtreler: no_photos=1, missing_cover=1, over_quota=1, q, page, limit
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/_helpers.php';
wb_method('GET');

// Kota limiti api/mobile/business/_gallery_helpers.php ile aynı tutulmalı.
const SA_GALLERY_QUOTA_LIMIT = 120;

try {
    $pg     = sa_page_params(25);
    $where  = [];
    $params = [];

    $q = trim((string)($_GET['q'] ?? ''));
    if ($q !== '') { $where[] = 'b.name LIKE ?'; $params[] = sa_like($q); }

    if (($_GET['no_photos'] ?? '') === '1') {
        $where[] = "NOT EXISTS (SELECT 1 FROM business_photos p
                     WHERE p.business_id=b.id AND p.status='active')";
    }
    if (($_GET['missing_cover'] ?? '') === '1') {
        $where[] = "NOT EXISTS (SELECT 1 FROM business_photos p
                     WHERE p.business_id=b.id AND p.is_cover=1 AND p.status='active')";
    }
    if (($_GET['over_quota'] ?? '') === '1') {
        $where[] = "(SELECT COUNT(*) FROM business_photos p
                     WHERE p.business_id=b.id AND p.status='active') > " . SA_GALLERY_QUOTA_LIMIT;
    }

    $whereSql = $where ? ('WHERE ' . implode(' AND ', $where)) : '';

    $total = (int)sa_val($pdo, "SELECT COUNT(*) FROM businesses b $whereSql", $params);

    $rows = sa_rows($pdo, "
        SELECT
            b.id, b.name, b.status,
            (SELECT COUNT(*) FROM business_photos p
              WHERE p.business_id=b.id AND p.status='active')                       AS photo_count,
            (SELECT p.id FROM business_photos p
              WHERE p.business_id=b.id AND p.is_cover=1 AND p.status='active'
              ORDER BY p.id LIMIT 1)                                                AS cover_photo_id,
            (SELECT COUNT(*) FROM business_photos p
              WHERE p.business_id=b.id AND p.category='logo' AND p.status='active') AS logo_count,
            (SELECT COUNT(*) FROM business_photos p
              WHERE p.business_id=b.id AND p.status='active' AND p.is_visible=1)    AS visible_photo_count,
            (SELECT COUNT(*) FROM business_photos p
              WHERE p.business_id=b.id AND p.status='active' AND p.is_visible=0)    AS hidden_photo_count,
            (SELECT MAX(p.created_at) FROM business_photos p
              WHERE p.business_id=b.id AND p.status='active')                       AS last_photo_created_at,
            (SELECT p.thumb_path FROM business_photos p
              WHERE p.business_id=b.id AND p.is_cover=1 AND p.status='active'
              ORDER BY p.id LIMIT 1)                                                AS cover_thumb
        FROM businesses b
        $whereSql
        ORDER BY photo_count DESC, b.name ASC
        LIMIT {$pg['limit']} OFFSET {$pg['offset']}
    ", $params);

    $items = array_map(static function (array $r): array {
        $count = (int)$r['photo_count'];
        return [
            'business_id'           => (int)$r['id'],
            'business_name'         => $r['name'],
            'business_status'       => $r['status'],
            'photo_count'           => $count,
            'has_cover'             => $r['cover_photo_id'] !== null,
            'cover_photo_id'        => $r['cover_photo_id'] !== null ? (int)$r['cover_photo_id'] : null,
            'cover_thumb'           => $r['cover_thumb'],
            'logo_count'            => (int)$r['logo_count'],
            'visible_photo_count'   => (int)$r['visible_photo_count'],
            'hidden_photo_count'    => (int)$r['hidden_photo_count'],
            'quota_used'            => $count,
            'quota_limit'           => SA_GALLERY_QUOTA_LIMIT,
            'over_quota'            => $count > SA_GALLERY_QUOTA_LIMIT,
            'last_photo_created_at' => $r['last_photo_created_at'],
        ];
    }, $rows);

    wb_ok(sa_list_payload($items, $total, $pg));

} catch (Throwable $e) {
    error_log('[superadmin/app/gallery] ' . $e->getMessage());
    wb_err('Galeri raporu yüklenemedi', 500, 'internal_error');
}
