<?php
declare(strict_types=1);
/**
 * api/mobile/business/staff-save.php
 * POST - Token sahibi isletmenin personelini ekler/gunceller.
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';
require_once __DIR__ . '/_helpers.php';

wb_method('POST');

$auth = mobile_auth($pdo, ['business', 'admin']);
$ctx = mobile_business_context($pdo, $auth);
$businessId = (int)$ctx['business_id'];
$body = wb_body();

$id = (int)($body['id'] ?? 0);
$name = mb_substr(trim((string)($body['name'] ?? '')), 0, 100);
$role = mb_substr(trim((string)($body['role'] ?? '')), 0, 100);
$phone = preg_replace('/\D+/', '', (string)($body['phone'] ?? '')) ?: null;
$email = strtolower(trim((string)($body['email'] ?? '')));
$isActive = array_key_exists('is_active', $body) ? (bool)$body['is_active'] : true;
$serviceIdsProvided = array_key_exists('service_ids', $body);
$serviceIdsRaw = [];
$serviceIds = [];

if ($name === '') {
    wb_err('name zorunlu', 400, 'missing_name');
}
if ($email !== '' && !filter_var($email, FILTER_VALIDATE_EMAIL)) {
    wb_err('email formati gecersiz', 422, 'invalid_email');
}
if ($serviceIdsProvided) {
    if (!is_array($body['service_ids'])) {
        wb_err('service_ids dizi olmali', 422, 'invalid_service_ids');
    }
    $serviceIdsRaw = $body['service_ids'];
}

foreach ($serviceIdsRaw as $value) {
    $serviceId = filter_var($value, FILTER_VALIDATE_INT);
    if ($serviceId === false || (int)$serviceId <= 0) {
        wb_err('service_ids gecersiz', 422, 'invalid_service_ids');
    }
    $serviceIds[(int)$serviceId] = true;
}
$serviceIds = array_keys($serviceIds);

try {
    $columns = mobile_business_table_columns($pdo, 'staff');
    $hasRole = isset($columns['role']);
    $hasPosition = isset($columns['position']);
    $hasEmail = isset($columns['email']);
    $hasActive = isset($columns['is_active']);
    $hasColor = isset($columns['color']);

    $pdo->beginTransaction();

    if ($serviceIdsProvided && !empty($serviceIds)) {
        $in = implode(',', array_fill(0, count($serviceIds), '?'));
        $svcStmt = $pdo->prepare("SELECT id FROM services WHERE business_id = ? AND id IN ($in)");
        $svcStmt->execute(array_merge([$businessId], $serviceIds));
        $validIds = array_map('intval', $svcStmt->fetchAll(PDO::FETCH_COLUMN));
        sort($validIds);
        $requested = $serviceIds;
        sort($requested);
        if ($validIds !== $requested) {
            $pdo->rollBack();
            wb_err('Bazi hizmetler bu isletmeye ait degil', 403, 'service_forbidden');
        }
    }

    if ($id > 0) {
        $check = $pdo->prepare('SELECT id FROM staff WHERE id = ? AND business_id = ? LIMIT 1 FOR UPDATE');
        $check->execute([$id, $businessId]);
        if (!$check->fetch()) {
            $pdo->rollBack();
            wb_err('Personel bulunamadi', 404, 'staff_not_found');
        }

        $fields = ['name = ?', 'phone = ?'];
        $params = [$name, $phone];

        if ($hasRole) {
            $fields[] = 'role = ?';
            $params[] = $role !== '' ? $role : null;
        } elseif ($hasPosition) {
            $fields[] = 'position = ?';
            $params[] = $role !== '' ? $role : null;
        }
        if ($hasEmail) {
            $fields[] = 'email = ?';
            $params[] = $email !== '' ? $email : null;
        }
        if ($hasActive) {
            $fields[] = 'is_active = ?';
            $params[] = $isActive ? 1 : 0;
        }
        if ($hasColor && array_key_exists('color', $body)) {
            $fields[] = 'color = ?';
            $params[] = trim((string)$body['color']) ?: null;
        }

        $params[] = $id;
        $params[] = $businessId;
        $pdo->prepare('UPDATE staff SET ' . implode(', ', $fields) . ' WHERE id = ? AND business_id = ?')
            ->execute($params);
    } else {
        $insertColumns = ['business_id', 'name', 'phone'];
        $placeholders = ['?', '?', '?'];
        $params = [$businessId, $name, $phone];

        if ($hasRole) {
            $insertColumns[] = 'role';
            $placeholders[] = '?';
            $params[] = $role !== '' ? $role : null;
        } elseif ($hasPosition) {
            $insertColumns[] = 'position';
            $placeholders[] = '?';
            $params[] = $role !== '' ? $role : null;
        }
        if ($hasEmail) {
            $insertColumns[] = 'email';
            $placeholders[] = '?';
            $params[] = $email !== '' ? $email : null;
        }
        if ($hasActive) {
            $insertColumns[] = 'is_active';
            $placeholders[] = '?';
            $params[] = $isActive ? 1 : 0;
        }
        if ($hasColor && array_key_exists('color', $body)) {
            $insertColumns[] = 'color';
            $placeholders[] = '?';
            $params[] = trim((string)$body['color']) ?: null;
        }

        $sql = 'INSERT INTO staff (`' . implode('`, `', $insertColumns) . '`) VALUES (' . implode(', ', $placeholders) . ')';
        $pdo->prepare($sql)->execute($params);
        $id = (int)$pdo->lastInsertId();
    }

    if ($serviceIdsProvided) {
        $pdo->prepare('DELETE FROM staff_services WHERE staff_id = ?')->execute([$id]);
        if (!empty($serviceIds)) {
            $insertSvc = $pdo->prepare('INSERT INTO staff_services (staff_id, service_id) VALUES (?, ?)');
            foreach ($serviceIds as $serviceId) {
                $insertSvc->execute([$id, $serviceId]);
            }
        }
    }

    $staffStmt = $pdo->prepare("
        SELECT
            st.id,
            st.name,
            st.phone,
            " . ($hasRole ? 'st.role' : 'NULL') . " AS role,
            " . ($hasPosition ? 'st.position' : 'NULL') . " AS position,
            " . ($hasEmail ? 'st.email' : 'NULL') . " AS email,
            " . (isset($columns['avatar_url']) ? 'st.avatar_url' : 'NULL') . " AS avatar_url,
            " . (isset($columns['photo_url']) ? 'st.photo_url' : 'NULL') . " AS photo_url,
            " . (isset($columns['photo_opt']) ? 'st.photo_opt' : 'NULL') . " AS photo_opt,
            " . ($hasActive ? 'st.is_active' : '1') . " AS is_active
        FROM staff st
        WHERE st.id = ? AND st.business_id = ?
        LIMIT 1
    ");
    $staffStmt->execute([$id, $businessId]);
    $staff = $staffStmt->fetch();

    $serviceStmt = $pdo->prepare("
        SELECT ss.service_id
        FROM staff_services ss
        INNER JOIN services s ON s.id = ss.service_id AND s.business_id = ?
        WHERE ss.staff_id = ?
        ORDER BY ss.service_id ASC
    ");
    $serviceStmt->execute([$businessId, $id]);
    $savedServiceIds = array_map('intval', $serviceStmt->fetchAll(PDO::FETCH_COLUMN));

    $pdo->commit();

    wb_ok([
        'saved' => true,
        'staff' => mobile_business_staff_item($staff ?: [
            'id' => $id,
            'name' => $name,
            'phone' => $phone,
            'role' => $role !== '' ? $role : null,
            'email' => $email !== '' ? $email : null,
            'is_active' => $isActive,
        ], $savedServiceIds, []),
    ]);
} catch (Throwable $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    error_log('[mobile/business/staff-save.php] ' . $e->getMessage());
    wb_err('Personel kaydedilemedi', 500, 'internal_error');
}
