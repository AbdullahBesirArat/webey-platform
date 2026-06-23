<?php
declare(strict_types=1);
/**
 * api/mobile/business/action-center.php
 * GET - Token sahibi isletme icin gercek veriyle aksiyon listesi.
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';
require_once __DIR__ . '/_helpers.php';
require_once __DIR__ . '/../_campaigns.php';

wb_method('GET');

$auth = mobile_auth($pdo, ['business', 'admin']);
$ctx = mobile_business_context($pdo, $auth);
$businessId = (int)$ctx['business_id'];

function wb_action_center_count(PDO $pdo, string $sql, array $params): int
{
    try {
        $stmt = $pdo->prepare($sql);
        $stmt->execute($params);
        return (int)$stmt->fetchColumn();
    } catch (Throwable $e) {
        error_log('[mobile/business/action-center.php count] ' . $e->getMessage());
        return 0;
    }
}

function wb_action_center_add(array &$items, string $id, string $title, string $description, string $meta, string $status, string $icon, string $target, int $count = 0): void
{
    $items[] = [
        'id' => $id,
        'title' => $title,
        'description' => $description,
        'meta' => $meta,
        'status' => $status,
        'icon' => $icon,
        'target' => $target,
        'count' => $count,
    ];
}

try {
    $items = [];

    $depositPending = mobile_table_has_column($pdo, 'appointments', 'deposit_status')
        ? wb_action_center_count(
            $pdo,
            "SELECT COUNT(*) FROM appointments
             WHERE business_id = ?
               AND deposit_required = 1
               AND deposit_status IN ('customer_marked_sent','pending')
               AND status NOT IN ('cancelled','rejected','declined','no_show','completed')",
            [$businessId]
        )
        : 0;
    if ($depositPending > 0) {
        wb_action_center_add(
            $items,
            'pending_deposits',
            'Bekleyen kaporalari kontrol et',
            $depositPending . ' randevuda kapora onayi bekleniyor.',
            'Odeme',
            'urgent',
            'wallet',
            'deposits',
            $depositPending
        );
    }

    $pendingAppointments = wb_action_center_count(
        $pdo,
        "SELECT COUNT(*) FROM appointments
         WHERE business_id = ?
           AND status IN ('pending','cancellation_requested')",
        [$businessId]
    );
    if ($pendingAppointments > 0) {
        wb_action_center_add(
            $items,
            'pending_appointments',
            'Bekleyen randevulari yanitla',
            $pendingAppointments . ' randevu isletme onayi bekliyor.',
            'Takvim',
            'urgent',
            'calendar',
            'calendar_pending',
            $pendingAppointments
        );
    }

    $todayAppointments = wb_action_center_count(
        $pdo,
        "SELECT COUNT(*) FROM appointments
         WHERE business_id = ?
           AND DATE(start_at) = CURDATE()
           AND status NOT IN ('cancelled','rejected','declined','no_show')",
        [$businessId]
    );
    if ($todayAppointments > 0) {
        wb_action_center_add(
            $items,
            'today_appointments',
            'Bugunku randevulari hazirla',
            'Bugun ' . $todayAppointments . ' musteri randevusu var.',
            'Bugun',
            'today',
            'event',
            'calendar_today',
            $todayAppointments
        );
    }

    $outcomePending = wb_action_center_count(
        $pdo,
        "SELECT COUNT(*) FROM appointments
         WHERE business_id = ?
           AND start_at < NOW()
           AND status IN ('pending','approved','confirmed')",
        [$businessId]
    );
    if ($outcomePending > 0) {
        wb_action_center_add(
            $items,
            'outcome_pending',
            'Gecmis randevulari kapat',
            $outcomePending . ' randevunun sonucu henuz isaretlenmedi.',
            'Takvim',
            'urgent',
            'check',
            'calendar_outcome',
            $outcomePending
        );
    }

    $activeServices = wb_action_center_count(
        $pdo,
        mobile_table_has_column($pdo, 'services', 'is_active')
            ? "SELECT COUNT(*) FROM services WHERE business_id = ? AND is_active = 1"
            : "SELECT COUNT(*) FROM services WHERE business_id = ?",
        [$businessId]
    );
    if ($activeServices < 3) {
        wb_action_center_add(
            $items,
            'services_missing',
            'Hizmet listesini tamamla',
            'Kesif ve rezervasyon icin en az 3 aktif hizmet onerilir.',
            $activeServices . '/3 hizmet',
            'suggestion',
            'services',
            'services',
            $activeServices
        );
    }

    $activeStaff = wb_action_center_count(
        $pdo,
        mobile_table_has_column($pdo, 'staff', 'is_active')
            ? "SELECT COUNT(*) FROM staff WHERE business_id = ? AND is_active = 1"
            : "SELECT COUNT(*) FROM staff WHERE business_id = ?",
        [$businessId]
    );
    if ($activeStaff < 1) {
        wb_action_center_add(
            $items,
            'staff_missing',
            'Ekip uyelerini ekle',
            'Musterilerin uzman secmesi icin en az 1 aktif personel ekleyin.',
            'Ekip',
            'suggestion',
            'staff',
            'staff',
            $activeStaff
        );
    }

    $openDays = wb_action_center_count(
        $pdo,
        "SELECT COUNT(*) FROM business_hours WHERE business_id = ? AND is_open = 1",
        [$businessId]
    );
    if ($openDays < 1) {
        wb_action_center_add(
            $items,
            'hours_missing',
            'Calisma saatlerini gir',
            'Randevu alinabilmesi icin haftada en az bir acik gun tanimlayin.',
            'Takvim',
            'suggestion',
            'hours',
            'hours',
            $openDays
        );
    }

    $galleryCount = wb_action_center_count(
        $pdo,
        "SELECT COUNT(*) FROM business_photos WHERE business_id = ? AND status = 'active'",
        [$businessId]
    );
    if ($galleryCount < 3) {
        wb_action_center_add(
            $items,
            'gallery_missing',
            'Profil fotograflarini guncelle',
            'Salon atmosferi icin galeriye en az 3 aktif gorsel ekleyin.',
            $galleryCount . '/3 gorsel',
            'suggestion',
            'gallery',
            'gallery',
            $galleryCount
        );
    }

    $depositRate = null;
    try {
        if (mobile_table_has_column($pdo, 'deposit_policies', 'rate_pct')) {
            $stmt = $pdo->prepare('SELECT rate_pct FROM deposit_policies WHERE business_id = ? LIMIT 1');
            $stmt->execute([$businessId]);
            $raw = $stmt->fetchColumn();
            $depositRate = $raw !== false ? (int)$raw : null;
        }
    } catch (Throwable $e) {
        error_log('[mobile/business/action-center.php deposit_policy] ' . $e->getMessage());
    }
    $depositRequired = $depositRate !== null && $depositRate > 0;
    if (!$depositRequired && mobile_table_has_column($pdo, 'businesses', 'deposit_required')) {
        $depositRequired = wb_action_center_count(
            $pdo,
            "SELECT COUNT(*) FROM businesses WHERE id = ? AND deposit_required = 1",
            [$businessId]
        ) > 0;
    }
    if (!$depositRequired) {
        wb_action_center_add(
            $items,
            'deposit_policy_missing',
            'Kapora politikasini belirle',
            'No-show riskini azaltmak icin sabit veya yuzdelik kapora secin.',
            'Kapora',
            'suggestion',
            'deposit',
            'deposit_policy',
            0
        );
    }

    $hasIban = false;
    try {
        if (mobile_table_has_column($pdo, 'business_payment_settings', 'iban')) {
            $stmt = $pdo->prepare(
                "SELECT iban FROM business_payment_settings WHERE business_id = ? LIMIT 1"
            );
            $stmt->execute([$businessId]);
            $iban = trim((string)($stmt->fetchColumn() ?: ''));
            $hasIban = $iban !== '';
        }
    } catch (Throwable $e) {
        error_log('[mobile/business/action-center.php iban] ' . $e->getMessage());
    }
    if ($depositRequired && !$hasIban) {
        wb_action_center_add(
            $items,
            'iban_missing',
            'IBAN bilgilerini tamamla',
            'Kapora aktif ancak musteri odemesi icin IBAN eksik.',
            'Odeme',
            'urgent',
            'bank',
            'payment_settings',
            0
        );
    }

    // Kampanya önerisi (opsiyonel) — işletmenin hiç (archived hariç) kampanyası
    // yoksa öneri olarak göster. Yayına hazırlık için ZORUNLU değil.
    if (wb_campaign_tables_ready($pdo)) {
        $campaignCount = wb_action_center_count(
            $pdo,
            "SELECT COUNT(*) FROM business_campaigns WHERE business_id = ? AND status <> 'archived'",
            [$businessId]
        );
        if ($campaignCount < 1) {
            wb_action_center_add(
                $items,
                'campaign_missing',
                'İlk kampanyanı oluştur',
                'Hizmetlerini öne çıkaracak indirim ve fırsatlar sun.',
                'Kampanya',
                'suggestion',
                'campaign',
                'campaigns',
                0
            );
        }
    }

    $summary = [
        'total' => count($items),
        'urgent' => count(array_filter($items, static fn(array $item): bool => $item['status'] === 'urgent')),
        'today' => count(array_filter($items, static fn(array $item): bool => $item['status'] === 'today')),
        'suggestion' => count(array_filter($items, static fn(array $item): bool => $item['status'] === 'suggestion')),
        'done' => 0,
    ];

    wb_ok([
        'summary' => $summary,
        'items' => $items,
    ]);
} catch (Throwable $e) {
    error_log('[mobile/business/action-center.php] ' . $e->getMessage());
    wb_err('Aksiyon merkezi alinamadi', 500, 'internal_error');
}
