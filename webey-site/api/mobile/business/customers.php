<?php
declare(strict_types=1);
/**
 * api/mobile/business/customers.php
 * GET — Token sahibi işletmenin GERÇEK müşteri listesi (randevulardan türetilir).
 *
 * Müşteri anahtarı: customer_user_id (>0) varsa o; yoksa normalize telefon.
 * Telefon/e-posta maskeli döner (gizlilik).
 *
 * Query params:
 *   q     : string  (opsiyonel — ad/telefon arama)
 *   limit : int 1-200 (default 100)
 *
 * Yanıt:
 *   summary { total_customers, new_this_month, repeat_rate }
 *   items[] { id, name, phone, email, total_appointments, completed_appointments,
 *             cancelled_appointments, no_show_count, total_spent,
 *             first_visit_at, last_visit_at, favorite_service, is_vip }
 *
 * Auth: business/admin; yalnızca kendi işletmesi.
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';
require_once __DIR__ . '/_helpers.php';

wb_method('GET');

$auth       = mobile_auth($pdo, ['business', 'admin']);
$ctx        = mobile_business_context($pdo, $auth);
$businessId = (int)$ctx['business_id'];

$limit = mobile_limit(mobile_param('limit', 100), 100, 200);

function wb_mask_phone(?string $phone): string
{
    $d = preg_replace('/\D/', '', (string)$phone);
    if ($d === '') {
        return '';
    }
    $last = substr($d, -2);
    return '*** *** ** ' . $last;
}

function wb_mask_email(?string $email): string
{
    $e = trim((string)$email);
    if ($e === '' || !str_contains($e, '@')) {
        return '';
    }
    [$user, $domain] = explode('@', $e, 2);
    $head = mb_substr($user, 0, 1);
    return $head . '***@' . $domain;
}

try {
    $hasUsers = mobile_table_has_column($pdo, 'users', 'id');

    // Ana toplulaştırma — müşteri anahtarına göre grupla.
    $sql = "
        SELECT
            COALESCE(NULLIF(a.customer_user_id, 0), 0) AS customer_user_id,
            CASE
                WHEN a.customer_user_id IS NOT NULL AND a.customer_user_id > 0
                    THEN CONCAT('u', a.customer_user_id)
                WHEN a.customer_phone IS NOT NULL AND a.customer_phone <> ''
                    THEN CONCAT('p', a.customer_phone)
                ELSE CONCAT('n', COALESCE(NULLIF(a.customer_name, ''), 'Müşteri'))
            END AS cust_key,
            COALESCE(MAX(NULLIF(a.customer_name, '')), '') AS name,
            MAX(a.customer_phone) AS phone,
            " . ($hasUsers ? "MAX(u.email)" : "NULL") . " AS email,
            COUNT(*) AS total_appointments,
            SUM(CASE WHEN a.status = 'completed' THEN 1 ELSE 0 END) AS completed_appointments,
            SUM(CASE WHEN a.status IN ('cancelled','rejected','declined') THEN 1 ELSE 0 END) AS cancelled_appointments,
            SUM(CASE WHEN a.status = 'no_show' THEN 1 ELSE 0 END) AS no_show_count,
            SUM(CASE WHEN a.status = 'completed' THEN COALESCE(s.price, 0) ELSE 0 END) AS total_spent,
            MIN(a.start_at) AS first_visit_at,
            MAX(a.start_at) AS last_visit_at
        FROM appointments a
        LEFT JOIN services s ON s.id = a.service_id AND s.business_id = a.business_id
        " . ($hasUsers ? "LEFT JOIN users u ON u.id = a.customer_user_id" : "") . "
        WHERE a.business_id = ?
        GROUP BY cust_key, customer_user_id
        ORDER BY total_appointments DESC, last_visit_at DESC
        LIMIT {$limit}
    ";
    $stmt = $pdo->prepare($sql);
    $stmt->execute([$businessId]);
    $rows = $stmt->fetchAll() ?: [];

    // En çok alınan hizmet (favorite_service) — müşteri anahtarı bazında.
    $favByKey = [];
    try {
        $favStmt = $pdo->prepare("
            SELECT cust_key, svc_name FROM (
                SELECT
                    CASE
                        WHEN a.customer_user_id IS NOT NULL AND a.customer_user_id > 0
                            THEN CONCAT('u', a.customer_user_id)
                        WHEN a.customer_phone IS NOT NULL AND a.customer_phone <> ''
                            THEN CONCAT('p', a.customer_phone)
                        ELSE CONCAT('n', COALESCE(NULLIF(a.customer_name, ''), 'Müşteri'))
                    END AS cust_key,
                    s.name AS svc_name,
                    COUNT(*) AS cnt
                FROM appointments a
                LEFT JOIN services s ON s.id = a.service_id AND s.business_id = a.business_id
                WHERE a.business_id = ? AND s.name IS NOT NULL
                GROUP BY cust_key, s.name
                ORDER BY cnt DESC
            ) t
        ");
        $favStmt->execute([$businessId]);
        foreach ($favStmt->fetchAll() as $fr) {
            $k = (string)$fr['cust_key'];
            if (!isset($favByKey[$k]) && ($fr['svc_name'] ?? null) !== null) {
                $favByKey[$k] = (string)$fr['svc_name'];
            }
        }
    } catch (Throwable $favEx) {
        error_log('[business/customers.php fav] ' . $favEx->getMessage());
    }

    $now = new DateTimeImmutable('now', new DateTimeZone('Europe/Istanbul'));
    $curYm = $now->format('Y-m');
    $newThisMonth = 0;
    $repeatCount = 0;

    $items = [];
    foreach ($rows as $r) {
        $key   = (string)$r['cust_key'];
        $uid   = (int)($r['customer_user_id'] ?? 0);
        $total = (int)$r['total_appointments'];
        $completed = (int)$r['completed_appointments'];
        $spent = (float)$r['total_spent'];
        $firstAt = (string)($r['first_visit_at'] ?? '');
        $isVip = ($completed >= 5) || ($spent >= 2000);

        if ($firstAt !== '' && substr($firstAt, 0, 7) === $curYm) {
            $newThisMonth++;
        }
        if ($total > 1) {
            $repeatCount++;
        }

        $items[] = [
            // id ve detail_key her zaman cust_key (self-describing: u<id> | p<phone> | n<name>)
            // → customer-detail.php aynı anahtarı çözer, "geçersiz id" oluşmaz.
            'id'                     => $key,
            'detail_key'             => $key,
            'name'                   => (string)($r['name'] !== '' ? $r['name'] : 'Müşteri'),
            'phone'                  => wb_mask_phone($r['phone'] ?? ''),
            'email'                  => wb_mask_email($r['email'] ?? ''),
            'total_appointments'     => $total,
            'completed_appointments' => $completed,
            'cancelled_appointments' => (int)$r['cancelled_appointments'],
            'no_show_count'          => (int)$r['no_show_count'],
            'total_spent'            => $spent,
            'first_visit_at'         => $firstAt,
            'last_visit_at'          => (string)($r['last_visit_at'] ?? ''),
            'favorite_service'       => $favByKey[$key] ?? null,
            'is_vip'                 => $isVip,
        ];
    }

    $totalCustomers = count($items);
    $repeatRate = $totalCustomers > 0 ? (int)round($repeatCount / $totalCustomers * 100) : 0;

    wb_ok([
        'summary' => [
            'total_customers' => $totalCustomers,
            'new_this_month'  => $newThisMonth,
            'repeat_rate'     => $repeatRate,
        ],
        'items' => $items,
    ]);
} catch (Throwable $e) {
    error_log('[mobile/business/customers.php] ' . $e->getMessage());
    wb_err('Müşteriler alınamadı', 500, 'internal_error');
}
