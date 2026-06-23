<?php
declare(strict_types=1);
/**
 * api/user/getProfile.php
 * GET — Oturum açık kullanıcının profilini döndürür.
 * Oturum yoksa ok:true, boş profil döner (anonim booking için).
 */

require_once __DIR__ . '/../_public_bootstrap.php';
wb_method('GET');

try {
    $sessionUserId = null;
    if (!empty($_SESSION['user_id']) && ($_SESSION['user_role'] ?? '') === 'user') {
        $sessionUserId = (int)$_SESSION['user_id'];
    }

    if (!$sessionUserId) {
        wb_ok(['uid' => null, 'name' => null, 'phone' => null, 'phoneE164' => null, 'email' => null]);
    }

    $stmt = $pdo->prepare("
        SELECT c.first_name, c.last_name, c.phone, c.email
        FROM customers c WHERE c.user_id = ? LIMIT 1
    ");
    $stmt->execute([$sessionUserId]);
    $row = $stmt->fetch();

    $name  = $row ? trim(($row['first_name'] ?? '') . ' ' . ($row['last_name'] ?? '')) : '';
    $phone = $row ? ($row['phone'] ?? $_SESSION['user_phone'] ?? null) : ($_SESSION['user_phone'] ?? null);
    $email = $row ? ($row['email'] ?? null) : null;

    wb_ok([
        'uid'       => (string)$sessionUserId,
        'name'      => $name ?: null,
        'phone'     => $phone,
        'phoneE164' => $phone,
        'email'     => $email,
    ]);

} catch (Throwable $e) {
    error_log('[user/getProfile.php] ' . $e->getMessage());
    wb_err('Profil alınamadı.', 500, 'internal_error');
}