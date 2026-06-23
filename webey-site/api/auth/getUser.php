<?php
// api/auth/getUser.php — Auth durumu + uid döner (profile.js uyumlu)
declare(strict_types=1);
require_once __DIR__ . '/../_public_bootstrap.php';

wb_method('GET');

if (empty($_SESSION['user_id'])) {
    wb_ok([]); // giriş yok — ok:true, data:{} (profile.js null check yapar)
}

$userId = (int)$_SESSION['user_id'];
$role   = $_SESSION['user_role'] ?? '';

// Müşteri ise customers tablosundan ad/soyad al (booking için gerekli)
$name     = null;
$phone    = $_SESSION['user_phone'] ?? '';
$email    = null;

if ($role === 'user') {
    try {
        $stmt = $pdo->prepare("
            SELECT c.first_name, c.last_name, c.phone, c.email
            FROM customers c WHERE c.user_id = ? LIMIT 1
        ");
        $stmt->execute([$userId]);
        $row = $stmt->fetch();
        if ($row) {
            $name  = trim(($row['first_name'] ?? '') . ' ' . ($row['last_name'] ?? '')) ?: null;
            $phone = $row['phone'] ?? $phone;
            $email = $row['email'] ?? null;
        }
    } catch (Throwable) {}
}

wb_ok([
    'uid'       => (string)$userId,
    'userId'    => (string)$userId,
    'role'      => $role,
    'phone'     => $phone,
    'phoneE164' => $phone,
    'name'      => $name,
    'email'     => $email,
]);