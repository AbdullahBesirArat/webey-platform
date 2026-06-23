<?php
// api/admin/status.php — İşletme onboarding durumu
declare(strict_types=1);

require_once __DIR__ . '/_bootstrap.php';

wb_method('GET', 'POST');

$sess = wb_auth_admin();

try {
    $stmt = $pdo->prepare("
        SELECT id, status, onboarding_step, onboarding_completed
        FROM businesses WHERE owner_id = ? LIMIT 1
    ");
    $stmt->execute([$sess['user_id']]);
    $business = $stmt->fetch();

    if (!$business) {
        wb_ok([
            'hasBarber' => false,
            'barberId'  => null,
            'status'    => 'none',
            'step'      => 0,
            'barber'    => null,
        ]);
    }

    $step      = (int)$business['onboarding_step'];
    $status    = $business['status'];
    $completed = (bool)$business['onboarding_completed'];

    wb_ok([
        'hasBarber'           => true,
        'barberId'            => (string)$business['id'],
        'status'              => $status,
        'step'                => $step,
        'onboardingCompleted' => $completed,
        'barber' => [
            'uid'                 => (string)$business['id'],
            'status'              => $status,
            'step'                => $step,
            'onboardingCompleted' => $completed,
        ],
    ]);

} catch (Throwable $e) {
    error_log('[status] ' . $e->getMessage());
    wb_err('Sunucu hatası', 500, 'internal_error');
}