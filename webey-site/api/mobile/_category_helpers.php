<?php
declare(strict_types=1);
/**
 * api/mobile/_category_helpers.php
 * Hizmet kategorisi (service_categories / business_categories) ortak yardimcilari.
 *
 * service_categories.business_id = 0  -> sistem (global) kategorisi
 * service_categories.business_id > 0  -> isletmeye ozel kategori
 */

if (!function_exists('mobile_category_table_exists')) {
    /** service_categories tablosu var mi? (migration calismadiysa false) */
    function mobile_category_table_exists(PDO $pdo): bool
    {
        static $exists = null;
        if ($exists === null) {
            try {
                $stmt = $pdo->query("SHOW TABLES LIKE 'service_categories'");
                $exists = $stmt->fetch() !== false;
            } catch (Throwable $e) {
                error_log('[mobile_category_table_exists] ' . $e->getMessage());
                $exists = false;
            }
        }
        return $exists;
    }

    /** business_categories (onboarding ana kategori secimi) tablosu var mi? */
    function mobile_business_categories_table_exists(PDO $pdo): bool
    {
        static $exists = null;
        if ($exists === null) {
            try {
                $stmt = $pdo->query("SHOW TABLES LIKE 'business_categories'");
                $exists = $stmt->fetch() !== false;
            } catch (Throwable $e) {
                error_log('[mobile_business_categories_table_exists] ' . $e->getMessage());
                $exists = false;
            }
        }
        return $exists;
    }

    /** Turkce karakterleri sadelestirip URL-guvenli slug uretir. */
    function mobile_slugify_tr(string $name): string
    {
        $map = [
            'Ğ' => 'g', 'ğ' => 'g', 'Ü' => 'u', 'ü' => 'u', 'Ş' => 's', 'ş' => 's',
            'İ' => 'i', 'I' => 'i', 'ı' => 'i', 'Ö' => 'o', 'ö' => 'o', 'Ç' => 'c', 'ç' => 'c',
        ];
        $slug = strtr(trim($name), $map);
        $slug = strtolower($slug);
        $slug = (string)preg_replace('/[^a-z0-9]+/', '_', $slug);
        $slug = trim($slug, '_');
        if ($slug === '') {
            $slug = 'kategori';
        }
        return mb_substr($slug, 0, 90);
    }

    /** Sistem kategorisi slug -> ana sayfa alt basligi (geriye uyumlu metinler). */
    function mobile_category_subtitle(string $slug): string
    {
        $map = [
            'nail_studio'       => 'Manikür, kalıcı oje ve nail art',
            'lash_brow'         => 'Lifting, laminasyon ve tasarım',
            'skin_care'         => 'Profesyonel bakım ve yenileme',
            'laser_epilation'   => 'Bölgesel ve paket uygulamalar',
            'hair_salon'        => 'Kesim, boya, bakım ve şekillendirme',
            'makeup_studio'     => 'Günlük, gece ve özel gün makyajı',
            'spa_massage'       => 'Rahatlama, bakım ve wellness',
            'beauty_salon'      => 'Kapsamlı güzellik hizmetleri',
            'manicure_pedicure' => 'El ve ayak bakımı',
            'hair_care'         => 'Bakım ve onarım uygulamaları',
            'brow_design'       => 'Kaş şekillendirme ve tasarım',
            'prosthetic_nail'   => 'Jel ve protez tırnak uygulamaları',
            'permanent_makeup'  => 'Kalıcı makyaj uygulamaları',
        ];
        return $map[$slug] ?? 'Profesyonel hizmetler';
    }

    /**
     * Token sahibi isletmenin secebilecegi kategoriler:
     * aktif sistem kategorileri + isletmenin kendi kategorileri.
     *
     * @return array<int, array<string, mixed>>
     */
    function mobile_fetch_categories_for_business(PDO $pdo, int $businessId): array
    {
        if (!mobile_category_table_exists($pdo)) {
            return [];
        }
        $hasSvcActive = mobile_table_has_column($pdo, 'services', 'is_active');
        $activeCond = $hasSvcActive ? ' AND s.is_active = 1' : '';
        $stmt = $pdo->prepare("
            SELECT sc.id, sc.business_id, sc.name, sc.slug, sc.icon_key, sc.sort_order,
                   (SELECT COUNT(*) FROM services s
                     WHERE s.category_id = sc.id AND s.business_id = ?$activeCond) AS service_count
            FROM service_categories sc
            WHERE sc.is_active = 1 AND sc.business_id IN (0, ?)
            ORDER BY sc.business_id ASC, sc.sort_order ASC, sc.name ASC
        ");
        $stmt->execute([$businessId, $businessId]);
        return array_map(
            static fn(array $row): array => mobile_category_item($row),
            $stmt->fetchAll()
        );
    }

    /** Tek kategori satirini API cikti formatina cevirir. */
    function mobile_category_item(array $row): array
    {
        $isSystem = (int)($row['business_id'] ?? 0) === 0;
        return [
            'id' => (int)$row['id'],
            'name' => (string)($row['name'] ?? ''),
            'slug' => (string)($row['slug'] ?? ''),
            'icon_key' => $row['icon_key'] ?? null,
            'sort_order' => (int)($row['sort_order'] ?? 0),
            'is_system' => $isSystem,
            'service_count' => (int)($row['service_count'] ?? 0),
        ];
    }
}
