<?php
declare(strict_types=1);
/**
 * api/mobile/business/hours.php
 * GET — Token sahibi işletmenin çalışma saatlerini döner (7 gün).
 *
 * Yanıt:
 *   items : array  — her biri {day, is_open, open_time, close_time}
 *           DB'de kaydı olmayan günler için platform varsayılanı kullanılır.
 *
 * Faz 8B — Bearer token zorunlu, business/admin tipi.
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';
require_once __DIR__ . '/_helpers.php';

wb_method('GET');

$auth       = mobile_auth($pdo, ['business', 'admin']);
$ctx        = mobile_business_context($pdo, $auth);
$businessId = (int)$ctx['business_id'];

$allDays     = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
$weekdaySet  = ['mon', 'tue', 'wed', 'thu', 'fri'];

try {
    $stmt = $pdo->prepare(
        'SELECT day, is_open, open_time, close_time FROM business_hours WHERE business_id = ?'
    );
    $stmt->execute([$businessId]);

    $byDay = [];
    foreach ($stmt->fetchAll() as $row) {
        $byDay[(string)$row['day']] = $row;
    }

    $items = [];
    foreach ($allDays as $day) {
        if (isset($byDay[$day])) {
            $r       = $byDay[$day];
            $isOpen  = (bool)$r['is_open'];
            $items[] = [
                'day'        => $day,
                'is_open'    => $isOpen,
                'open_time'  => $isOpen ? ($r['open_time']  ?? null) : null,
                'close_time' => $isOpen ? ($r['close_time'] ?? null) : null,
            ];
        } else {
            $isDefault = in_array($day, $weekdaySet, true);
            $items[]   = [
                'day'        => $day,
                'is_open'    => $isDefault,
                'open_time'  => $isDefault ? '09:00:00' : null,
                'close_time' => $isDefault ? '18:00:00' : null,
            ];
        }
    }

    wb_ok(['items' => $items]);

} catch (Throwable $e) {
    error_log('[mobile/business/hours.php] ' . $e->getMessage());
    wb_err('Çalışma saatleri alınamadı.', 500, 'internal_error');
}
