<?php
declare(strict_types=1);
/**
 * api/mobile/business/staff.php
 * GET - Token sahibi isletmenin personelleri.
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';
require_once __DIR__ . '/_helpers.php';

wb_method('GET');

$auth = mobile_auth($pdo, ['business', 'admin']);
$ctx = mobile_business_context($pdo, $auth);
$businessId = (int)$ctx['business_id'];

try {
    $columns = mobile_business_table_columns($pdo, 'staff');
    $hasRole = isset($columns['role']);
    $hasPosition = isset($columns['position']);
    $hasEmail = isset($columns['email']);
    $hasAvatar = isset($columns['avatar_url']);
    $hasPhotoUrl = isset($columns['photo_url']);
    $hasPhotoOpt = isset($columns['photo_opt']);
    $hasActive = isset($columns['is_active']);
    $hasProfilePhoto = isset($columns['profile_photo_url']);

    $stmt = $pdo->prepare("
        SELECT
            st.id,
            st.name,
            st.phone,
            " . ($hasRole ? 'st.role' : 'NULL') . " AS role,
            " . ($hasPosition ? 'st.position' : 'NULL') . " AS position,
            " . ($hasEmail ? 'st.email' : 'NULL') . " AS email,
            " . ($hasAvatar ? 'st.avatar_url' : 'NULL') . " AS avatar_url,
            " . ($hasPhotoUrl ? 'st.photo_url' : 'NULL') . " AS photo_url,
            " . ($hasPhotoOpt ? 'st.photo_opt' : 'NULL') . " AS photo_opt,
            " . ($hasProfilePhoto ? 'st.profile_photo_url' : 'NULL') . " AS profile_photo_url,
            " . ($hasProfilePhoto ? 'st.profile_photo_updated_at' : 'NULL') . " AS profile_photo_updated_at,
            " . ($hasActive ? 'st.is_active' : '1') . " AS is_active
        FROM staff st
        WHERE st.business_id = ?
        ORDER BY st.id ASC
    ");
    $stmt->execute([$businessId]);
    $rows = $stmt->fetchAll();

    $staffIds = array_map(static fn(array $row): int => (int)$row['id'], $rows);
    $servicesByStaff = [];
    $hoursByStaff = [];

    if (!empty($staffIds)) {
        $in = implode(',', array_fill(0, count($staffIds), '?'));

        $serviceStmt = $pdo->prepare("
            SELECT ss.staff_id, ss.service_id
            FROM staff_services ss
            INNER JOIN services s ON s.id = ss.service_id AND s.business_id = ?
            WHERE ss.staff_id IN ($in)
            ORDER BY ss.staff_id ASC, ss.service_id ASC
        ");
        $serviceStmt->execute(array_merge([$businessId], $staffIds));
        foreach ($serviceStmt->fetchAll() as $row) {
            $sid = (int)$row['staff_id'];
            $servicesByStaff[$sid][] = (int)$row['service_id'];
        }

        $hourStmt = $pdo->prepare("
            SELECT staff_id, day, is_open, open_time, close_time
            FROM staff_hours
            WHERE business_id = ? AND staff_id IN ($in)
            ORDER BY staff_id ASC, FIELD(day,'mon','tue','wed','thu','fri','sat','sun')
        ");
        $hourStmt->execute(array_merge([$businessId], $staffIds));
        foreach ($hourStmt->fetchAll() as $row) {
            $sid = (int)$row['staff_id'];
            $hoursByStaff[$sid][] = [
                'day' => (string)$row['day'],
                'is_open' => (bool)$row['is_open'],
                'open_time' => $row['open_time'] !== null ? substr((string)$row['open_time'], 0, 5) : null,
                'close_time' => $row['close_time'] !== null ? substr((string)$row['close_time'], 0, 5) : null,
            ];
        }
    }

    $items = [];
    foreach ($rows as $row) {
        $sid = (int)$row['id'];
        $items[] = mobile_business_staff_item(
            $row,
            $servicesByStaff[$sid] ?? [],
            $hoursByStaff[$sid] ?? []
        );
    }

    wb_ok(['items' => $items]);
} catch (Throwable $e) {
    error_log('[mobile/business/staff.php] ' . $e->getMessage());
    wb_err('Personel listesi alinamadi', 500, 'internal_error');
}
