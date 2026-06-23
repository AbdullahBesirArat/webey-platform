<?php
declare(strict_types=1);
/**
 * api/mobile/business/hours-save.php
 * POST — Token sahibi işletmenin çalışma saatlerini kaydeder/günceller.
 *
 * Body (JSON):
 *   items : array  (zorunlu, en az 1 eleman)
 *     - day        : string  (mon|tue|wed|thu|fri|sat|sun — zorunlu)
 *     - is_open    : bool    (zorunlu)
 *     - open_time  : string  (HH:MM veya HH:MM:SS — is_open=true ise zorunlu)
 *     - close_time : string  (HH:MM veya HH:MM:SS — is_open=true ise zorunlu)
 *
 * Yanıt:
 *   items : array  — güncel 7 gün (hours.php ile aynı yapı)
 *
 * Faz 8B — Bearer token zorunlu, business/admin tipi.
 * business_hours.(business_id,day) üzerinde UNIQUE KEY uq_business_hours_day varsayılır.
 */

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';
require_once __DIR__ . '/_helpers.php';

wb_method('POST');

$auth       = mobile_auth($pdo, ['business', 'admin']);
$ctx        = mobile_business_context($pdo, $auth);
$businessId = (int)$ctx['business_id'];

$in    = wb_body();
$items = $in['items'] ?? null;

if (!is_array($items) || $items === []) {
    wb_err('items dizisi zorunludur.', 422, 'missing_items');
}

$validDays = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
$rows      = [];

foreach ($items as $item) {
    $day = strtolower(trim((string)($item['day'] ?? '')));
    if (!in_array($day, $validDays, true)) {
        wb_err('Geçersiz day değeri: ' . htmlspecialchars($day, ENT_QUOTES), 422, 'invalid_day');
    }

    $isOpen    = (bool)($item['is_open'] ?? false);
    $openTime  = $isOpen ? mb_substr(trim((string)($item['open_time']  ?? '09:00')), 0, 8) : null;
    $closeTime = $isOpen ? mb_substr(trim((string)($item['close_time'] ?? '18:00')), 0, 8) : null;

    if ($openTime !== null && !preg_match('/^\d{2}:\d{2}/', $openTime)) {
        wb_err('open_time HH:MM formatında olmalı (' . $day . ').', 422, 'invalid_open_time');
    }
    if ($closeTime !== null && !preg_match('/^\d{2}:\d{2}/', $closeTime)) {
        wb_err('close_time HH:MM formatında olmalı (' . $day . ').', 422, 'invalid_close_time');
    }

    // Dakika yalnızca 00/15/30/45 olabilir.
    $allowedMinutes = [0, 15, 30, 45];
    if ($openTime !== null) {
        $om = (int)substr($openTime, 3, 2);
        if (!in_array($om, $allowedMinutes, true)) {
            wb_err('open_time dakikası 00/15/30/45 olmalı (' . $day . ').', 422, 'invalid_open_time_minute');
        }
    }
    if ($closeTime !== null) {
        $cm = (int)substr($closeTime, 3, 2);
        if (!in_array($cm, $allowedMinutes, true)) {
            wb_err('close_time dakikası 00/15/30/45 olmalı (' . $day . ').', 422, 'invalid_close_time_minute');
        }
    }

    $rows[$day] = [$businessId, $day, $isOpen ? 1 : 0, $openTime, $closeTime];
}

try {
    $pdo->beginTransaction();

    $upsert = $pdo->prepare("
        INSERT INTO business_hours (business_id, day, is_open, open_time, close_time)
        VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            is_open    = VALUES(is_open),
            open_time  = VALUES(open_time),
            close_time = VALUES(close_time)
    ");

    foreach ($rows as $params) {
        $upsert->execute($params);
    }

    $pdo->commit();

    // ── Re-fetch güncel 7 gün ─────────────────────────────────────────────────
    $allDays    = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
    $weekdaySet = ['mon', 'tue', 'wed', 'thu', 'fri'];

    $stmt = $pdo->prepare(
        'SELECT day, is_open, open_time, close_time FROM business_hours WHERE business_id = ?'
    );
    $stmt->execute([$businessId]);

    $byDay = [];
    foreach ($stmt->fetchAll() as $row) {
        $byDay[(string)$row['day']] = $row;
    }

    $result = [];
    foreach ($allDays as $day) {
        if (isset($byDay[$day])) {
            $r      = $byDay[$day];
            $isOpen = (bool)$r['is_open'];
            $result[] = [
                'day'        => $day,
                'is_open'    => $isOpen,
                'open_time'  => $isOpen ? ($r['open_time']  ?? null) : null,
                'close_time' => $isOpen ? ($r['close_time'] ?? null) : null,
            ];
        } else {
            $isDef    = in_array($day, $weekdaySet, true);
            $result[] = [
                'day'        => $day,
                'is_open'    => $isDef,
                'open_time'  => $isDef ? '09:00:00' : null,
                'close_time' => $isDef ? '18:00:00' : null,
            ];
        }
    }

    wb_ok(['items' => $result]);

} catch (Throwable $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    error_log('[mobile/business/hours-save.php] ' . $e->getMessage());
    wb_err('Çalışma saatleri kaydedilemedi.', 500, 'internal_error');
}
