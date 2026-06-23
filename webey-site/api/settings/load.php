<?php
declare(strict_types=1);
/**
 * api/settings/load.php
 * GET — İşletme ayarlarını yükle (business, hours, services, images)
 */

require_once __DIR__ . '/../admin/_bootstrap.php';
wb_method('GET');

$bid = $user['business_id'];
if (!$bid) wb_err('İşletme bulunamadı', 404, 'business_not_found');

try {
    // ── İşletme bilgileri ────────────────────────────────────────────────────
    $stmt = $pdo->prepare('
        SELECT name, owner_name, phone, city, district, address_line,
               about, map_url, building_no, neighborhood, images_json
        FROM   businesses WHERE id = ?
    ');
    $stmt->execute([$bid]);
    $biz = $stmt->fetch();
    if (!$biz) wb_err('İşletme bulunamadı', 404, 'business_not_found');

    // ── Çalışma saatleri ─────────────────────────────────────────────────────
    $stmt = $pdo->prepare('
        SELECT day, is_open, open_time, close_time
        FROM   business_hours
        WHERE  business_id = ?
        ORDER BY FIELD(day,"mon","tue","wed","thu","fri","sat","sun")
    ');
    $stmt->execute([$bid]);
    $hours = [];
    foreach ($stmt->fetchAll() as $h) {
        $isOpen       = (bool)$h['is_open'];
        $hours[$h['day']] = [
            'closed' => !$isOpen,
            'open'   => $isOpen && $h['open_time']  ? substr($h['open_time'],  0, 5) : '10:00',
            'close'  => $isOpen && $h['close_time'] ? substr($h['close_time'], 0, 5) : '19:00',
        ];
    }

    // ── Hizmetler ────────────────────────────────────────────────────────────
    $stmt = $pdo->prepare('
        SELECT id, name, duration_min AS min, price
        FROM   services
        WHERE  business_id = ?
        ORDER BY id ASC
    ');
    $stmt->execute([$bid]);
    $services = array_map(function ($s) {
        $s['min']   = (int)$s['min'];
        $s['price'] = (float)$s['price'];
        return $s;
    }, $stmt->fetchAll());

    // ── Görseller + URL normalize ─────────────────────────────────────────────
    $rawImages = json_decode($biz['images_json'] ?? 'null', true) ?: [];
    $images    = _normalizeImages($rawImages, $bid);

    // One-time migration: normalize edilmiş URL'leri DB'ye geri yaz
    if ($rawImages !== $images) {
        $pdo->prepare('UPDATE businesses SET images_json = ? WHERE id = ?')
            ->execute([json_encode($images), $bid]);
    }

    wb_ok([
        'business' => [
            'name'         => $biz['name']         ?? '',
            'ownerName'    => $biz['owner_name']    ?? '',
            'phone'        => $biz['phone']         ?? '',
            'about'        => $biz['about']         ?? '',
            'city'         => $biz['city']          ?? '',
            'district'     => $biz['district']      ?? '',
            'neighborhood' => $biz['neighborhood']  ?? '',
            'buildingNo'   => $biz['building_no']   ?? '',
            'mapUrl'       => $biz['map_url']       ?? '',
            'addressLine'  => $biz['address_line']  ?? '',
        ],
        'hours'    => $hours,
        'services' => $services,
        'images'   => $images,
    ]);

} catch (Throwable $e) {
    error_log('[settings/load] ' . $e->getMessage());
    wb_err('Ayarlar yüklenemedi', 500, 'internal_error');
}

// ── Yardımcı: URL normalize ───────────────────────────────────────────────────
function _normalizeImages(array $raw, int $bid): array
{
    $images = ['cover' => [], 'cover_opt' => [], 'salon' => [], 'salon_opt' => [], 'model' => [], 'model_opt' => []];

    foreach (['cover', 'cover_opt', 'salon', 'salon_opt', 'model', 'model_opt'] as $k) {
        $list = $raw[$k] ?? [];
        if (!is_array($list)) $list = $list ? [$list] : [];
        foreach ($list as $u) {
            $n = _normalizeUrl((string)$u, $bid);
            if ($n) $images[$k][] = $n;
        }
    }
    return $images;
}

function _normalizeUrl(string $url, int $bid): ?string
{
    $url = trim($url);
    if (!$url) return null;
    if (str_starts_with($url, 'uploads/')) return $url;
    if (preg_match('#/uploads/biz/(\d+)/(.+)$#', $url, $m)) return 'uploads/biz/' . $m[1] . '/' . $m[2];
    if (preg_match('#/uploads/(?:optimized|original)/(.+)$#', $url, $m)) return 'uploads/optimized/' . $m[1];
    if (!str_contains($url, '/')) return 'uploads/biz/' . $bid . '/' . $url;
    return $url;
}