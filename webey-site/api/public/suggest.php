<?php
declare(strict_types=1);
/**
 * api/public/suggest.php — Navbar arama önerileri
 * GET ?q=saç
 */

require_once __DIR__ . '/../_public_bootstrap.php';
header('Cache-Control: public, max-age=30');
wb_method('GET');

$q = trim($_GET['q'] ?? '');
if (mb_strlen($q) < 1) { wb_ok([]); }

$like   = '%' . $q . '%';
$limit  = 10;
$result = [];

try {
    $stmt = $pdo->prepare("
        SELECT id, name, city, district
        FROM businesses
        WHERE status = 'active'
          AND onboarding_completed = 1
          AND name LIKE ?
        ORDER BY updated_at DESC
        LIMIT ?
    ");
    $stmt->execute([$like, $limit]);
    foreach ($stmt->fetchAll() as $b) {
        $result[] = [
            'type'     => 'business',
            'id'       => (string)$b['id'],
            'name'     => $b['name'],
            'subtitle' => trim(($b['district'] ?? '') . ' ' . ($b['city'] ?? '')),
        ];
    }

    $remaining = $limit - count($result);
    if ($remaining > 0) {
        try {
            $stmt2 = $pdo->prepare("
                SELECT DISTINCT s.name
                FROM services s
                INNER JOIN businesses b ON b.id = s.business_id
                WHERE b.status = 'active'
                  AND b.onboarding_completed = 1
                  AND s.name LIKE ?
                ORDER BY s.name ASC
                LIMIT ?
            ");
            $stmt2->execute([$like, $remaining]);
            foreach ($stmt2->fetchAll() as $svc) {
                $result[] = ['type' => 'service', 'name' => $svc['name'], 'subtitle' => 'Hizmet'];
            }
        } catch (Throwable) {}
    }

    wb_ok($result);

} catch (Throwable $e) {
    error_log('[suggest.php] ' . $e->getMessage());
    wb_err('Sunucu hatası', 500, 'internal_error');
}