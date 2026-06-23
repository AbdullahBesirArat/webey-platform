<?php
declare(strict_types=1);

$origin = $_SERVER['HTTP_ORIGIN'] ?? '';

$allowedOrigins = [
    'http://localhost:8081',
    'http://localhost:8082',
    'http://127.0.0.1:8081',
    'http://127.0.0.1:8082',
    'https://webey.com.tr',
    'https://www.webey.com.tr',
];

if ($origin !== '' && in_array($origin, $allowedOrigins, true)) {
    header("Access-Control-Allow-Origin: {$origin}");
    header('Vary: Origin');
    header('Access-Control-Allow-Credentials: true');
}

header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Accept');
header('Access-Control-Max-Age: 86400');

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    http_response_code(204);
    exit;
}

/**
 * api/mobile/_bootstrap.php
 * Mobile API endpoints için ortak başlangıç dosyası.
 *
 * Faz 1 kapsamı:
 * - Response standardı: wb_ok / wb_err
 * - DB bağlantısı: mevcut db.php
 * - Auth yok; Faz 2'de eklenecek.
 */

ini_set('display_errors', '0');
ini_set('display_startup_errors', '0');
error_reporting(E_ALL);

require_once __DIR__ . '/../wb_response.php';
require_once __DIR__ . '/../../db.php';

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

