<?php
declare(strict_types=1);
/**
 * api/business/profile.php
 * GET ?id=123  veya  ?slug=salon-adi
 * PUBLIC — işletme profil sayfası için tek endpoint
 *
 * PERFORMANS FIX (N+1 → 6 sorgu):
 * Önceki sürüm 10 personelli bir işletme için 4+2N = 24 sorgu yapıyordu.
 * Artık:
 *   1. İşletme
 *   2. Çalışma saatleri
 *   3. Hizmetler
 *   4. Personel listesi
 *   5. Tüm personel saatleri (tek JOIN sorgusu)
 *   6. Tüm personel→hizmet eşleştirmeleri (tek sorgu)
 * = 6 sabit sorgu, N'den bağımsız.
 */

require_once __DIR__ . '/../_public_bootstrap.php';
header('Cache-Control: public, max-age=30');
wb_method('GET');

$id   = (int)trim($_GET['id']   ?? '0');
$slug = trim($_GET['slug'] ?? '');

if (!$id && !$slug) {
    wb_err('id veya slug zorunlu', 400, 'missing_param');
}

try {
    if (!function_exists('normalizeImageUrl')) {
        function normalizeImageUrl($url, $bid) {
            if (!$url) return null;
            $url = trim($url);
            if (str_starts_with($url, 'uploads/')) return $url;
            if (preg_match('#/uploads/biz/(\d+)/(.+)$#', $url, $m)) return 'uploads/biz/' . $m[1] . '/' . $m[2];
            if (preg_match('#/uploads/(?:optimized|original)/(.+)$#', $url, $m)) return 'uploads/optimized/' . $m[1];
            if (!str_contains($url, '/')) return 'uploads/biz/' . $bid . '/' . $url;
            return $url;
        }
    }
    if (!function_exists('wb_local_image_path')) {
        function wb_local_image_path(?string $url, string $webeyRoot): ?string {
            if (!$url) return null;
            $clean = ltrim((string)$url, '/');
            if (!str_starts_with($clean, 'uploads/')) return null;
            return $webeyRoot . '/' . $clean;
        }
    }
    if (!function_exists('wb_image_orientation_key')) {
        function wb_image_orientation_key(?string $path): ?string {
            if (!$path || !is_file($path)) return null;
            $size = @getimagesize($path);
            if (!$size || empty($size[0]) || empty($size[1])) return null;
            $w = (int)$size[0];
            $h = (int)$size[1];
            if (abs($w - $h) <= max(8, (int)floor(min($w, $h) * 0.05))) return 'square';
            return $w > $h ? 'landscape' : 'portrait';
        }
    }
    if (!function_exists('wb_safe_display_image_url')) {
        function wb_safe_display_image_url(?string $origUrl, ?string $optUrl, string $webeyRoot): ?string {
            if (!$optUrl) return $origUrl;
            if (!$origUrl) return $optUrl;
            $origPath = wb_local_image_path($origUrl, $webeyRoot);
            $optPath = wb_local_image_path($optUrl, $webeyRoot);
            $origOrientation = wb_image_orientation_key($origPath);
            $optOrientation = wb_image_orientation_key($optPath);
            if ($origOrientation && $optOrientation && $origOrientation !== $optOrientation) {
                return $origUrl;
            }
            return $optUrl;
        }
    }

    // ── 1. İşletme ───────────────────────────────────────────────────────────
    if ($id) {
        $stmt = $pdo->prepare("SELECT b.*, u.email AS owner_email FROM businesses b LEFT JOIN users u ON u.id = b.owner_id WHERE b.id = ? LIMIT 1");
        $stmt->execute([$id]);
    } else {
        $stmt = $pdo->prepare("SELECT b.*, u.email AS owner_email FROM businesses b LEFT JOIN users u ON u.id = b.owner_id WHERE b.slug = ? LIMIT 1");
        $stmt->execute([$slug]);
    }
    $biz = $stmt->fetch();
    if (!$biz) { wb_err('İşletme bulunamadı', 404, 'not_found'); }

    $bizId = (int)$biz['id'];

    require_once __DIR__ . '/../../api/_subscription_check.php';
    $ownerSub    = getSubscriptionStatus($pdo, (int)$biz['owner_id']);
    $isPublished = $ownerSub['active'];

    // ── 2. Çalışma saatleri ──────────────────────────────────────────────────
    $hStmt = $pdo->prepare("SELECT day, is_open, open_time, close_time FROM business_hours WHERE business_id = ? ORDER BY FIELD(day,'mon','tue','wed','thu','fri','sat','sun')");
    $hStmt->execute([$bizId]);
    $hours = [];
    foreach ($hStmt->fetchAll() as $h) {
        $isOpen    = (bool)$h['is_open'];
        $openTime  = ($isOpen && $h['open_time'])  ? substr($h['open_time'],  0, 5) : null;
        $closeTime = ($isOpen && $h['close_time']) ? substr($h['close_time'], 0, 5) : null;
        $hours[$h['day']] = ['closed' => !$isOpen, 'open' => $openTime, 'close' => $closeTime, 'start' => $openTime, 'end' => $closeTime, 'from' => $openTime, 'to' => $closeTime];
    }

    // ── 3. Hizmetler ─────────────────────────────────────────────────────────
    $sStmt = $pdo->prepare("SELECT id, name, duration_min, price FROM services WHERE business_id = ? ORDER BY id ASC");
    $sStmt->execute([$bizId]);
    $services = [];
    foreach ($sStmt->fetchAll() as $svc) {
        $services[] = ['id' => (string)$svc['id'], 'name' => $svc['name'], 'duration' => (int)$svc['duration_min'], 'duration_min' => (int)$svc['duration_min'], 'min' => (int)$svc['duration_min'], 'price' => (float)$svc['price']];
    }

    // ── 4. Personel listesi ──────────────────────────────────────────────────
    $stStmt = $pdo->prepare("SELECT id, name, color, phone FROM staff WHERE business_id = ? ORDER BY id ASC");
    $stStmt->execute([$bizId]);
    $staffRows = $stStmt->fetchAll();

    if (empty($staffRows)) {
        $staff = [];
    } else {
        $staffIds = array_column($staffRows, 'id');
        $inSql    = implode(',', array_fill(0, count($staffIds), '?'));

        // ── 5. Tüm personel saatleri — TEK SORGU (N+1 düzeltildi) ──────────
        $shStmt = $pdo->prepare("
            SELECT staff_id, day, is_open, open_time, close_time
            FROM staff_hours
            WHERE staff_id IN ($inSql) AND business_id = ?
            ORDER BY staff_id, FIELD(day,'mon','tue','wed','thu','fri','sat','sun')
        ");
        $shStmt->execute(array_merge($staffIds, [$bizId]));
        $allStaffHours = [];
        foreach ($shStmt->fetchAll() as $h) {
            $isOpen    = (bool)$h['is_open'];
            $openTime  = ($isOpen && $h['open_time'])  ? substr($h['open_time'],  0, 5) : null;
            $closeTime = ($isOpen && $h['close_time']) ? substr($h['close_time'], 0, 5) : null;
            $allStaffHours[(int)$h['staff_id']][$h['day']] = ['closed' => !$isOpen, 'open' => $openTime, 'close' => $closeTime, 'start' => $openTime, 'end' => $closeTime];
        }

        // ── 6. Tüm personel→hizmet eşleştirmeleri — TEK SORGU (N+1 düzeltildi)
        $ssStmt = null;
        $allStaffServices = null;
        try {
            $ssStmt = $pdo->prepare("SELECT staff_id, service_id FROM staff_services WHERE staff_id IN ($inSql) ORDER BY staff_id, service_id");
            $ssStmt->execute($staffIds);
            $allStaffServices = [];
            foreach ($ssStmt->fetchAll() as $ss) {
                $allStaffServices[(int)$ss['staff_id']][] = (string)$ss['service_id'];
            }
        } catch (Throwable) {
            $allStaffServices = null; // staff_services tablosu yoksa null → tüm hizmetler gösterilir
        }

        $fallbackAllServiceIds = array_map(static fn(array $svc): string => (string)$svc['id'], $services);
        $hasAnyExplicitStaffService = !empty($allStaffServices);
        $staff = [];
        foreach ($staffRows as $s) {
            $sid      = (int)$s['id'];

            $entry = [
                'id'            => (string)$sid,
                'name'          => $s['name'],
                'position'      => null,
                'color'         => $s['color'] ?? null,
                'phone'         => $s['phone'] ?? null,
                'hoursOverride' => $allStaffHours[$sid] ?? [],
            ];
            if ($allStaffServices !== null) {
                $entry['serviceIds'] = $allStaffServices[$sid] ?? ($hasAnyExplicitStaffService ? [] : $fallbackAllServiceIds);
            }
            $staff[] = $entry;
        }
    }

    // ── Görseller ────────────────────────────────────────────────────────────
    $webeyRoot = realpath(__DIR__ . '/../..') ?: dirname(__DIR__, 2);
    $images   = ['cover' => [], 'salon' => [], 'model' => [], 'cover_opt' => [], 'salon_opt' => [], 'model_opt' => []];
    $coverUrl = null;
    if (!empty($biz['images_json'])) {
        $rawImg   = json_decode($biz['images_json'], true) ?? [];
        $rawCover = $rawImg['cover'] ?? null;
        if (is_array($rawCover)) {
            foreach ($rawCover as $u) { $n = normalizeImageUrl($u, $bizId); if ($n) $images['cover'][] = $n; }
        } elseif ($rawCover) {
            $n = normalizeImageUrl($rawCover, $bizId); if ($n) $images['cover'][] = $n;
        }
        foreach ($rawImg['cover_opt'] ?? [] as $u) { $n = normalizeImageUrl($u, $bizId); if ($n) $images['cover_opt'][] = $n; }
        foreach (['salon', 'model'] as $k) {
            $arr = $rawImg[$k] ?? [];
            if (!is_array($arr)) continue;
            foreach ($arr as $u) { $n = normalizeImageUrl($u, $bizId); if ($n) $images[$k][] = $n; }
            foreach ($rawImg[$k . '_opt'] ?? [] as $u) { $n = normalizeImageUrl($u, $bizId); if ($n) $images[$k . '_opt'][] = $n; }
        }
        foreach (['cover', 'salon', 'model'] as $k) {
            $optKey = $k . '_opt';
            $safeOpt = [];
            foreach ($images[$k] as $idx => $origUrl) {
                $optUrl = $images[$optKey][$idx] ?? null;
                $safeOpt[] = wb_safe_display_image_url($origUrl, $optUrl, $webeyRoot);
            }
            $images[$optKey] = array_values(array_filter($safeOpt));
        }
        $coverUrl = $images['cover_opt'][0] ?? $images['cover'][0] ?? null;
    }
    if (!$coverUrl && !empty($biz['logo_url'])) {
        $coverUrl = normalizeImageUrl($biz['logo_url'], $bizId);
    }

    // ── Response ─────────────────────────────────────────────────────────────
    $payload = [
        'is_published' => $isPublished,
        'subscription' => ['active' => $ownerSub['active'], 'trialing' => $ownerSub['trialing'], 'plan' => $ownerSub['plan'], 'days_left' => $ownerSub['days_left']],
        'id'           => (string)$bizId,
        'businessId'   => (string)$bizId,
        'uid'          => (string)$bizId,
        'slug'         => $biz['slug'] ?? null,
        'name'         => $biz['name'] ?? '',
        'about'        => $biz['about'] ?? '',
        'phone'        => $biz['phone'] ?? '',
        'phoneE164'    => $biz['phone'] ?? '',
        'category'     => $biz['category'] ?? null,
        'status'       => $biz['status'] ?? null,
        'coverUrl'     => $coverUrl,
        'logoUrl'      => $biz['logo_url'] ?? $coverUrl,
        'images'       => $images,
        'services'     => $services,
        'hours'        => $hours,
        'staff'        => $staff,
        'loc'          => [
            'city'         => $biz['city']         ?? '',
            'district'     => $biz['district']     ?? '',
            'neighborhood' => $biz['neighborhood'] ?? '',
            'addressLine'  => $biz['address_line'] ?? '',
            'province'     => $biz['city']         ?? '',
            'mapUrl'       => $biz['map_url']      ?? null,
        ],
        'location'     => [
            'city'         => $biz['city']         ?? '',
            'district'     => $biz['district']     ?? '',
            'neighborhood' => $biz['neighborhood'] ?? '',
            'addressLine'  => $biz['address_line'] ?? '',
        ],
        'owner' => $biz['owner_name'] ? [
            'id'    => isset($biz['owner_id']) ? (string)$biz['owner_id'] : null,
            'name'  => $biz['owner_name'],
            'email' => $biz['owner_email'] ?? null,
        ] : null,
    ];

    wb_ok($payload);

} catch (Throwable $e) {
    error_log('[business/profile.php] ' . $e->getMessage());
    wb_err('İşletme bilgileri alınamadı', 500, 'internal_error');
}
