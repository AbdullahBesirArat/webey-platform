<?php
// api/admin/updateAbout.php — İşletme adı, sahip adı ve telefon güncelle
declare(strict_types=1);

require_once __DIR__ . '/_bootstrap.php';

wb_method('POST');
wb_csrf_verify(false);

$sess = wb_auth_admin();
$data = wb_body();

$businessName = trim((string)($data['businessName'] ?? ''));
$ownerName    = trim((string)($data['ownerName']    ?? ''));
$phone        = preg_replace('/\D+/', '', (string)($data['phone'] ?? ''));

if ($businessName === '' || mb_strlen($businessName) > 80) {
    wb_err('Geçerli bir işletme adı girin (max 80 karakter)', 422, 'invalid_business_name');
}
if ($ownerName === '' || mb_strlen($ownerName) > 80) {
    wb_err('Geçerli bir yetkili adı girin (max 80 karakter)', 422, 'invalid_owner_name');
}
if ($phone !== '' && !preg_match('/^5\d{9}$/', $phone)) {
    wb_err('Geçerli bir telefon numarası girin', 422, 'invalid_phone');
}

try {
    $stmt = $pdo->prepare("SELECT id, onboarding_step FROM businesses WHERE owner_id = ? LIMIT 1");
    $stmt->execute([$sess['user_id']]);
    $business = $stmt->fetch();

    if ($business) {
        $newStep = max((int)$business['onboarding_step'], 2);
        $pdo->prepare("UPDATE businesses SET name = ?, owner_name = ?, phone = ?, onboarding_step = ? WHERE id = ?")
            ->execute([$businessName, $ownerName, $phone ?: null, $newStep, $business['id']]);
        $businessId = (int)$business['id'];
    } else {
        $pdo->prepare("
            INSERT INTO businesses (owner_id, name, owner_name, phone, type, status, onboarding_step)
            VALUES (?, ?, ?, ?, 'kuafor', 'draft', 2)
        ")->execute([$sess['user_id'], $businessName, $ownerName, $phone ?: null]);
        $businessId = (int)$pdo->lastInsertId();
        $newStep    = 2;
    }

    wb_ok([
        'barberId' => (string)$businessId,
        'step'     => $newStep,
    ]);

} catch (Throwable $e) {
    error_log('[updateAbout] ' . $e->getMessage());
    wb_err('Sunucu hatası', 500, 'internal_error');
}