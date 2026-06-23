<?php
// api/superadmin/promo/create.php — Yeni promosyon kodu oluştur
declare(strict_types=1);

// FIX: İki farklı _bootstrap.php çift require ediliyordu — PHP warning + tahmin
// edilemez davranış. Superadmin endpoint'i sadece superadmin/_bootstrap.php kullanmalı.
require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../../billing/_plans.php';

wb_method('POST');
// Not: wb_csrf_verify(true) ve wb_auth_superadmin() zaten _bootstrap.php'de çağrılıyor
$sess = $user; // _bootstrap.php $user tanımlar

$PLANS = array_keys(WB_PLANS);

$data = wb_body();

$code = strtoupper(trim(preg_replace('/[^A-Z0-9]/i', '', $data['code'] ?? '')));
if (strlen($code) < 4 || strlen($code) > 32) {
    wb_err('Kod 4-32 harf/rakam olmalı', 400, 'invalid_code');
}

$plan         = in_array($data['plan'] ?? '', $PLANS) ? $data['plan'] : null;
$discountType = in_array($data['discount_type'] ?? 'free', ['free','percent','fixed'])
    ? $data['discount_type'] : 'free';

$discountValue = match($discountType) {
    'free'    => 100.00,
    'percent' => min(100, max(1, (float)($data['discount_value'] ?? 100))),
    'fixed'   => max(1,   (float)($data['discount_value'] ?? 0)),
};

$maxUses   = isset($data['max_uses']) && $data['max_uses'] !== '' ? max(1, (int)$data['max_uses']) : null;
$expiresAt = null;

if (!empty($data['expires_at'])) {
    $exp = strtotime($data['expires_at']);
    if ($exp && $exp > time()) {
        $expiresAt = date('Y-m-d H:i:s', $exp);
    } else {
        wb_err('Geçerli bir bitiş tarihi girin (gelecekte olmalı)', 400, 'invalid_expires_at');
    }
}

$note = substr(trim($data['note'] ?? ''), 0, 255);

try {
    $exists = $pdo->prepare("SELECT id FROM promo_codes WHERE code = ? LIMIT 1");
    $exists->execute([$code]);
    if ($exists->fetch()) {
        wb_err("'{$code}' kodu zaten mevcut", 409, 'code_exists');
    }

    $pdo->prepare("
        INSERT INTO promo_codes
            (code, plan, discount_type, discount_value, max_uses, expires_at, note, created_by, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, NOW())
    ")->execute([$code, $plan, $discountType, $discountValue, $maxUses, $expiresAt, $note ?: null, $sess['user_id']]);

    wb_ok([
        'id'             => (int)$pdo->lastInsertId(),
        'code'           => $code,
        'plan'           => $plan,
        'discount_type'  => $discountType,
        'discount_value' => $discountValue,
        'max_uses'       => $maxUses,
        'expires_at'     => $expiresAt,
        'note'           => $note ?: null,
    ], 201);

} catch (Throwable $e) {
    error_log('[promo/create] ' . $e->getMessage());
    wb_err('Kod oluşturulamadı', 500, 'internal_error');
}
