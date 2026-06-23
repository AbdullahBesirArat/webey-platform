<?php
declare(strict_types=1);
/**
 * api/mobile/business/customer-detail.php
 * GET — Tek müşterinin detay + istatistik + randevu geçmişi (gerçek veri).
 *
 * Query: id (customers.php'deki id: numeric user_id, "u<id>" veya "p<phone>")
 *
 * Yetki: business/admin; yalnızca kendi işletmesinin randevuları.
 * Yanıt: customer, stats, appointments[], services[]
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';
require_once __DIR__ . '/_helpers.php';

wb_method('GET');

$auth       = mobile_auth($pdo, ['business', 'admin']);
$ctx        = mobile_business_context($pdo, $auth);
$businessId = (int)$ctx['business_id'];

$rawId = trim((string)mobile_param('id', ''));
if ($rawId === '') {
    wb_err('id zorunlu', 422, 'missing_id');
}

// Müşteri anahtarını çöz: user_id mi telefon mu?
$userId = 0;
$phone  = '';
$name   = '';
// Anahtar: u<id> | p<phone> | n<name> (customers.php ile birebir). Bare numeric = legacy user_id.
if (str_starts_with($rawId, 'u') && ctype_digit(substr($rawId, 1))) {
    $userId = (int)substr($rawId, 1);
} elseif (str_starts_with($rawId, 'p')) {
    $phone = substr($rawId, 1);
} elseif (str_starts_with($rawId, 'n')) {
    $name = substr($rawId, 1);
} elseif (ctype_digit($rawId)) {
    $userId = (int)$rawId;
} else {
    $name = $rawId;
}

if ($userId <= 0 && $phone === '' && $name === '') {
    wb_err('Geçersiz müşteri kimliği', 422, 'invalid_id');
}

function wb_cd_mask_phone(?string $p): string
{
    $d = preg_replace('/\D/', '', (string)$p);
    return $d === '' ? '' : '*** *** ** ' . substr($d, -2);
}

try {
    // Eşleşme koşulu: user_id > telefon > isim (yalnızca isimle tanınan misafir).
    if ($userId > 0) {
        $matchSql = 'a.customer_user_id = ?';
        $matchArg = $userId;
    } elseif ($phone !== '') {
        $matchSql = 'a.customer_phone = ?';
        $matchArg = $phone;
    } else {
        // İsimle tanınan misafir: yalnızca user_id/telefonu olmayan kayıtlara eşle
        // (aynı isimli kayıtlı/telefonlu müşterileri sızdırma).
        $matchSql = "COALESCE(NULLIF(a.customer_name, ''), '') = ?"
            . " AND (a.customer_user_id IS NULL OR a.customer_user_id = 0)"
            . " AND (a.customer_phone IS NULL OR a.customer_phone = '')";
        $matchArg = $name;
    }

    $hasUsers = mobile_table_has_column($pdo, 'users', 'id');
    $emailSel = $hasUsers ? 'MAX(u.email)' : 'NULL';
    $emailJoin = $hasUsers ? 'LEFT JOIN users u ON u.id = a.customer_user_id' : '';

    // Müşteri başlığı + istatistikler.
    $sumStmt = $pdo->prepare("
        SELECT
            COALESCE(MAX(NULLIF(a.customer_name, '')), '') AS name,
            MAX(a.customer_phone) AS phone,
            {$emailSel} AS email,
            COUNT(*) AS total_appointments,
            SUM(CASE WHEN a.status = 'completed' THEN 1 ELSE 0 END) AS completed_appointments,
            SUM(CASE WHEN a.status IN ('cancelled','rejected','declined') THEN 1 ELSE 0 END) AS cancelled_appointments,
            SUM(CASE WHEN a.status = 'no_show' THEN 1 ELSE 0 END) AS no_show_appointments,
            SUM(CASE WHEN a.status = 'completed' THEN COALESCE(s.price, 0) ELSE 0 END) AS total_spent,
            MIN(a.start_at) AS first_visit_at,
            MAX(a.start_at) AS last_visit_at
        FROM appointments a
        LEFT JOIN services s ON s.id = a.service_id AND s.business_id = a.business_id
        {$emailJoin}
        WHERE a.business_id = ? AND {$matchSql}
    ");
    $sumStmt->execute([$businessId, $matchArg]);
    $sum = $sumStmt->fetch();

    if (!$sum || (int)($sum['total_appointments'] ?? 0) === 0) {
        wb_err('Müşteri bulunamadı', 404, 'customer_not_found');
    }

    $completed = (int)$sum['completed_appointments'];
    $totalSpent = (float)$sum['total_spent'];
    $avgSpent = $completed > 0 ? round($totalSpent / $completed, 2) : 0.0;

    // Randevu geçmişi.
    $hasDepositStatus = mobile_table_has_column($pdo, 'appointments', 'deposit_status');
    $depSel = $hasDepositStatus ? 'a.deposit_status' : "NULL AS deposit_status";
    $hasStaff = mobile_table_has_column($pdo, 'staff', 'id');
    $staffSel = $hasStaff ? 'st.name AS staff_name' : 'NULL AS staff_name';
    $staffJoin = $hasStaff ? 'LEFT JOIN staff st ON st.id = a.staff_id AND st.business_id = a.business_id' : '';

    $apptStmt = $pdo->prepare("
        SELECT a.id, a.start_at, a.status, {$depSel},
               s.name AS service_name, s.price AS price,
               {$staffSel}
        FROM appointments a
        LEFT JOIN services s ON s.id = a.service_id AND s.business_id = a.business_id
        {$staffJoin}
        WHERE a.business_id = ? AND {$matchSql}
        ORDER BY a.start_at DESC, a.id DESC
        LIMIT 100
    ");
    $apptStmt->execute([$businessId, $matchArg]);
    $appointments = array_map(static function (array $r): array {
        $startAt = (string)($r['start_at'] ?? '');
        return [
            'id'             => (string)$r['id'],
            'service_name'   => $r['service_name'] ?? null,
            'staff_name'     => $r['staff_name'] ?? null,
            'date'           => $startAt !== '' ? substr($startAt, 0, 10) : null,
            'time'           => $startAt !== '' ? substr($startAt, 11, 5) : null,
            'status'         => (string)($r['status'] ?? ''),
            'price'          => $r['price'] !== null ? (float)$r['price'] : null,
            'deposit_status' => $r['deposit_status'] ?? null,
        ];
    }, $apptStmt->fetchAll() ?: []);

    // Hizmet bazında özet.
    $svcStmt = $pdo->prepare("
        SELECT s.name AS service_name, COUNT(*) AS cnt,
               SUM(CASE WHEN a.status = 'completed' THEN COALESCE(s.price, 0) ELSE 0 END) AS total_spent
        FROM appointments a
        LEFT JOIN services s ON s.id = a.service_id AND s.business_id = a.business_id
        WHERE a.business_id = ? AND {$matchSql} AND s.name IS NOT NULL
        GROUP BY s.name
        ORDER BY cnt DESC
    ");
    $svcStmt->execute([$businessId, $matchArg]);
    $serviceRows = $svcStmt->fetchAll() ?: [];
    $services = array_map(static fn(array $r): array => [
        'service_name' => (string)$r['service_name'],
        'count'        => (int)$r['cnt'],
        'total_spent'  => (float)($r['total_spent'] ?? 0),
    ], $serviceRows);
    $favoriteService = $serviceRows !== [] ? (string)$serviceRows[0]['service_name'] : null;

    $isVip = ($completed >= 5) || ($totalSpent >= 2000);

    wb_ok([
        'customer' => [
            'id'             => $rawId,
            'name'           => (string)($sum['name'] !== '' ? $sum['name'] : 'Müşteri'),
            'phone'          => wb_cd_mask_phone($sum['phone'] ?? ''),
            'is_vip'         => $isVip,
            'first_visit_at' => (string)($sum['first_visit_at'] ?? ''),
            'last_visit_at'  => (string)($sum['last_visit_at'] ?? ''),
        ],
        'stats' => [
            'total_appointments'     => (int)$sum['total_appointments'],
            'completed_appointments' => $completed,
            'cancelled_appointments' => (int)$sum['cancelled_appointments'],
            'no_show_appointments'   => (int)$sum['no_show_appointments'],
            'total_spent'            => $totalSpent,
            'average_spent'          => $avgSpent,
            'repeat_count'           => (int)$sum['total_appointments'],
            'favorite_service'       => $favoriteService,
        ],
        'appointments' => $appointments,
        'services'     => $services,
    ]);
} catch (Throwable $e) {
    error_log('[mobile/business/customer-detail.php] ' . $e->getMessage());
    wb_err('Müşteri detayı alınamadı', 500, 'internal_error');
}
