<?php
// api/_slug.php — İşletme slug üretici ve çakışma çözücü
// ─────────────────────────────────────────────────────────
// Kullanım:
//   require_once __DIR__ . '/_slug.php';
//   $slug = wb_generate_slug($pdo, 'Ahmet Kuaför & Güzellik', $businessId);
//   // → "ahmet-kuafor-guzellik" veya "ahmet-kuafor-guzellik-2"
// ─────────────────────────────────────────────────────────
declare(strict_types=1);

/**
 * Türkçe karakterleri ASCII'ye çevirir ve slug formatına dönüştürür.
 */
function wb_slugify(string $text): string
{
    // Türkçe → ASCII
    $tr = [
        'ş'=>'s','Ş'=>'s','ı'=>'i','İ'=>'i','ğ'=>'g','Ğ'=>'g',
        'ü'=>'u','Ü'=>'u','ö'=>'o','Ö'=>'o','ç'=>'c','Ç'=>'c',
        'â'=>'a','Â'=>'a','î'=>'i','Î'=>'i','û'=>'u','Û'=>'u',
        '&'=>'ve','+'=> 've',
    ];
    $text = strtr($text, $tr);

    // Küçük harf
    $text = mb_strtolower($text, 'UTF-8');

    // Harf/rakam dışındakileri tire yap
    $text = preg_replace('/[^a-z0-9]+/', '-', $text);

    // Baş/son tireleri kaldır
    $text = trim($text, '-');

    // Maksimum 80 karakter
    return substr($text, 0, 80);
}

/**
 * Veritabanında çakışma olmayan benzersiz slug üretir.
 *
 * @param PDO    $pdo         Veritabanı bağlantısı
 * @param string $name        İşletme adı
 * @param int    $businessId  Mevcut işletme id'si (güncelleme ise kendi slug'ını görmezden gel)
 * @return string             Benzersiz slug
 */
function wb_generate_slug(PDO $pdo, string $name, int $businessId = 0): string
{
    $base = wb_slugify($name);

    if ($base === '') {
        $base = 'isletme';
    }

    // Önce mevcut slug'ı al — sadece name değişmişse slug yenilensin
    if ($businessId > 0) {
        $existing = $pdo->prepare('SELECT slug FROM businesses WHERE id = ? LIMIT 1');
        $existing->execute([$businessId]);
        $current = (string)($existing->fetchColumn() ?? '');
        // Slug zaten varsa ve hâlâ geçerliyse koru
        if ($current !== '' && str_starts_with($current, $base)) {
            return $current;
        }
    }

    // Çakışma kontrolü
    $candidate = $base;
    $suffix    = 2;

    while (true) {
        $check = $pdo->prepare('SELECT id FROM businesses WHERE slug = ? AND id != ? LIMIT 1');
        $check->execute([$candidate, $businessId]);
        if (!$check->fetchColumn()) {
            break; // Benzersiz
        }
        $candidate = $base . '-' . $suffix;
        $suffix++;

        // Sonsuz döngüye girmesin
        if ($suffix > 999) {
            $candidate = $base . '-' . uniqid();
            break;
        }
    }

    return $candidate;
}

/**
 * İşletmenin slug'ını günceller veya ilk kez oluşturur.
 * settings/save.php ve onboarding'den çağrılır.
 *
 * @return string  Kaydedilen slug
 */
function wb_ensure_slug(PDO $pdo, int $businessId, string $name): string
{
    // Mevcut slug boşsa oluştur, doluysa dokunma
    $row = $pdo->prepare('SELECT slug, name FROM businesses WHERE id = ? LIMIT 1');
    $row->execute([$businessId]);
    $biz = $row->fetch();

    if (!$biz) return '';

    // Slug zaten varsa ve isim değişmediyse koru
    if (!empty($biz['slug'])) {
        return $biz['slug'];
    }

    // Slug yok → oluştur
    $slug = wb_generate_slug($pdo, $name ?: $biz['name'], $businessId);

    $pdo->prepare('UPDATE businesses SET slug = ? WHERE id = ?')
        ->execute([$slug, $businessId]);

    return $slug;
}