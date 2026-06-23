<?php
declare(strict_types=1);
/**
 * api/mobile/business/search.php
 * GET — Business dashboard arama. q üzerinden randevu/müşteri/hizmet/personel taraması.
 *
 * Query:
 *   q : min 2 karakter
 *
 * Yanıt:
 * {
 *   "ok": true,
 *   "data": {
 *     "q": "...",
 *     "appointments": [...],
 *     "customers": [...],
 *     "services": [...],
 *     "staff": [...]
 *   }
 * }
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';
require_once __DIR__ . '/_helpers.php';

wb_method('GET');

$auth = mobile_auth($pdo, ['business', 'admin']);
$ctx = mobile_business_context($pdo, $auth);
$businessId = (int)$ctx['business_id'];

$q = trim((string)mobile_param('q', ''));
$empty = [
    'q' => $q,
    'appointments' => [],
    'customers' => [],
    'services' => [],
    'staff' => [],
];

if (mb_strlen($q) < 2) {
    wb_ok($empty);
}
$like = '%' . $q . '%';

try {
    // ── Appointments ─────────────────────────────────────────────────────────
    $apStmt = $pdo->prepare(
        "SELECT a.id, a.start_at, a.status, a.customer_name, a.customer_phone,
                s.name AS service_name
           FROM appointments a
           LEFT JOIN services s ON s.id = a.service_id
          WHERE a.business_id = ?
            AND (a.customer_name LIKE ? OR a.customer_phone LIKE ? OR s.name LIKE ?)
          ORDER BY a.start_at DESC
          LIMIT 8"
    );
    $apStmt->execute([$businessId, $like, $like, $like]);
    $appointments = array_map(static fn(array $r): array => [
        'id' => (string)$r['id'],
        'starts_at' => (string)($r['start_at'] ?? ''),
        'status' => (string)($r['status'] ?? ''),
        'customer_name' => (string)($r['customer_name'] ?? ''),
        'customer_phone' => $r['customer_phone'] ?? null,
        'service_name' => $r['service_name'] ?? null,
    ], $apStmt->fetchAll() ?: []);

    // ── Customers (distinct from appointments) ───────────────────────────────
    $cuStmt = $pdo->prepare(
        "SELECT a.customer_name, a.customer_phone, COUNT(*) AS visit_count,
                MAX(a.start_at) AS last_visit
           FROM appointments a
          WHERE a.business_id = ?
            AND (a.customer_name LIKE ? OR a.customer_phone LIKE ?)
            AND a.customer_name IS NOT NULL AND a.customer_name <> ''
          GROUP BY a.customer_name, a.customer_phone
          ORDER BY last_visit DESC
          LIMIT 8"
    );
    $cuStmt->execute([$businessId, $like, $like]);
    $customers = array_map(static fn(array $r): array => [
        'customer_name' => (string)($r['customer_name'] ?? ''),
        'customer_phone' => $r['customer_phone'] ?? null,
        'visit_count' => (int)($r['visit_count'] ?? 0),
        'last_visit' => (string)($r['last_visit'] ?? ''),
    ], $cuStmt->fetchAll() ?: []);

    // ── Services ─────────────────────────────────────────────────────────────
    $svStmt = $pdo->prepare(
        "SELECT id, name, price, duration_min
           FROM services
          WHERE business_id = ? AND name LIKE ?
          ORDER BY name ASC
          LIMIT 8"
    );
    $svStmt->execute([$businessId, $like]);
    $services = array_map(static fn(array $r): array => [
        'id' => (int)$r['id'],
        'name' => (string)$r['name'],
        'price' => $r['price'] !== null ? (float)$r['price'] : null,
        'duration_minutes' => (int)($r['duration_min'] ?? 0),
    ], $svStmt->fetchAll() ?: []);

    // ── Staff ────────────────────────────────────────────────────────────────
    $stStmt = $pdo->prepare(
        "SELECT id, name, COALESCE(role, '') AS role, phone
           FROM staff
          WHERE business_id = ? AND (name LIKE ? OR COALESCE(role,'') LIKE ?)
          ORDER BY name ASC
          LIMIT 8"
    );
    $stStmt->execute([$businessId, $like, $like]);
    $staff = array_map(static fn(array $r): array => [
        'id' => (int)$r['id'],
        'name' => (string)$r['name'],
        'role' => (string)($r['role'] ?? ''),
        'phone' => $r['phone'] ?? null,
    ], $stStmt->fetchAll() ?: []);

    wb_ok([
        'q' => $q,
        'appointments' => $appointments,
        'customers' => $customers,
        'services' => $services,
        'staff' => $staff,
    ]);
} catch (Throwable $e) {
    error_log('[mobile/business/search.php] ' . $e->getMessage());
    wb_ok($empty);
}
