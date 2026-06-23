<?php
declare(strict_types=1);
/**
 * api/session/me.php — Birleşik Oturum Kontrol Endpoint'i
 * ═══════════════════════════════════════════════════════
 * api-client.js'in refreshSession() fonksiyonu bu tek endpoint'i çağırır.
 *
 * Dönen format:
 *   { ok: true, data: { role: 'admin', ... } }   — işletme sahibi
 *   { ok: true, data: { role: 'user',  ... } }   — müşteri
 *   { ok: false, error: 'unauthenticated', code: 'unauthenticated' } — giriş yok
 *
 * FIX: Elle yazılmış session init kodu kaldırıldı → _public_bootstrap.php kullanılıyor.
 *      db.php de artık bootstrap üzerinden geliyor.
 */

// session/me.php api/ klasörü altında ama bir seviye yukarıdaki bootstrap'i kullanıyor
require_once __DIR__ . '/../../api/_public_bootstrap.php';

header('Cache-Control: no-store');
wb_method('GET', 'POST');

// ── Giriş yapılmamış ─────────────────────────────────────────────────────────
if (empty($_SESSION['user_id'])) {
    wb_err('Oturum açılmamış', 401, 'unauthenticated');
}

$userId = (int)$_SESSION['user_id'];

try {
    // ── Süper Admin ──────────────────────────────────────────────────────────
    if (($_SESSION['user_role'] ?? '') === 'superadmin') {
        $uStmt = $pdo->prepare('SELECT id, email, role FROM users WHERE id=? AND role="superadmin" LIMIT 1');
        $uStmt->execute([$userId]);
        $saUser = $uStmt->fetch();
        if (!$saUser) { session_destroy(); wb_err('Oturum geçersiz', 401, 'unauthenticated'); }
        wb_ok([
            'role'       => 'superadmin',
            'userId'     => (string)$userId,
            'email'      => $saUser['email'],
            'csrf_token' => wb_csrf_token(),
        ]);
    }

    // ── Admin / İşletme sahibi ───────────────────────────────────────────────
    if (!empty($_SESSION['admin_id'])) {
        $adminId = (int)$_SESSION['admin_id'];

        $stmt = $pdo->prepare('
            SELECT au.id       AS admin_id,
                   au.onboarding_completed,
                   u.email,
                   u.email_verified_at
            FROM   admin_users au
            JOIN   users u ON u.id = au.user_id
            WHERE  au.id = ?
            LIMIT  1
        ');
        $stmt->execute([$adminId]);
        $admin = $stmt->fetch();

        if (!$admin) {
            // Session tutarsız — temizle
            session_destroy();
            wb_err('Oturum geçersiz', 401, 'unauthenticated');
        }

        $bizStmt = $pdo->prepare('
            SELECT id, onboarding_step, status, name, owner_name
            FROM   businesses
            WHERE  owner_id = ?
            LIMIT  1
        ');
        $bizStmt->execute([$userId]);
        $business = $bizStmt->fetch();

        if ($business) {
            $_SESSION['business_id'] = (int)$business['id'];
        }

        wb_ok([
            'role'                => 'admin',
            'userId'              => (string)$userId,
            'adminId'             => (string)$adminId,
            'email'               => $admin['email'],
            'emailVerified'       => !empty($admin['email_verified_at']),
            'businessId'          => $business ? (string)$business['id'] : null,
            'businessName'        => $business['name']          ?? null,
            'ownerName'           => $business['owner_name']    ?? null,
            'onboardingCompleted' => ((int)$admin['onboarding_completed'] === 1),
            'onboardingStep'      => $business ? (int)$business['onboarding_step'] : 0,
            'status'              => $business['status']        ?? null,
            'csrf_token'          => wb_csrf_token(),
        ]);
    }

    // ── Müşteri (end-user) ───────────────────────────────────────────────────
    if (($_SESSION['user_role'] ?? '') === 'user') {

        $stmt = $pdo->prepare('
            SELECT c.first_name, c.last_name, c.phone, c.birthday,
                   c.email,      c.city,       c.district, c.neighborhood,
                   c.sms_ok,     c.email_ok,
                   u.created_at, u.last_login_at,
                   u.email_verified_at, u.phone_verified_at, u.google_id
            FROM   customers c
            JOIN   users u ON u.id = c.user_id
            WHERE  c.user_id = ?
            LIMIT  1
        ');
        $stmt->execute([$userId]);
        $row = $stmt->fetch();

        wb_ok([
            'role'         => 'user',
            'userId'       => (string)$userId,
            'phone'        => $row['phone']        ?? ($_SESSION['user_phone'] ?? ''),
            'firstName'    => $row['first_name']   ?? '',
            'lastName'     => $row['last_name']    ?? '',
            'birthday'     => $row['birthday']     ?? null,
            'email'        => ($row['email'] ?? '') ?: null,
            'city'         => $row['city']         ?? null,
            'district'     => $row['district']     ?? null,
            'neighborhood' => $row['neighborhood'] ?? null,
            'smsOk'        => (bool)($row['sms_ok']   ?? true),
            'emailOk'      => (bool)($row['email_ok'] ?? false),
            'createdAt'    => $row['created_at']   ?? null,
            'lastLoginAt'  => $row['last_login_at'] ?? null,
            'googleConnected' => !empty($row['google_id']),
            // End-user için email doğrulama customers.email_ok üzerinden takip edilir.
            'emailVerified'=> !empty($row['email_ok']),
            'emailOk'      => !empty($row['email_ok']),
            'phoneVerified'=> !empty($row['phone_verified_at']),
            'csrf_token'   => wb_csrf_token(),
        ]);
    }

    // ── user_id var ama rol tanımsız ─────────────────────────────────────────
    wb_err('Oturum rolü tanımsız', 401, 'unauthenticated');

} catch (Throwable $e) {
    error_log('[session/me.php] ' . $e->getMessage());
    wb_err('Oturum bilgisi alınamadı. Lütfen tekrar deneyin.', 500);
}

