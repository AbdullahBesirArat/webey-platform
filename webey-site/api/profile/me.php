<?php
declare(strict_types=1);
/**
 * api/profile/me.php — Admin profil bilgileri
 * ──────────────────────────────────────────────
 * GET /api/profile/me.php
 * Döner: { ok, data: { uid, email, ownerName, businessName, businessId,
 *                      phone, createdAt, lastLoginAt, emailVerified, ... } }
 */

require_once __DIR__ . '/../_bootstrap.php';

wb_method('GET', 'POST');

$sess   = wb_auth_admin();
$userId = (int)$sess['user_id'];

try {
    $stmt = $pdo->prepare("
        SELECT
            u.id            AS uid,
            u.email,
            u.google_id,
            u.created_at,
            u.last_login_at,
            u.email_verified_at,
            au.id           AS admin_id,
            au.onboarding_completed,
            b.id            AS business_id,
            b.name          AS business_name,
            b.owner_name,
            b.phone,
            b.status        AS business_status
        FROM users u
        JOIN admin_users au ON au.user_id = u.id
        LEFT JOIN businesses b ON b.owner_id = u.id
        WHERE u.id = ?
        LIMIT 1
    ");
    $stmt->execute([$userId]);
    $row = $stmt->fetch();

    if (!$row) {
        wb_err('Profil bulunamadı', 404);
    }

    wb_ok([
        'uid'                 => (string)$row['uid'],
        'adminId'             => (string)$row['admin_id'],
        'email'               => $row['email'],
        'googleConnected'     => !empty($row['google_id']),
        'emailVerified'       => !empty($row['email_verified_at']),
        'ownerName'           => $row['owner_name']    ?? null,
        'businessName'        => $row['business_name'] ?? null,
        'businessId'          => $row['business_id'] ? (string)$row['business_id'] : null,
        'phone'               => $row['phone']         ?? null,
        'createdAt'           => $row['created_at']    ?? null,
        'lastLoginAt'         => $row['last_login_at'] ?? null,
        'onboardingCompleted' => ((int)($row['onboarding_completed'] ?? 0) === 1),
        'businessStatus'      => $row['business_status'] ?? null,
        'csrf_token'          => wb_csrf_token(),
    ]);

} catch (Throwable $e) {
    error_log('[profile/me.php] ' . $e->getMessage());
    wb_err('Profil bilgisi alınamadı', 500);
}
