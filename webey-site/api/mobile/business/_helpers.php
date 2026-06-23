<?php
declare(strict_types=1);
/**
 * api/mobile/business/_helpers.php
 * Mobil business endpointleri icin ortak helper fonksiyonlar.
 */

if (!function_exists('mobile_business_context')) {
    function mobile_business_context(PDO $pdo, array $auth): array
    {
        $userId = (int)($auth['user_id'] ?? 0);
        if ($userId <= 0) {
            wb_err('Yetkisiz erisim', 401, 'unauthorized');
        }

        try {
            $stmt = $pdo->prepare("
                SELECT
                    u.id AS user_id,
                    u.email,
                    u.name AS user_name,
                    u.role,
                    au.id AS admin_id,
                    b.id AS business_id,
                    b.name AS business_name,
                    b.status AS business_status
                FROM users u
                INNER JOIN admin_users au ON au.user_id = u.id
                LEFT JOIN businesses b ON b.owner_id = u.id
                WHERE u.id = ?
                LIMIT 1
            ");
            $stmt->execute([$userId]);
            $row = $stmt->fetch();
        } catch (Throwable $e) {
            error_log('[mobile_business_context] ' . $e->getMessage());
            wb_err('Isletme bilgisi alinamadi', 500, 'business_context_failed');
        }

        if (!$row || empty($row['business_id'])) {
            wb_err('Bu islem icin isletme hesabi gerekli', 403, 'business_required');
        }

        return [
            'user_id' => (int)$row['user_id'],
            'admin_id' => (int)$row['admin_id'],
            'business_id' => (int)$row['business_id'],
            'business_name' => (string)($row['business_name'] ?? ''),
            'business_status' => (string)($row['business_status'] ?? ''),
            'role' => (string)($row['role'] ?? ''),
            'email' => (string)($row['email'] ?? ''),
        ];
    }

    function mobile_business_duration_minutes(array $row): ?int
    {
        if ($row['duration_min'] !== null && $row['duration_min'] !== '') {
            return (int)$row['duration_min'];
        }

        $start = strtotime((string)($row['start_at'] ?? ''));
        $end = strtotime((string)($row['end_at'] ?? ''));
        if ($start !== false && $end !== false && $end > $start) {
            return (int)round(($end - $start) / 60);
        }

        return null;
    }

    function mobile_business_appointment_item(array $row): array
    {
        $startsAt = (string)($row['start_at'] ?? '');
        $date = '';
        $time = '';

        try {
            if ($startsAt !== '') {
                $dt = new DateTimeImmutable($startsAt);
                $date = $dt->format('Y-m-d');
                $time = $dt->format('H:i');
            }
        } catch (Throwable) {
        }

        return [
            'id' => (string)$row['id'],
            'status' => (string)($row['status'] ?: 'pending'),
            'starts_at' => $startsAt,
            'ends_at' => (string)($row['end_at'] ?? ''),
            'date' => $date,
            'time' => $time,
            'customer_name' => (string)($row['customer_name'] ?? ''),
            'customer_phone' => $row['customer_phone'] ?? null,
            'service_name' => $row['service_name'] ?? null,
            'staff_name' => $row['staff_name'] ?? null,
            'price' => $row['price'] !== null ? (float)$row['price'] : null,
            'duration_minutes' => mobile_business_duration_minutes($row),
            'note' => $row['notes'] ?? null,
        ];
    }

    function mobile_business_appointment_select_sql(): string
    {
        return "
            SELECT
                a.id,
                a.business_id,
                a.staff_id,
                a.service_id,
                a.customer_user_id,
                a.customer_name,
                a.customer_phone,
                a.customer_email,
                a.start_at,
                a.end_at,
                a.status,
                a.attended,
                a.notes,
                s.name AS service_name,
                s.duration_min,
                s.price,
                st.name AS staff_name,
                b.name AS business_name
            FROM appointments a
            LEFT JOIN services s ON s.id = a.service_id AND s.business_id = a.business_id
            LEFT JOIN staff st ON st.id = a.staff_id AND st.business_id = a.business_id
            LEFT JOIN businesses b ON b.id = a.business_id
        ";
    }

    function mobile_business_require_appointment(
        PDO $pdo,
        int $businessId,
        int $appointmentId,
        bool $forUpdate = false
    ): array {
        if ($appointmentId <= 0) {
            wb_err('appointment_id zorunlu', 400, 'missing_param');
        }

        $sql = mobile_business_appointment_select_sql()
            . ' WHERE a.id = ? AND a.business_id = ? LIMIT 1'
            . ($forUpdate ? ' FOR UPDATE' : '');

        $stmt = $pdo->prepare($sql);
        $stmt->execute([$appointmentId, $businessId]);
        $row = $stmt->fetch();

        if (!$row) {
            wb_err('Randevu bulunamadi', 404, 'appointment_not_found');
        }

        return $row;
    }

    /**
     * Kullanicidan gelen status degeri SQL'e dogrudan eklenmez.
     * Donen kosul hardcoded, parametreleri ise prepared statement ile baglanir.
     *
     * @return array{sql:string,params:array<int,mixed>}
     */
    function mobile_business_status_filter_sql(string $status): array
    {
        return match ($status) {
            'today' => [
                'sql' => ' AND DATE(a.start_at) = CURDATE()',
                'params' => [],
            ],
            'upcoming' => [
                'sql' => " AND a.start_at >= NOW()
                           AND a.status NOT IN ('completed','cancelled','rejected','declined','no_show')",
                'params' => [],
            ],
            'pending' => [
                'sql' => " AND a.status IN ('pending','cancellation_requested')",
                'params' => [],
            ],
            'completed' => [
                'sql' => " AND a.status = 'completed'",
                'params' => [],
            ],
            'cancelled' => [
                'sql' => " AND a.status IN ('cancelled','rejected','declined','no_show')",
                'params' => [],
            ],
            default => [
                'sql' => '',
                'params' => [],
            ],
        };
    }

    function mobile_business_table_columns(PDO $pdo, string $table): array
    {
        static $cache = [];
        $allowed = ['services', 'staff', 'staff_services', 'staff_hours'];
        if (!in_array($table, $allowed, true)) {
            return [];
        }
        if (isset($cache[$table])) {
            return $cache[$table];
        }

        try {
            $stmt = $pdo->query('SHOW COLUMNS FROM `' . $table . '`');
            $columns = [];
            foreach ($stmt->fetchAll() as $row) {
                $field = (string)($row['Field'] ?? '');
                if ($field !== '') {
                    $columns[$field] = true;
                }
            }
            $cache[$table] = $columns;
            return $columns;
        } catch (Throwable $e) {
            error_log('[mobile_business_table_columns] ' . $table . ' ' . $e->getMessage());
            $cache[$table] = [];
            return [];
        }
    }

    function mobile_business_has_column(PDO $pdo, string $table, string $column): bool
    {
        $columns = mobile_business_table_columns($pdo, $table);
        return isset($columns[$column]);
    }

    function mobile_business_service_item(array $row): array
    {
        // Kategori adi: once service_categories.name (join geldiyse),
        // yoksa eski serbest metin `category` fallback.
        $resolvedName = $row['category_resolved_name'] ?? null;
        $textFallback = $row['category'] ?? null;
        $categoryOwner = $row['category_owner'] ?? null;

        return [
            'id' => (int)$row['id'],
            'name' => (string)($row['name'] ?? ''),
            'description' => $row['description'] ?? null,
            'price' => $row['price'] !== null ? (float)$row['price'] : null,
            'duration_minutes' => (int)($row['duration_min'] ?? 0),
            'category' => $resolvedName ?? $textFallback,
            'category_id' => isset($row['category_id']) && $row['category_id'] !== null
                ? (int)$row['category_id']
                : null,
            'category_slug' => $row['category_slug'] ?? null,
            'category_icon_key' => $row['category_icon_key'] ?? null,
            'is_custom_category' => $categoryOwner !== null && (int)$categoryOwner > 0,
            'is_active' => (bool)($row['is_active'] ?? true),
            'sort_order' => (int)($row['sort_order'] ?? 0),
        ];
    }

    function mobile_business_staff_item(array $row, array $serviceIds = [], array $hours = []): array
    {
        $profilePhoto = ($row['profile_photo_url'] ?? '') !== '' ? (string)$row['profile_photo_url'] : null;
        $avatarUrl = $profilePhoto ?? $row['avatar_url'] ?? $row['photo_url'] ?? $row['photo_opt'] ?? null;
        $photoVersion = null;
        if ($profilePhoto !== null && ($row['profile_photo_updated_at'] ?? null) !== null) {
            $photoVersion = (string)strtotime((string)$row['profile_photo_updated_at']);
        }

        return [
            'id' => (int)$row['id'],
            'name' => (string)($row['name'] ?? ''),
            'role' => $row['role'] ?? $row['position'] ?? null,
            'phone' => $row['phone'] ?? null,
            'email' => $row['email'] ?? null,
            'avatar_url' => $avatarUrl,
            'profile_photo_url' => $profilePhoto,
            'profile_photo_version' => $photoVersion,
            'is_active' => (bool)($row['is_active'] ?? true),
            'service_ids' => array_values(array_map('intval', $serviceIds)),
            'hours' => array_values($hours),
        ];
    }

    /**
     * İşletmenin efektif abonelik statüsü (boost uygunluğu için).
     * Açık business_subscriptions kaydı varsa onun statüsü; yoksa
     * created_at + plan.trial_days'ten türetilen 'trial' (deneme süresindeyse)
     * ya da 'unknown'. Eski iyzico `subscriptions` tablosuna BAKMAZ.
     */
    function mobile_business_effective_subscription_status(PDO $pdo, int $businessId): string
    {
        // 1) Açık abonelik kaydı (en güncel).
        try {
            if (mobile_table_has_column($pdo, 'business_subscriptions', 'id')) {
                $stmt = $pdo->prepare(
                    "SELECT status FROM business_subscriptions
                     WHERE business_id = ? ORDER BY id DESC LIMIT 1"
                );
                $stmt->execute([$businessId]);
                $st = $stmt->fetchColumn();
                if ($st !== false && $st !== null) {
                    return (string)$st;
                }
            }
        } catch (Throwable $e) {
            error_log('[mobile_business_effective_subscription_status:sub] ' . $e->getMessage());
        }

        // 2) Türetilmiş deneme (created_at + trial_days).
        $trialDays = 30;
        try {
            if (mobile_table_has_column($pdo, 'business_subscription_plans', 'id')) {
                $p = $pdo->prepare(
                    "SELECT trial_days FROM business_subscription_plans
                     WHERE code = 'webey_business' AND is_active = 1 LIMIT 1"
                );
                $p->execute();
                $td = $p->fetchColumn();
                if ($td !== false && $td !== null) {
                    $trialDays = (int)$td;
                }
            }
        } catch (Throwable $e) {
            // varsayılan 30 gün
        }

        try {
            $b = $pdo->prepare("SELECT created_at FROM businesses WHERE id = ? LIMIT 1");
            $b->execute([$businessId]);
            $createdAt = $b->fetchColumn();
            if ($createdAt) {
                $trialEnd = strtotime((string)$createdAt) + ($trialDays * 86400);
                if ($trialEnd > time()) {
                    return 'trial';
                }
            }
        } catch (Throwable $e) {
            error_log('[mobile_business_effective_subscription_status:trial] ' . $e->getMessage());
        }

        return 'unknown';
    }

    /**
     * Boost uygunluk kontrolü. Tüm şartları değerlendirir; eksik olanları döner.
     * Müşteri sıralaması/görünürlüğü ile İLGİSİ YOKTUR (yalnızca boost talebi gate).
     *
     * @return array{eligible:bool, missing:array<int,array{key:string,label:string}>}
     */
    function mobile_boost_eligibility(PDO $pdo, int $businessId, string $businessStatus): array
    {
        $missing = [];
        $add = static function (array &$m, string $key, string $label): void {
            $m[] = ['key' => $key, 'label' => $label];
        };

        // 1) İşletme hesabı aktif mi?
        if (strtolower(trim($businessStatus)) !== 'active') {
            $add($missing, 'business_inactive', 'İşletme hesabınız aktif değil');
        }

        // 2) Onboarding + konum (businesses tablosundan).
        $b = null;
        try {
            $stmt = $pdo->prepare(
                "SELECT onboarding_completed, latitude, longitude FROM businesses WHERE id = ? LIMIT 1"
            );
            $stmt->execute([$businessId]);
            $b = $stmt->fetch() ?: null;
        } catch (Throwable $e) {
            error_log('[mobile_boost_eligibility:business] ' . $e->getMessage());
        }
        if (!$b || (int)($b['onboarding_completed'] ?? 0) !== 1) {
            $add($missing, 'onboarding_incomplete', 'Kayıt adımlarını tamamlayın');
        }
        $lat = $b['latitude'] ?? null;
        $lng = $b['longitude'] ?? null;
        $hasLocation = $lat !== null && $lng !== null
            && !(abs((float)$lat) < 0.0001 && abs((float)$lng) < 0.0001);
        if (!$hasLocation) {
            $add($missing, 'location_missing', 'Salon konumunu ekleyin');
        }

        // 3) Webey aboneliği trial/active mı?
        $subStatus = mobile_business_effective_subscription_status($pdo, $businessId);
        if (!in_array($subStatus, ['trial', 'active'], true)) {
            $add($missing, 'subscription_inactive', 'Webey aboneliğiniz aktif değil');
        }

        // 4) Kapak görseli var mı? (business_photos is_cover=1 active)
        $hasCover = false;
        try {
            $stmt = $pdo->prepare(
                "SELECT 1 FROM business_photos
                 WHERE business_id = ? AND is_cover = 1 AND status = 'active' LIMIT 1"
            );
            $stmt->execute([$businessId]);
            $hasCover = (bool)$stmt->fetchColumn();
        } catch (Throwable $e) {
            $hasCover = false;
        }
        if (!$hasCover) {
            $add($missing, 'cover_missing', 'Kapak görseli ekleyin');
        }

        // 5) Galeri boş değil mi? (en az 1 aktif fotoğraf)
        $galleryCount = 0;
        try {
            $stmt = $pdo->prepare(
                "SELECT COUNT(*) FROM business_photos WHERE business_id = ? AND status = 'active'"
            );
            $stmt->execute([$businessId]);
            $galleryCount = (int)$stmt->fetchColumn();
        } catch (Throwable $e) {
            $galleryCount = 0;
        }
        if ($galleryCount < 1) {
            $add($missing, 'gallery_empty', 'Galeriye en az 1 fotoğraf ekleyin');
        }

        // 6) En az 3 aktif hizmet var mı?
        $serviceCount = 0;
        try {
            $hasActiveCol = mobile_business_has_column($pdo, 'services', 'is_active');
            $sql = $hasActiveCol
                ? "SELECT COUNT(*) FROM services WHERE business_id = ? AND is_active = 1"
                : "SELECT COUNT(*) FROM services WHERE business_id = ?";
            $stmt = $pdo->prepare($sql);
            $stmt->execute([$businessId]);
            $serviceCount = (int)$stmt->fetchColumn();
        } catch (Throwable $e) {
            $serviceCount = 0;
        }
        if ($serviceCount < 3) {
            $add($missing, 'services_insufficient', 'En az 3 aktif hizmet ekleyin');
        }

        // 7) Çalışma saatleri girilmiş mi? (en az 1 açık gün)
        $hasHours = false;
        try {
            $stmt = $pdo->prepare(
                "SELECT 1 FROM business_hours WHERE business_id = ? AND is_open = 1 LIMIT 1"
            );
            $stmt->execute([$businessId]);
            $hasHours = (bool)$stmt->fetchColumn();
        } catch (Throwable $e) {
            $hasHours = false;
        }
        if (!$hasHours) {
            $add($missing, 'hours_missing', 'Çalışma saatlerini girin');
        }

        return ['eligible' => count($missing) === 0, 'missing' => $missing];
    }
}
