<?php
declare(strict_types=1);

require_once __DIR__ . '/_bootstrap.php';

wb_method('POST');

function wb_shift_datetime_expr(string $column, string $intervalUnit): string
{
    return match ($intervalUnit) {
        'DAY' => "DATE_ADD({$column}, INTERVAL ? DAY)",
        'MONTH' => "DATE_ADD({$column}, INTERVAL ? MONTH)",
        'YEAR' => "DATE_ADD({$column}, INTERVAL ? YEAR)",
        default => throw new InvalidArgumentException('Unsupported interval unit'),
    };
}

function wb_update_shifted_datetime(PDO $pdo, string $table, string $column, string $whereColumn, string $intervalUnit, int $signedAmount, int $targetId): int
{
    $expr = wb_shift_datetime_expr($column, $intervalUnit);
    $stmt = $pdo->prepare("UPDATE {$table} SET {$column} = {$expr} WHERE {$whereColumn} = ?");
    $stmt->execute([$signedAmount, $targetId]);
    return $stmt->rowCount();
}

$in = wb_body();

$adminId = (int)($in['admin_id'] ?? 0);
$direction = (string)($in['direction'] ?? '');
$amount = (int)($in['amount'] ?? 0);
$unit = strtolower(trim((string)($in['unit'] ?? '')));

if ($adminId <= 0) {
    wb_err('Gecerli bir admin ID girin.', 422, 'invalid_admin_id');
}
if (!in_array($direction, ['forward', 'backward'], true)) {
    wb_err('Gecersiz yon.', 422, 'invalid_direction');
}
if ($amount <= 0 || $amount > 3650) {
    wb_err('Miktar 1 ile 3650 arasinda olmali.', 422, 'invalid_amount');
}

$unitMap = [
    'day' => 'DAY',
    'days' => 'DAY',
    'month' => 'MONTH',
    'months' => 'MONTH',
    'year' => 'YEAR',
    'years' => 'YEAR',
];
$intervalUnit = $unitMap[$unit] ?? null;
if ($intervalUnit === null) {
    wb_err('Gecersiz zaman birimi.', 422, 'invalid_unit');
}

$signedAmount = $direction === 'forward' ? $amount : -$amount;

$stmt = $pdo->prepare("
    SELECT
        u.id,
        u.email,
        u.role,
        u.created_at AS user_created_at,
        au.created_at AS admin_created_at,
        b.id AS business_id,
        b.name AS business_name,
        b.created_at AS business_created_at
    FROM users u
    LEFT JOIN admin_users au ON au.user_id = u.id
    LEFT JOIN businesses b ON b.owner_id = u.id
    WHERE u.id = ?
    LIMIT 1
");
$stmt->execute([$adminId]);
$row = $stmt->fetch(PDO::FETCH_ASSOC);

if (!$row) {
    wb_err('Admin bulunamadi.', 404, 'admin_not_found');
}
if ((string)($row['role'] ?? '') !== 'admin') {
    wb_err('Bu ID bir isletme adminine ait degil.', 422, 'not_business_admin');
}

$pdo->beginTransaction();
try {
    wb_update_shifted_datetime($pdo, 'users', 'created_at', 'id', $intervalUnit, $signedAmount, $adminId);
    wb_update_shifted_datetime($pdo, 'admin_users', 'created_at', 'user_id', $intervalUnit, $signedAmount, $adminId);

    $businessUpdated = false;
    if (!empty($row['business_id'])) {
        $businessUpdated = wb_update_shifted_datetime($pdo, 'businesses', 'created_at', 'owner_id', $intervalUnit, $signedAmount, $adminId) > 0;
    }

    $starterSubIdsStmt = $pdo->prepare("
        SELECT s.id
        FROM subscriptions s
        LEFT JOIN promo_code_uses pcu ON pcu.subscription_id = s.id
        WHERE s.user_id = ?
          AND s.plan = 'monthly_1'
          AND s.price = 0
          AND pcu.subscription_id IS NULL
    ");
    $starterSubIdsStmt->execute([$adminId]);
    $starterSubIds = array_map('intval', $starterSubIdsStmt->fetchAll(PDO::FETCH_COLUMN) ?: []);

    foreach ($starterSubIds as $starterSubId) {
        wb_update_shifted_datetime($pdo, 'subscriptions', 'created_at', 'id', $intervalUnit, $signedAmount, $starterSubId);
        wb_update_shifted_datetime($pdo, 'subscriptions', 'start_date', 'id', $intervalUnit, $signedAmount, $starterSubId);
        wb_update_shifted_datetime($pdo, 'subscriptions', 'end_date', 'id', $intervalUnit, $signedAmount, $starterSubId);
    }

    $freshStmt = $pdo->prepare("
        SELECT
            u.id,
            u.email,
            u.created_at AS user_created_at,
            au.created_at AS admin_created_at,
            b.id AS business_id,
            b.name AS business_name,
            b.created_at AS business_created_at
        FROM users u
        LEFT JOIN admin_users au ON au.user_id = u.id
        LEFT JOIN businesses b ON b.owner_id = u.id
        WHERE u.id = ?
        LIMIT 1
    ");
    $freshStmt->execute([$adminId]);
    $fresh = $freshStmt->fetch(PDO::FETCH_ASSOC) ?: [];

    $pdo->commit();

    wb_ok([
        'message' => 'Admin kayit tarihi guncellendi.',
        'admin' => [
            'id' => $adminId,
            'email' => $fresh['email'] ?? ($row['email'] ?? null),
            'beforeCreatedAt' => $row['user_created_at'] ?? null,
            'afterCreatedAt' => $fresh['user_created_at'] ?? null,
            'beforeAdminCreatedAt' => $row['admin_created_at'] ?? null,
            'afterAdminCreatedAt' => $fresh['admin_created_at'] ?? null,
            'businessId' => $fresh['business_id'] ?? ($row['business_id'] ?? null),
            'businessName' => $fresh['business_name'] ?? ($row['business_name'] ?? null),
            'beforeBusinessCreatedAt' => $row['business_created_at'] ?? null,
            'afterBusinessCreatedAt' => $fresh['business_created_at'] ?? null,
            'businessUpdated' => $businessUpdated,
            'shiftedStarterSubscriptionCount' => count($starterSubIds),
        ],
    ]);
} catch (Throwable $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    wb_err('Tarih guncellenemedi.', 500, 'update_failed');
}
