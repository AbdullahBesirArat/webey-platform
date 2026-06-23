<?php
declare(strict_types=1);

require_once __DIR__ . '/_bootstrap.php';
require_once __DIR__ . '/../_google_auth.php';

wb_method('POST');

$body = wb_body();
$credential = trim((string)($body['credential'] ?? ''));
if ($credential === '') {
    wb_err('Google token eksik.', 422, 'missing_google_token');
}

$identity = wb_google_extract_identity($credential);
if (!$identity) {
    wb_err('Google doğrulaması geçersiz. Lütfen tekrar deneyin.', 422, 'invalid_google_token');
}

$userId = (int)$user['user_id'];
$googleId = (string)$identity['google_id'];
$googleEmail = strtolower(trim((string)$identity['email']));
$fullName = trim((string)($identity['full_name'] ?? ''));
$avatar = trim((string)($identity['avatar'] ?? ''));

try {
    $pdo->beginTransaction();

    $stmt = $pdo->prepare("
        SELECT u.id, u.email, u.google_id, u.name, c.email AS customer_email
        FROM users u
        LEFT JOIN customers c ON c.user_id = u.id
        WHERE u.id = ?
        LIMIT 1
        FOR UPDATE
    ");
    $stmt->execute([$userId]);
    $currentUser = $stmt->fetch();

    if (!$currentUser) {
        $pdo->rollBack();
        wb_err('Kullanıcı bulunamadı.', 404, 'user_not_found');
    }

    $currentEmail = strtolower(trim((string)($currentUser['customer_email'] ?: $currentUser['email'] ?: '')));
    if ($currentEmail === '') {
        $pdo->rollBack();
        wb_err('Google hesabı bağlamak için önce hesabınıza e-posta ekleyin.', 409, 'email_required');
    }

    if ($currentEmail !== $googleEmail) {
        $pdo->rollBack();
        wb_err('Google hesabındaki e-posta mevcut hesabınızla aynı olmalı.', 409, 'email_mismatch');
    }

    $checkStmt = $pdo->prepare("
        SELECT id
        FROM users
        WHERE google_id = ?
        LIMIT 1
    ");
    $checkStmt->execute([$googleId]);
    $existingOwnerId = (int)($checkStmt->fetchColumn() ?: 0);
    if ($existingOwnerId > 0 && $existingOwnerId !== $userId) {
        $pdo->rollBack();
        wb_err('Bu Google hesabı başka bir kullanıcıya bağlı.', 409, 'google_already_linked');
    }

    $currentGoogleId = trim((string)($currentUser['google_id'] ?? ''));
    if ($currentGoogleId !== '' && $currentGoogleId !== $googleId) {
        $pdo->rollBack();
        wb_err('Hesabınıza zaten farklı bir Google hesabı bağlı.', 409, 'google_already_connected');
    }

    $updateStmt = $pdo->prepare("
        UPDATE users
        SET google_id = ?,
            avatar_url = CASE WHEN (avatar_url IS NULL OR avatar_url = '') AND ? <> '' THEN ? ELSE avatar_url END,
            name = CASE WHEN (name IS NULL OR name = '') AND ? <> '' THEN ? ELSE name END,
            email_verified_at = COALESCE(email_verified_at, NOW())
        WHERE id = ?
        LIMIT 1
    ");
    $updateStmt->execute([$googleId, $avatar, $avatar, $fullName, $fullName, $userId]);

    $customerStmt = $pdo->prepare("
        UPDATE customers
        SET email = COALESCE(NULLIF(email, ''), ?),
            email_ok = 1,
            updated_at = NOW()
        WHERE user_id = ?
    ");
    $customerStmt->execute([$googleEmail, $userId]);

    $pdo->commit();

    wb_ok([
        'googleConnected' => true,
        'email' => $currentEmail,
    ]);
} catch (Throwable $e) {
    if (isset($pdo) && $pdo->inTransaction()) {
        $pdo->rollBack();
    }
    error_log('[user/google-link.php] ' . $e->getMessage());
    wb_err('Google hesabı bağlanamadı. Lütfen tekrar deneyin.', 500, 'google_link_failed');
}
