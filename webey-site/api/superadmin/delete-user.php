<?php
declare(strict_types=1);

require_once __DIR__ . '/_bootstrap.php';

wb_method('GET', 'POST');

$currentSuperadminId = (int)($user['user_id'] ?? 0);

function wb_sa_in_clause(array $values): array
{
    $values = array_values(array_filter($values, static fn($v) => $v !== null && $v !== ''));
    if (!$values) {
        return ['sql' => '', 'params' => []];
    }
    return [
        'sql' => implode(',', array_fill(0, count($values), '?')),
        'params' => $values,
    ];
}

function wb_sa_collect_preview(PDO $pdo, int $userId): ?array
{
    $stmt = $pdo->prepare(
        "SELECT
            u.id,
            u.email,
            u.name,
            u.role,
            u.created_at,
            u.last_login_at,
            b.id AS business_id,
            b.name AS business_name,
            b.status AS business_status,
            c.id AS customer_id,
            c.email AS customer_email,
            c.phone AS customer_phone
         FROM users u
         LEFT JOIN businesses b ON b.owner_id = u.id
         LEFT JOIN customers c ON c.user_id = u.id
         WHERE u.id = ?
         LIMIT 1"
    );
    $stmt->execute([$userId]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$row) {
        return null;
    }

    $businessId = isset($row['business_id']) ? (int)$row['business_id'] : 0;
    $counts = [
        'subscriptions' => 0,
        'paymentCards' => 0,
        'promoUses' => 0,
        'pushSubscriptions' => 0,
        'userNotifications' => 0,
        'customerAppointments' => 0,
        'businessAppointments' => 0,
        'services' => 0,
        'staff' => 0,
        'invoices' => 0,
    ];

    $q = $pdo->prepare('SELECT COUNT(*) FROM subscriptions WHERE user_id = ?');
    $q->execute([$userId]);
    $counts['subscriptions'] = (int)$q->fetchColumn();

    $q = $pdo->prepare('SELECT COUNT(*) FROM payment_cards WHERE user_id = ?');
    $q->execute([$userId]);
    $counts['paymentCards'] = (int)$q->fetchColumn();

    $q = $pdo->prepare('SELECT COUNT(*) FROM promo_code_uses WHERE user_id = ?');
    $q->execute([$userId]);
    $counts['promoUses'] = (int)$q->fetchColumn();

    $q = $pdo->prepare('SELECT COUNT(*) FROM push_subscriptions WHERE user_id = ?');
    $q->execute([$userId]);
    $counts['pushSubscriptions'] = (int)$q->fetchColumn();

    $q = $pdo->prepare('SELECT COUNT(*) FROM user_notifications WHERE user_id = ?');
    $q->execute([$userId]);
    $counts['userNotifications'] = (int)$q->fetchColumn();

    $q = $pdo->prepare('SELECT COUNT(*) FROM appointments WHERE customer_user_id = ?');
    $q->execute([$userId]);
    $counts['customerAppointments'] = (int)$q->fetchColumn();

    $q = $pdo->prepare('SELECT COUNT(*) FROM invoices WHERE user_id = ?');
    $q->execute([$userId]);
    $counts['invoices'] = (int)$q->fetchColumn();

    if ($businessId > 0) {
        $q = $pdo->prepare('SELECT COUNT(*) FROM appointments WHERE business_id = ?');
        $q->execute([$businessId]);
        $counts['businessAppointments'] = (int)$q->fetchColumn();

        $q = $pdo->prepare('SELECT COUNT(*) FROM services WHERE business_id = ?');
        $q->execute([$businessId]);
        $counts['services'] = (int)$q->fetchColumn();

        $q = $pdo->prepare('SELECT COUNT(*) FROM staff WHERE business_id = ?');
        $q->execute([$businessId]);
        $counts['staff'] = (int)$q->fetchColumn();

        $q = $pdo->prepare('SELECT COUNT(*) FROM promo_code_uses WHERE business_id = ?');
        $q->execute([$businessId]);
        $counts['promoUses'] += (int)$q->fetchColumn();
    }

    return [
        'user' => [
            'id' => (string)$row['id'],
            'email' => (string)$row['email'],
            'name' => $row['name'] !== null ? (string)$row['name'] : null,
            'role' => (string)$row['role'],
            'createdAt' => $row['created_at'],
            'lastLoginAt' => $row['last_login_at'],
        ],
        'business' => $businessId > 0 ? [
            'id' => (string)$businessId,
            'name' => (string)($row['business_name'] ?? ''),
            'status' => (string)($row['business_status'] ?? ''),
        ] : null,
        'customer' => !empty($row['customer_id']) ? [
            'id' => (string)$row['customer_id'],
            'email' => $row['customer_email'] !== null ? (string)$row['customer_email'] : null,
            'phone' => $row['customer_phone'] !== null ? (string)$row['customer_phone'] : null,
        ] : null,
        'counts' => $counts,
    ];
}

