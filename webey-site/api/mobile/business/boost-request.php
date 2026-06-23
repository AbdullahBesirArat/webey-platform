<?php
declare(strict_types=1);
/**
 * api/mobile/business/boost-request.php
 * POST — İşletme bir boost paketi için talep oluşturur (ödeme entegrasyonu yok).
 *
 * Body (JSON):
 *   package_id : int    (zorunlu)
 *   note       : string (opsiyonel)
 *
 * Gerçek kayıt: business_boost_requests (status='pending'). Sahte satın alma YOK.
 * Auth: business/admin; yalnızca kendi işletmesi.
 *
 * Yanıt: request{...}, message
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';
require_once __DIR__ . '/_helpers.php';

wb_method('POST');

try {
    $auth       = mobile_auth($pdo, ['business', 'admin']);
    $ctx        = mobile_business_context($pdo, $auth);
    $businessId = (int)$ctx['business_id'];

    if (!mobile_table_has_column($pdo, 'business_boost_requests', 'id')) {
        wb_err('Boost talebi servisi şu an kullanılamıyor', 503, 'boost_unavailable');
    }

    $in        = wb_body();
    $packageId = (int)($in['package_id'] ?? 0);
    $note      = mb_substr(trim((string)($in['note'] ?? '')), 0, 500);

    if ($packageId <= 0) {
        wb_err('package_id zorunlu', 422, 'missing_package_id');
    }

    // Paket bu sistemde gerçekten var ve aktif mi?
    $pkgStmt = $pdo->prepare('SELECT id, name FROM boost_packages WHERE id = ? AND is_active = 1 LIMIT 1');
    $pkgStmt->execute([$packageId]);
    $pkg = $pkgStmt->fetch();
    if (!$pkg) {
        wb_err('Geçersiz veya pasif paket', 404, 'package_not_found');
    }

    // Boost uygunluk HARD-GATE: abonelik (trial/active) + profil tamamlanma.
    // Eksik şart varsa talep oluşturulmaz; eksikler istemciye döner.
    $eligibility = mobile_boost_eligibility($pdo, $businessId, (string)($ctx['business_status'] ?? ''));
    if (!$eligibility['eligible']) {
        wb_err(
            'Boost talebi için bazı şartlar eksik.',
            422,
            'boost_not_eligible',
            ['missing_requirements' => $eligibility['missing']]
        );
    }

    // Aynı paket için zaten bekleyen talep varsa tekrar oluşturma (idempotent-ish).
    $dupStmt = $pdo->prepare(
        "SELECT id FROM business_boost_requests
         WHERE business_id = ? AND package_id = ? AND status = 'pending' LIMIT 1"
    );
    $dupStmt->execute([$businessId, $packageId]);
    $existingId = $dupStmt->fetchColumn();

    if ($existingId === false) {
        $pdo->prepare(
            "INSERT INTO business_boost_requests (business_id, package_id, status, note, created_at, updated_at)
             VALUES (?, ?, 'pending', ?, NOW(), NOW())"
        )->execute([$businessId, $packageId, $note !== '' ? $note : null]);
        $requestId = (int)$pdo->lastInsertId();
    } else {
        $requestId = (int)$existingId;
    }

    wb_ok([
        'request' => [
            'id'           => $requestId,
            'package_id'   => $packageId,
            'package_name' => (string)$pkg['name'],
            'status'       => 'pending',
        ],
        'message' => 'Talebiniz alındı. Webey ekibi en kısa sürede sizinle iletişime geçecek.',
    ]);
} catch (Throwable $e) {
    error_log('[mobile/business/boost-request.php] ' . $e->getMessage());
    wb_err('Boost talebi oluşturulamadı. Lütfen tekrar deneyin.', 500, 'internal_error');
}
