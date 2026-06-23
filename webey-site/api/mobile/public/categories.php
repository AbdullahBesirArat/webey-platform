<?php
declare(strict_types=1);
/**
 * api/mobile/public/categories.php
 * GET - Customer ana sayfa kategorileri.
 *
 * Artik sabit liste yerine GERCEK veriden uretilir:
 *   - Yalnizca yayindaki (status=active + onboarding_completed=1) salonlarin
 *     aktif hizmetlerinden kategori cikarilir.
 *   - Ana sayfada yalnizca SISTEM kategorileri gosterilir; isletmeye ozel
 *     kategoriler salon detayindaki hizmet gruplamasinda gorunur.
 *   - Kategorisi atanmamis hizmetler isletmenin ana tipine (businesses.type)
 *     map edilerek sayilir; boylece eski veriler de gercek sayima girer.
 *   - Hic hizmeti olmayan kategori DONMEZ (fake/sabit kategori yok).
 *
 * Item alanlari (geriye uyumlu):
 *   id (slug), slug, title, subtitle, icon, sort_order
 *   + category_id (sayisal), salon_count, service_count, is_system
 *
 * Siralama: service_count DESC, salon_count DESC, sort_order ASC, title ASC.
 * Migration calismadiysa eski statik listeye doner (uygulama bozulmaz).
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_category_helpers.php';

wb_method('GET');

try {
    $hasCatId = mobile_table_has_column($pdo, 'services', 'category_id');
    if (!mobile_category_table_exists($pdo) || !$hasCatId) {
        // Migration oncesi geriye uyumlu davranis.
        wb_ok(['items' => mobile_categories()]);
    }

    $hasSvcActive = mobile_table_has_column($pdo, 'services', 'is_active');
    $svcActiveCond = $hasSvcActive ? ' AND s.is_active = 1' : '';

    // Sistem kategorisi meta bilgileri (slug -> satir).
    $metaStmt = $pdo->query(
        "SELECT id, name, slug, icon_key, sort_order
         FROM service_categories
         WHERE business_id = 0 AND is_active = 1"
    );
    $metaBySlug = [];
    foreach ($metaStmt->fetchAll() as $row) {
        $metaBySlug[(string)$row['slug']] = $row;
    }

    // A) Kategorisi atanmis aktif hizmetler (yayindaki salonlar).
    $catStmt = $pdo->prepare("
        SELECT sc.slug,
               COUNT(s.id) AS service_count,
               COUNT(DISTINCT s.business_id) AS salon_count
        FROM service_categories sc
        JOIN services s ON s.category_id = sc.id$svcActiveCond
        JOIN businesses b ON b.id = s.business_id
             AND b.status = 'active' AND b.onboarding_completed = 1
        WHERE sc.business_id = 0 AND sc.is_active = 1
        GROUP BY sc.slug
    ");
    $catStmt->execute();

    $counts = [];
    foreach ($catStmt->fetchAll() as $row) {
        $slug = (string)$row['slug'];
        $counts[$slug] = [
            'service_count' => (int)$row['service_count'],
            'salon_count' => (int)$row['salon_count'],
            'salon_ids' => null,
        ];
    }

    // B) Kategorisi atanmamis aktif hizmetler -> isletme tipine gore say.
    $unStmt = $pdo->prepare("
        SELECT b.type,
               COUNT(s.id) AS service_count,
               COUNT(DISTINCT b.id) AS salon_count
        FROM services s
        JOIN businesses b ON b.id = s.business_id
             AND b.status = 'active' AND b.onboarding_completed = 1
        WHERE s.category_id IS NULL$svcActiveCond
        GROUP BY b.type
    ");
    $unStmt->execute();
    foreach ($unStmt->fetchAll() as $row) {
        $slugs = mobile_category_slugs_from_type($row['type'] ?? null);
        if ($slugs === []) {
            continue;
        }
        $slug = $slugs[0];
        if (!isset($counts[$slug])) {
            $counts[$slug] = ['service_count' => 0, 'salon_count' => 0, 'salon_ids' => null];
        }
        $counts[$slug]['service_count'] += (int)$row['service_count'];
        // Not: ayni salon hem A hem B'de sayilabilir; salon_count yaklasik
        // degerdir ve yalnizca siralama/gosterim amaclidir.
        $counts[$slug]['salon_count'] += (int)$row['salon_count'];
    }

    $items = [];
    foreach ($counts as $slug => $count) {
        $meta = $metaBySlug[$slug] ?? null;
        if ($meta === null || $count['service_count'] < 1) {
            continue;
        }
        $items[] = [
            'id' => $slug, // geriye uyumluluk: eski istemciler id'yi slug olarak kullanir
            'category_id' => (int)$meta['id'],
            'slug' => $slug,
            'title' => (string)$meta['name'],
            'subtitle' => mobile_category_subtitle($slug),
            'icon' => $meta['icon_key'] !== null && $meta['icon_key'] !== ''
                ? (string)$meta['icon_key']
                : 'sparkles',
            'sort_order' => (int)$meta['sort_order'],
            'salon_count' => $count['salon_count'],
            'service_count' => $count['service_count'],
            'is_system' => true,
        ];
    }

    usort($items, static function (array $a, array $b): int {
        return [$b['service_count'], $b['salon_count'], $a['sort_order'], $a['title']]
            <=> [$a['service_count'], $a['salon_count'], $b['sort_order'], $b['title']];
    });

    wb_ok(['items' => $items]);
} catch (Throwable $e) {
    error_log('[mobile/public/categories.php] ' . $e->getMessage());
    wb_err('Kategoriler alınamadı', 500, 'internal_error');
}
