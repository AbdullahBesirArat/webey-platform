<?php
// api/appointments/unlock.php
// Geçici slot kilidini manuel olarak kaldırır.
// Müşteri geri gittiğinde, sayfayı kapattığında veya farklı bir slot seçtiğinde çağrılır.
//
// POST JSON: { token: "kilit_token" }
// Döner: { ok:true, released:true }
//
// NOT: Token bilinmeden kilit kaldırılamaz (güvenlik).
//      Süresi dolan kilitler zaten geçersiz sayılır; bu endpoint erken serbest bırakma içindir.

declare(strict_types=1);

require_once __DIR__ . '/../_public_bootstrap.php';
wb_method('POST');

$data = wb_body();
if (!is_array($data)) { wb_err('Geçersiz JSON', 400); }

$token = trim($data['token'] ?? '');

if ($token === '') {
    wb_err('token zorunlu', 400);
}

// Token formatı: 48 karakter hex
if (!preg_match('/^[0-9a-f]{48}$/', $token)) {
    wb_err('Geçersiz token formatı', 400);
}

try {
    $stmt = $pdo->prepare('DELETE FROM slot_locks WHERE lock_token = ?');
    $stmt->execute([$token]);
    $affected = $stmt->rowCount();

    wb_ok([
        'released' => $affected > 0,
        'message'  => $affected > 0
            ? 'Slot kilidi kaldırıldı.'
            : 'Kilit bulunamadı veya zaten süresi dolmuştu.',
    ]);

} catch (Throwable $e) {
    error_log('[unlock.php] ' . $e->getMessage());
    wb_err('Kilit kaldırılamadı. Lütfen tekrar deneyin.', 500);
}