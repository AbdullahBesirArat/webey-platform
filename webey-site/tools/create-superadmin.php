<?php
declare(strict_types=1);

/**
 * tools/create-superadmin.php
 *
 * Secure usage (CLI only):
 *   php tools/create-superadmin.php --email=admin@example.com --name="Webey Admin" --password="StrongPass123"
 */

if (PHP_SAPI !== 'cli') {
    http_response_code(403);
    exit('Forbidden: CLI only');
}

$options = getopt('', ['email:', 'name:', 'password:']);
$email = strtolower(trim((string)($options['email'] ?? '')));
$name = trim((string)($options['name'] ?? ''));
$password = (string)($options['password'] ?? '');

if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
    fwrite(STDERR, "Error: --email is required and must be valid.\n");
    exit(1);
}
if (mb_strlen($name) < 2) {
    fwrite(STDERR, "Error: --name must be at least 2 chars.\n");
    exit(1);
}
if (strlen($password) < 12) {
    fwrite(STDERR, "Error: --password must be at least 12 chars.\n");
    exit(1);
}

require_once __DIR__ . '/../db.php';

try {
    $stmt = $pdo->prepare('SELECT id, role FROM users WHERE email = ? LIMIT 1');
    $stmt->execute([$email]);
    $existing = $stmt->fetch();

    $hash = password_hash($password, PASSWORD_BCRYPT, ['cost' => 12]);

    if ($existing) {
        $pdo->prepare(
            'UPDATE users SET role = ?, password_hash = ?, name = ?, email_verified_at = COALESCE(email_verified_at, NOW()) WHERE id = ?'
        )->execute(['superadmin', $hash, $name, $existing['id']]);

        fwrite(STDOUT, "Updated user #{$existing['id']} to superadmin.\n");
        exit(0);
    }

    $pdo->prepare(
        "INSERT INTO users (email, password_hash, name, role, email_verified_at, created_at) VALUES (?, ?, ?, 'superadmin', NOW(), NOW())"
    )->execute([$email, $hash, $name]);

    $newId = (int)$pdo->lastInsertId();
    fwrite(STDOUT, "Created superadmin user #{$newId}.\n");
    exit(0);
} catch (Throwable $e) {
    error_log('[create-superadmin] ' . $e->getMessage());
    fwrite(STDERR, "Error: could not create/update superadmin.\n");
    exit(1);
}