if (!function_exists('mobile_param')) {
    function mobile_param(string $key, mixed $default = null): mixed
    {
        $value = $_GET[$key] ?? $_POST[$key] ?? $default;
        if (is_string($value)) {
            return trim($value);
        }
        return $value;
    }

    function mobile_int_param(string $key, ?int $default = null): ?int
    {
        $value = mobile_param($key, $default);
        if ($value === null || $value === '') {
            return $default;
        }
        return filter_var($value, FILTER_VALIDATE_INT) !== false ? (int)$value : $default;
    }

    function mobile_bool_param(string $key, bool $default = false): bool
    {
        $value = mobile_param($key, null);
        if ($value === null || $value === '') {
            return $default;
        }
        if (is_bool($value)) {
            return $value;
        }
        $normalized = strtolower((string)$value);
        return in_array($normalized, ['1', 'true', 'yes', 'on'], true);
    }

    function mobile_limit(mixed $value, int $default = 20, int $max = 50): int
    {
        $limit = filter_var($value, FILTER_VALIDATE_INT) !== false ? (int)$value : $default;
        return min(max($limit, 1), $max);
    }

    function mobile_categories(): array
    {
        return [
            [
                'id' => 'nail_studio',
                'slug' => 'nail_studio',
                'title' => 'Tırnak Stüdyosu',
                'subtitle' => 'Manikür, kalıcı oje ve nail art',
                'icon' => 'nail',
                'sort_order' => 10,
            ],
            [
                'id' => 'lash_brow',
                'slug' => 'lash_brow',
                'title' => 'Kirpik ve Kaş',
                'subtitle' => 'Lifting, laminasyon ve tasarım',
                'icon' => 'eye',
                'sort_order' => 20,
            ],
            [
                'id' => 'skin_care',
                'slug' => 'skin_care',
                'title' => 'Cilt Bakımı',
                'subtitle' => 'Profesyonel bakım ve yenileme',
                'icon' => 'sparkles',
                'sort_order' => 30,
            ],
            [
                'id' => 'laser_epilation',
                'slug' => 'laser_epilation',
                'title' => 'Lazer Epilasyon',
                'subtitle' => 'Bölgesel ve paket uygulamalar',
                'icon' => 'zap',
                'sort_order' => 40,
            ],
            [
                'id' => 'hair_salon',
                'slug' => 'hair_salon',
                'title' => 'Kuaför',
                'subtitle' => 'Kesim, boya, bakım ve şekillendirme',
                'icon' => 'scissors',
                'sort_order' => 50,
            ],
            [
                'id' => 'makeup_studio',
                'slug' => 'makeup_studio',
                'title' => 'Makyaj Stüdyosu',
                'subtitle' => 'Günlük, gece ve özel gün makyajı',
                'icon' => 'brush',
                'sort_order' => 60,
            ],
            [
                'id' => 'spa_massage',
                'slug' => 'spa_massage',
                'title' => 'Spa ve Masaj',
                'subtitle' => 'Rahatlama, bakım ve wellness',
                'icon' => 'spa',
                'sort_order' => 70,
            ],
            [
                'id' => 'beauty_salon',
                'slug' => 'beauty_salon',
                'title' => 'Güzellik Salonu',
                'subtitle' => 'Çoklu güzellik hizmetleri',
                'icon' => 'heart',
                'sort_order' => 80,
            ],
        ];
    }

    function mobile_category_slugs_from_type(?string $type): array
    {
        $type = strtolower(trim((string)$type));
        if ($type === '') {
            return [];
        }

        $direct = array_column(mobile_categories(), 'slug');
        if (in_array($type, $direct, true)) {
            return [$type];
        }

        $map = [
            'kuafor' => 'hair_salon',
            'kuaför' => 'hair_salon',
            'hair' => 'hair_salon',
            'hair_salon' => 'hair_salon',
            'nail' => 'nail_studio',
            'nail_studio' => 'nail_studio',
            'guzellik' => 'beauty_salon',
            'güzellik' => 'beauty_salon',
            'beauty' => 'beauty_salon',
            'beauty_salon' => 'beauty_salon',
            'makeup' => 'makeup_studio',
            'makeup_studio' => 'makeup_studio',
            'spa' => 'spa_massage',
            'spa_massage' => 'spa_massage',
            'lash' => 'lash_brow',
            'lash_brow' => 'lash_brow',
            'skin' => 'skin_care',
            'skin_care' => 'skin_care',
            'laser' => 'laser_epilation',
            'laser_epilation' => 'laser_epilation',
        ];

        return isset($map[$type]) ? [$map[$type]] : [];
    }

    function mobile_images(?string $json): array
    {
        $result = [
            'cover_image_url' => null,
            'logo_url' => null,
            'gallery' => [],
        ];

        if (!$json) {
            return $result;
        }

        $raw = json_decode($json, true);
        if (!is_array($raw)) {
            return $result;
        }

        $gallery = [];
        foreach (['cover_opt', 'cover', 'salon_opt', 'salon', 'model_opt', 'model'] as $key) {
            $items = $raw[$key] ?? [];
            if (is_string($items) && $items !== '') {
                $items = [$items];
            }
            if (!is_array($items)) {
                continue;
            }
            foreach ($items as $item) {
                $url = is_array($item) ? ($item['url'] ?? $item['src'] ?? '') : $item;
                if (is_string($url) && trim($url) !== '' && !in_array($url, $gallery, true)) {
                    $gallery[] = trim($url);
                }
            }
        }

        $result['gallery'] = $gallery;
        $result['cover_image_url'] = $gallery[0] ?? null;
        $result['logo_url'] = $result['cover_image_url'];
        return $result;
    }

    function mobile_day_key(?int $weekday = null): string
    {
        $map = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];
        $idx = $weekday ?? (int)date('w');
        return $map[$idx] ?? 'sun';
    }

    /**
     * Belirtilen tabloda kolonun var olup olmadığını döner.
     * SHOW COLUMNS sonucu request süresince static cache'te tutulur.
     * Tablo yoksa veya izin verilmiyorsa false döner.
     */
    function mobile_table_has_column(PDO $pdo, string $table, string $column): bool
    {
        static $cache = [];
        $allowed = [
            'businesses',
            'appointments',
            'appointment_payments',
            'services',
            'staff',
            'reviews',
            'business_payment_settings',
            'deposit_policies',
            'boost_packages',
            'business_boost_subscriptions',
            'business_boost_requests',
            'business_subscription_plans',
            'business_subscriptions',
            'business_subscription_payments',
        ];
        if (!in_array($table, $allowed, true)) {
            return false;
        }
        if (!array_key_exists($table, $cache)) {
            $cache[$table] = [];
            try {
                $stmt = $pdo->query('SHOW COLUMNS FROM `' . $table . '`');
                foreach ($stmt->fetchAll() as $row) {
                    $field = (string)($row['Field'] ?? '');
                    if ($field !== '') {
                        $cache[$table][$field] = true;
                    }
                }
            } catch (Throwable $e) {
                error_log('[mobile_table_has_column] ' . $table . ': ' . $e->getMessage());
            }
        }
        return isset($cache[$table][$column]);
    }

    /**
     * Verilen appointment ID listesi için deposit bilgisini toplu çeker.
     * Migration çalışmamışsa boş dizi döner; çağıran taraf default kullanır.
     *
     * @param  array<int|string> $appointmentIds
     * @return array<string, array{required:bool,amount:float|null,status:string|null,paid_at:string|null}>
     */
    function mobile_batch_deposit_info(PDO $pdo, array $appointmentIds): array
    {
        if (empty($appointmentIds)) {
            return [];
        }

        $hasSnapshot = mobile_table_has_column($pdo, 'appointments', 'deposit_required');
        $hasPayments = mobile_table_has_column($pdo, 'appointment_payments', 'id');

        if (!$hasSnapshot && !$hasPayments) {
            return [];
        }

        $ids = array_values(array_unique(array_map('intval', $appointmentIds)));
        if (empty($ids)) {
            return [];
        }
        $placeholders = implode(',', array_fill(0, count($ids), '?'));

        // Aşağıdaki SQL parçaları tamamen iç flag'lerden üretiliyor — kullanıcı girdisi yok.
        // Manuel (IBAN) kapora takibi appointments kolonlarından gelir; yoksa
        // eski iyzico appointment_payments'a düşülür.
        $hasManual = mobile_table_has_column($pdo, 'appointments', 'deposit_status');
        $selDeposit  = $hasSnapshot
            ? 'a.deposit_required, a.deposit_amount,'
            : '0 AS deposit_required, NULL AS deposit_amount,';
        if ($hasManual) {
            $selPayment  = 'a.deposit_status AS deposit_status, a.deposit_reference_code AS deposit_reference_code, a.deposit_paid_at AS deposit_paid_at';
            $joinPayment = '';
        } elseif ($hasPayments) {
            $selPayment  = 'ap.status AS deposit_status, NULL AS deposit_reference_code, ap.paid_at AS deposit_paid_at';
            $joinPayment = 'LEFT JOIN appointment_payments ap ON ap.appointment_id = a.id';
        } else {
            $selPayment  = 'NULL AS deposit_status, NULL AS deposit_reference_code, NULL AS deposit_paid_at';
            $joinPayment = '';
        }

        try {
            $stmt = $pdo->prepare(
                "SELECT a.id AS appointment_id, {$selDeposit} {$selPayment}
                 FROM appointments a {$joinPayment}
                 WHERE a.id IN ({$placeholders})"
            );
            $stmt->execute($ids);
            $map = [];
            foreach ($stmt->fetchAll() as $row) {
                $map[(string)$row['appointment_id']] = [
                    'required' => (bool)($row['deposit_required'] ?? false),
                    'amount'   => $row['deposit_amount'] !== null ? (float)$row['deposit_amount'] : null,
                    'status'   => $row['deposit_status'] ?? null,
                    'reference_code' => $row['deposit_reference_code'] ?? null,
                    'paid_at'  => $row['deposit_paid_at'] ?? null,
                ];
            }
            return $map;
        } catch (Throwable $e) {
            error_log('[mobile_batch_deposit_info] ' . $e->getMessage());
            return [];
        }
    }
}
