<?php
declare(strict_types=1);
require_once __DIR__ . '/_bootstrap.php';
wb_method('GET');

$userId = $user['user_id'];
$phone  = $user['phone'] ?? '';

try {
    // ── 1. ID'leri topla: customer_user_id + phone eşleşmesi ──────────────
    $ids = [];

    // a) customer_user_id ile doğrudan eşleşen randevular
    $s1 = $pdo->prepare("
        SELECT id FROM appointments
        WHERE customer_user_id = ?
          AND start_at >= NOW() - INTERVAL 12 MONTH
    ");
    $s1->execute([$userId]);
    foreach ($s1->fetchAll() as $r) $ids[] = (int)$r['id'];

    // b) phone eşleşmesi (kayıt sırasında user_id bağlanmamış olabilir)
    $phones = [];
    $sp = preg_replace('/\D/', '', $phone);
    if ($sp) $phones[] = substr($sp, -10);

    $cRow = $pdo->prepare("SELECT phone FROM customers WHERE user_id = ? LIMIT 1");
    $cRow->execute([$userId]);
    $cp = preg_replace('/\D/', '', $cRow->fetchColumn() ?: '');
    if ($cp) { $t = substr($cp, -10); if (!in_array($t, $phones)) $phones[] = $t; }

    if ($phones) {
        $ph = implode(',', array_fill(0, count($phones), '?'));
        $s2 = $pdo->prepare("
            SELECT id FROM appointments
            WHERE RIGHT(REPLACE(REPLACE(REPLACE(COALESCE(customer_phone,''),'+',''),' ',''),'-',''), 10) IN ($ph)
              AND start_at >= NOW() - INTERVAL 12 MONTH
        ");
        $s2->execute($phones);
        foreach ($s2->fetchAll() as $r) $ids[] = (int)$r['id'];
    }

    $ids = array_values(array_unique($ids));

    if (!$ids) { wb_ok([]); }

    // ── 2. Tam veriyi çek ─────────────────────────────────────────────────
    $ph2  = implode(',', array_fill(0, count($ids), '?'));
    $stmt = $pdo->prepare("
        SELECT
            a.id,
            a.business_id   AS businessId,
            a.start_at      AS startAt,
            a.end_at        AS endAt,
            a.status,
            a.notes,
            a.customer_name,
            s.name          AS serviceName,
            s.duration_min  AS serviceDuration,
            b.name          AS businessName,
            b.images_json,
            b.city, b.district, b.address_line, b.map_url
        FROM appointments a
        LEFT JOIN businesses b ON b.id = a.business_id
        LEFT JOIN services   s ON s.id = a.service_id
        WHERE a.id IN ($ph2)
        ORDER BY a.start_at DESC
    ");
    $stmt->execute($ids);
    $rows = $stmt->fetchAll();

    $data = array_map(function($r) {
        $logo = null;
        if (!empty($r['images_json'])) {
            $img  = json_decode($r['images_json'], true) ?? [];
            $c    = $img['cover_opt'] ?? ($img['cover'] ?? null);
            $logo = is_array($c) ? ($c[0] ?? null) : $c;
            if (!$logo && !empty($img['salon_opt'])) {
                $logo = is_array($img['salon_opt']) ? ($img['salon_opt'][0] ?? null) : $img['salon_opt'];
            }
            if (!$logo && !empty($img['salon'])) {
                $logo = is_array($img['salon']) ? ($img['salon'][0] ?? null) : $img['salon'];
            }
            if (!$logo) $logo = $img['logo'] ?? null;
        }
        $services = [];
        $note = (string)($r['notes'] ?? '');
        if ($note !== '' && preg_match('/hizmet\s*:\s*(.+)$/iu', $note, $m)) {
            $parts = preg_split('/\s*,\s*/u', trim((string)$m[1])) ?: [];
            foreach ($parts as $part) {
                $name = trim((string)$part);
                if ($name !== '') {
                    $services[] = ['name' => $name];
                }
            }
        }
        if (!$services && !empty($r['serviceName'])) {
            $services[] = [
                'name'        => $r['serviceName'],
                'durationMin' => (int)($r['serviceDuration'] ?? 0),
            ];
        }
        return [
            'id'           => (string)$r['id'],
            'businessId'   => (string)($r['businessId'] ?? ''),
            'businessName' => $r['businessName'] ?? 'İşletme',
            'logo'         => $logo,
            'startAt'      => $r['startAt'],
            'endAt'        => $r['endAt'],
            'status'       => $r['status'] ?? 'pending',
            'serviceTitle' => $services ? implode(', ', array_map(static fn($s) => (string)($s['name'] ?? ''), $services)) : ($r['serviceName'] ?? 'Hizmet'),
            'services'     => $services,
            'address' => [
                'city'          => $r['city']         ?? '',
                'district'      => $r['district']     ?? '',
                'street'        => $r['address_line'] ?? '',
                'googleMapsUrl' => $r['map_url']      ?? '',
            ],
        ];
    }, $rows);

    wb_ok($data);

} catch (Throwable $e) {
    error_log('[user/appointments.php] ' . $e->getMessage());
    wb_err('Randevular alınamadı.', 500, 'internal_error');
}
