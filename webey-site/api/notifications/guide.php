<?php
declare(strict_types=1);
/**
 * api/notifications/guide.php
 * POST { page } | { page: "bootstrap" }
 * Admin sayfaları için rehber bildirimlerini işletme bazında yalnızca bir kez üretir.
 */

require_once __DIR__ . '/../admin/_bootstrap.php';
wb_method('POST');

$bid = (int)($user['business_id'] ?? 0);
if ($bid <= 0) {
    wb_err('İşletme bulunamadı', 404, 'business_not_found');
}

$in = wb_body();
$page = trim((string)($in['page'] ?? ''));

$guides = [
    'calendar' => [
        'title'   => 'Takvim sayfasını kullanın',
        'message' => 'Takvim sayfasında randevularınızı onaylayabilir, yönetebilir ve görebilirsiniz.',
        'link'    => 'calendar.html',
    ],
    'staff' => [
        'title'   => 'Personel ekranını keşfedin',
        'message' => 'Personel ekleyip çıkarabilir ve personellerinizin hangi hizmetleri yapabileceğini seçebilirsiniz.',
        'link'    => 'staff.html',
    ],
    'settings' => [
        'title'   => 'Dükkan sayfanızı yönetin',
        'message' => 'İşletme bilgilerinizi, iletişim numaranızı, açık saatlerinizi, görsellerinizi, hizmetlerinizi ve hizmet ücretlerinizi yönetebilirsiniz.',
        'link'    => 'settings.html',
    ],
    'notifications' => [
        'title'   => 'Bildirim merkezi hazır',
        'message' => 'Bu sayfada tüm bildirimlerinizi görüntüleyebilir ve yönetebilirsiniz.',
        'link'    => 'bildirimler.html',
    ],
];

if (!isset($guides[$page])) {
    if ($page !== 'bootstrap') {
        wb_err('Geçersiz sayfa', 400, 'invalid_page');
    }
}

try {
    $fetchRow = static function(int $id) use ($pdo, $bid): ?array {
        $stmt = $pdo->prepare("
            SELECT id, type, customer_name, customer_phone, service_name, staff_name,
                   appointment_start, result, is_read, created_at, appointment_id
            FROM notifications
            WHERE id = ? AND business_id = ?
            LIMIT 1
        ");
        $stmt->execute([$id, $bid]);
        $row = $stmt->fetch();
        return $row ?: null;
    };

    $normalizeItem = static function(array $row): array {
        return [
            'id'               => (string)$row['id'],
            'type'             => (string)$row['type'],
            'customerName'     => $row['customer_name'] ?? '',
            'customerPhone'    => $row['customer_phone'] ?? null,
            'serviceName'      => $row['service_name'] ?? null,
            'staffName'        => $row['staff_name'] ?? null,
            'appointmentStart' => $row['appointment_start'] ?? null,
            'startFmt'         => null,
            'result'           => $row['result'] ?? 'info',
            'isRead'           => (bool)$row['is_read'],
            'createdAt'        => $row['created_at'],
            'appointmentId'    => $row['appointment_id'] ? (string)$row['appointment_id'] : null,
            'title'            => $row['customer_name'] ?? '',
            'message'          => $row['service_name'] ?? '',
            'linkUrl'          => $row['staff_name'] ?? '',
            'guideKey'         => $row['result'] ?? '',
            'category'         => 'system',
        ];
    };

    $ensureGuide = static function(string $guidePage) use ($pdo, $bid, $guides, $fetchRow): array {
        $stmt = $pdo->prepare("
            SELECT id, type, customer_name, customer_phone, service_name, staff_name,
                   appointment_start, result, is_read, created_at, appointment_id
            FROM notifications
            WHERE business_id = ? AND type = 'guide' AND result = ? AND is_deleted = 0
            ORDER BY id ASC
        ");
        $stmt->execute([$bid, $guidePage]);
        $rows = $stmt->fetchAll();
        $row = $rows[0] ?? null;

        if (count($rows) > 1) {
            $duplicateIds = array_map(static fn(array $r): int => (int)$r['id'], array_slice($rows, 1));
            $placeholders = implode(',', array_fill(0, count($duplicateIds), '?'));
            $params = array_merge($duplicateIds, [$bid]);
            $pdo->prepare("UPDATE notifications SET is_deleted = 1, is_read = 1 WHERE id IN ($placeholders) AND business_id = ?")
                ->execute($params);
        }

        if ($row) {
            $pdo->prepare("UPDATE notifications SET is_read = 1 WHERE id = ? AND business_id = ?")
                ->execute([(int)$row['id'], $bid]);
            $row['is_read'] = 1;
            return ['created' => false, 'row' => $row];
        }

        $guide = $guides[$guidePage];
        $pdo->prepare("
            INSERT INTO notifications
                (business_id, type, customer_name, service_name, staff_name, result, is_read, created_at)
            VALUES
                (?, 'guide', ?, ?, ?, ?, 1, NOW())
        ")->execute([
            $bid,
            $guide['title'],
            $guide['message'],
            $guide['link'],
            $guidePage,
        ]);

        $id = (int)$pdo->lastInsertId();
        $row = $fetchRow($id);

        return ['created' => true, 'row' => $row];
    };

    if ($page === 'bootstrap') {
        $items = [];
        $createdItems = [];
        foreach (array_keys($guides) as $guidePage) {
            $result = $ensureGuide($guidePage);
            if (!empty($result['row'])) {
                $items[] = $normalizeItem($result['row']);
                if (!empty($result['created'])) {
                    $createdItems[] = $normalizeItem($result['row']);
                }
            }
        }
        wb_ok([
            'created' => count($createdItems) > 0,
            'items' => $items,
            'createdItems' => $createdItems,
        ]);
    }

    $result = $ensureGuide($page);
    if (empty($result['row'])) {
        wb_ok(['created' => false, 'item' => null]);
    }

    wb_ok([
        'created' => (bool)$result['created'],
        'item' => $normalizeItem($result['row']),
    ]);
} catch (Throwable $e) {
    error_log('[notifications/guide] ' . $e->getMessage());
    wb_err('Rehber bildirimi oluşturulamadı', 500, 'internal_error');
}