if (strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'GET') {
    $userId = (int)($_GET['user_id'] ?? 0);
    if ($userId <= 0) {
        wb_err('Geçerli bir kullanıcı ID girin', 422, 'invalid_user_id');
    }

    $preview = wb_sa_collect_preview($pdo, $userId);
    if (!$preview) {
        wb_err('Kullanıcı bulunamadı', 404, 'user_not_found');
    }

    $preview['canDelete'] = ((int)$preview['user']['id'] !== $currentSuperadminId)
        && (($preview['user']['role'] ?? '') !== 'superadmin');

    wb_ok($preview);
}

$body = wb_body();
$userId = (int)($body['user_id'] ?? 0);
$confirmText = trim((string)($body['confirm_text'] ?? ''));
$confirmNormalized = strtoupper(str_replace('İ', 'I', $confirmText));

if ($userId <= 0) {
    wb_err('Geçerli bir kullanıcı ID girin', 422, 'invalid_user_id');
}

if ($confirmNormalized !== 'SIL') {
    wb_err('Silme işlemi için SIL yazılmalı', 422, 'confirm_text_required');
}

if ($userId === $currentSuperadminId) {
    wb_err('Aktif superadmin hesabı silinemez', 403, 'cannot_delete_self');
}

$preview = wb_sa_collect_preview($pdo, $userId);
if (!$preview) {
    wb_err('Kullanıcı bulunamadı', 404, 'user_not_found');
}

if (($preview['user']['role'] ?? '') === 'superadmin') {
    wb_err('Superadmin hesabı bu araçla silinemez', 403, 'cannot_delete_superadmin');
}

$targetEmail = trim((string)($preview['user']['email'] ?? ''));
$customerEmail = trim((string)($preview['customer']['email'] ?? ''));
$customerPhone = trim((string)($preview['customer']['phone'] ?? ''));
$businessId = (int)($preview['business']['id'] ?? 0);

try {
    $pdo->beginTransaction();

    $appointmentIds = [];
    $apptStmt = $businessId > 0
        ? $pdo->prepare('SELECT id FROM appointments WHERE customer_user_id = ? OR business_id = ?')
        : $pdo->prepare('SELECT id FROM appointments WHERE customer_user_id = ?');
    $apptStmt->execute($businessId > 0 ? [$userId, $businessId] : [$userId]);
    $appointmentIds = array_map('intval', array_column($apptStmt->fetchAll(PDO::FETCH_ASSOC), 'id'));

    $subscriptionIds = [];
    $subStmt = $pdo->prepare('SELECT id FROM subscriptions WHERE user_id = ?');
    $subStmt->execute([$userId]);
    $subscriptionIds = array_map('intval', array_column($subStmt->fetchAll(PDO::FETCH_ASSOC), 'id'));

    if ($appointmentIds) {
        $in = wb_sa_in_clause($appointmentIds);
        $pdo->prepare("DELETE FROM appointment_reminders WHERE appointment_id IN ({$in['sql']})")->execute($in['params']);
        $pdo->prepare("DELETE FROM appointment_logs WHERE appointment_id IN ({$in['sql']})")->execute($in['params']);
        $pdo->prepare("DELETE FROM notifications WHERE appointment_id IN ({$in['sql']})")->execute($in['params']);
        $pdo->prepare("DELETE FROM sms_queue WHERE appointment_id IN ({$in['sql']})")->execute($in['params']);
        $pdo->prepare("DELETE FROM user_notifications WHERE appointment_id IN ({$in['sql']})")->execute($in['params']);
        $pdo->prepare("DELETE FROM appointments WHERE id IN ({$in['sql']})")->execute($in['params']);
    }

    $pdo->prepare('DELETE FROM appointment_logs WHERE actor_user_id = ?')->execute([$userId]);

    if ($businessId > 0) {
        $pdo->prepare('DELETE FROM notifications WHERE business_id = ?')->execute([$businessId]);
        $pdo->prepare('DELETE FROM slot_locks WHERE business_id = ?')->execute([$businessId]);
        $pdo->prepare('DELETE FROM promo_code_uses WHERE business_id = ?')->execute([$businessId]);
    }

    if ($subscriptionIds) {
        $in = wb_sa_in_clause($subscriptionIds);
        $pdo->prepare("DELETE FROM subscription_reminders WHERE subscription_id IN ({$in['sql']})")->execute($in['params']);
        $pdo->prepare("DELETE FROM promo_code_uses WHERE subscription_id IN ({$in['sql']})")->execute($in['params']);
        $pdo->prepare("DELETE FROM invoices WHERE subscription_id IN ({$in['sql']})")->execute($in['params']);
    }

    $pdo->prepare('DELETE FROM invoices WHERE user_id = ?')->execute([$userId]);
    $pdo->prepare('DELETE FROM payment_cards WHERE user_id = ?')->execute([$userId]);
    $pdo->prepare('DELETE FROM subscriptions WHERE user_id = ?')->execute([$userId]);
    $pdo->prepare('DELETE FROM promo_code_uses WHERE user_id = ?')->execute([$userId]);
    $pdo->prepare('DELETE FROM push_subscriptions WHERE user_id = ?')->execute([$userId]);
    $pdo->prepare('DELETE FROM user_notifications WHERE user_id = ?')->execute([$userId]);
    $pdo->prepare('DELETE FROM admin_users WHERE user_id = ?')->execute([$userId]);

    $emails = array_values(array_unique(array_filter([$targetEmail, $customerEmail])));
    if ($emails) {
        $in = wb_sa_in_clause($emails);
        $pdo->prepare("DELETE FROM email_otp_tokens WHERE email IN ({$in['sql']})")->execute($in['params']);
        $pdo->prepare("DELETE FROM email_queue WHERE to_email IN ({$in['sql']})")->execute($in['params']);
    }

    $phones = array_values(array_unique(array_filter([$customerPhone])));
    if ($phones) {
        $in = wb_sa_in_clause($phones);
        $pdo->prepare("DELETE FROM otp_tokens WHERE phone IN ({$in['sql']})")->execute($in['params']);
        $pdo->prepare("DELETE FROM sms_queue WHERE phone IN ({$in['sql']})")->execute($in['params']);
    }

    if ($businessId > 0) {
        $pdo->prepare('DELETE FROM businesses WHERE owner_id = ?')->execute([$userId]);
    }

    $pdo->prepare('DELETE FROM customers WHERE user_id = ?')->execute([$userId]);
    $pdo->prepare('DELETE FROM users WHERE id = ?')->execute([$userId]);

    $pdo->commit();

    wb_ok([
        'deleted' => true,
        'userId' => (string)$userId,
        'email' => $targetEmail,
        'role' => $preview['user']['role'],
    ]);
} catch (Throwable $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    error_log('[superadmin/delete-user] ' . $e->getMessage());
    wb_err('Kullanıcı silinemedi', 500, 'delete_failed');
}
