<?php
declare(strict_types=1);
/**
 * api/mobile/booking/_helpers.php
 * Mobil booking endpointleri için paylaşılan helper fonksiyonlar.
 * Faz 5A — booking/availability, lock, unlock, book tarafından kullanılır.
 */

if (!function_exists('wb_bk_time_to_min')) {

    // "HH:MM" → dakika (günün başından itibaren)
    function wb_bk_time_to_min(string $hhmm): int
    {
        $parts = explode(':', $hhmm . ':0');
        return (int)$parts[0] * 60 + (int)$parts[1];
    }

    // date string → gün enum ('mon','tue',...)
    function wb_bk_day_key(string $date): string
    {
        $map = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];
        try {
            $idx = (int)(new DateTimeImmutable($date, new DateTimeZone('Europe/Istanbul')))->format('w');
            return $map[$idx] ?? 'sun';
        } catch (Throwable) {
            return 'sun';
        }
    }

    // business_hours / staff_hours satırlarını [{start, end}] minutu listesine dönüştür
    function wb_bk_extract_hour_ranges(array $rows): array
    {
        $ranges = [];
        foreach ($rows as $row) {
            if (!(int)($row['is_open'] ?? 0)) {
                continue;
            }
            $open  = substr((string)($row['open_time']  ?? ''), 0, 5);
            $close = substr((string)($row['close_time'] ?? ''), 0, 5);
            if (!preg_match('/^\d{2}:\d{2}$/', $open) || !preg_match('/^\d{2}:\d{2}$/', $close)) {
                continue;
            }
            $s = wb_bk_time_to_min($open);
            $e = wb_bk_time_to_min($close);
            if ($e > $s) {
                $ranges[] = ['start' => $s, 'end' => $e];
            }
        }
        return $ranges;
    }

    /**
     * İşletme / personel için belirtilen tarihteki çalışma aralıklarını döner.
     * businesses.staff_hours = 1 ise staff_hours tablosu, değilse business_hours kullanılır.
     * Personel saati bulunamazsa işletme saatine düşer.
     */
    function wb_bk_get_working_ranges(PDO $pdo, int $businessId, ?int $staffId, string $date): array
    {
        $dayKey = wb_bk_day_key($date);

        if ($staffId !== null) {
            // İşletme per-staff hour kullanıyor mu?
            $bizStmt = $pdo->prepare('SELECT staff_hours FROM businesses WHERE id = ? LIMIT 1');
            $bizStmt->execute([$businessId]);
            $bizRow = $bizStmt->fetch();
            $usesStaffHours = (bool)($bizRow['staff_hours'] ?? false);

            if ($usesStaffHours) {
                $shStmt = $pdo->prepare(
                    'SELECT is_open, open_time, close_time FROM staff_hours
                     WHERE staff_id = ? AND business_id = ? AND day = ?'
                );
                $shStmt->execute([$staffId, $businessId, $dayKey]);
                $shRows = $shStmt->fetchAll();
                if ($shRows) {
                    $ranges = wb_bk_extract_hour_ranges($shRows);
                    if ($ranges) {
                        return $ranges;
                    }
                }
            }
        }

        // Fallback: işletme saatleri
        $bhStmt = $pdo->prepare(
            'SELECT is_open, open_time, close_time FROM business_hours WHERE business_id = ? AND day = ?'
        );
        $bhStmt->execute([$businessId, $dayKey]);
        return wb_bk_extract_hour_ranges($bhStmt->fetchAll());
    }

    /**
     * Belirtilen gün için dolu randevu aralıklarını [{start, end}] dakika olarak döner.
     * cancellation_requested dahildir (iptal onaylanana kadar slot dolu sayılır).
     */
    function wb_bk_get_booked_ranges(PDO $pdo, int $businessId, ?int $staffId, string $date): array
    {
        $sql    = "SELECT start_at, end_at FROM appointments
                   WHERE business_id = ? AND DATE(start_at) = ?
                     AND status NOT IN ('cancelled','no_show','rejected','declined')";
        $params = [$businessId, $date];
        if ($staffId !== null) {
            $sql    .= ' AND staff_id = ?';
            $params[] = $staffId;
        }
        $stmt = $pdo->prepare($sql);
        $stmt->execute($params);

        $ranges = [];
        foreach ($stmt->fetchAll() as $r) {
            try {
                $start = new DateTimeImmutable($r['start_at']);
                $end   = new DateTimeImmutable($r['end_at']);
                $s     = (int)$start->format('G') * 60 + (int)$start->format('i');
                $e     = (int)$end->format('G')   * 60 + (int)$end->format('i');
                if ($e > $s) {
                    $ranges[] = ['start' => $s, 'end' => $e];
                }
            } catch (Throwable) {}
        }
        return $ranges;
    }

    /**
     * Aktif slot kilit aralıklarını döner.
     * Belirli personel için: o personele ait (staff_id = $staffId) VE
     * işletme geneli (staff_id = 0) kilitleri çakışma sayılır.
     * Personel belirtilmemişse yalnızca işletme geneli kilitler (staff_id = 0) kontrol edilir.
     */
    function wb_bk_get_lock_ranges(
        PDO $pdo,
        int $businessId,
        ?int $staffId,
        string $date,
        ?string $excludeToken = null
    ): array {
        if ($staffId !== null) {
            $sql    = "SELECT start_min, duration_min FROM slot_locks
                       WHERE business_id = ? AND day_str = ?
                         AND (staff_id = ? OR staff_id = 0)
                         AND expires_at >= NOW()";
            $params = [$businessId, $date, $staffId];
        } else {
            $sql    = "SELECT start_min, duration_min FROM slot_locks
                       WHERE business_id = ? AND day_str = ?
                         AND staff_id = 0
                         AND expires_at >= NOW()";
            $params = [$businessId, $date];
        }

        if ($excludeToken !== null && $excludeToken !== '') {
            $sql    .= ' AND lock_token != ?';
            $params[] = $excludeToken;
        }

        $stmt = $pdo->prepare($sql);
        $stmt->execute($params);

        $ranges = [];
        foreach ($stmt->fetchAll() as $r) {
            $s = (int)$r['start_min'];
            $e = $s + (int)$r['duration_min'];
            if ($e > $s) {
                $ranges[] = ['start' => $s, 'end' => $e];
            }
        }
        return $ranges;
    }

    // Verilen slotun herhangi bir aralıkla çakışıp çakışmadığını kontrol eder
    function wb_bk_ranges_overlap(array $ranges, int $slotStart, int $slotEnd): bool
    {
        foreach ($ranges as $r) {
            if ($r['start'] < $slotEnd && $r['end'] > $slotStart) {
                return true;
            }
        }
        return false;
    }

    /**
     * starts_at string'ini parse eder ve normalize eder.
     * Kabul edilen formatlar: "YYYY-MM-DD HH:MM:SS", "YYYY-MM-DDTHH:MM:SS", "YYYY-MM-DD HH:MM"
     * Başarısızlıkta null döner.
     */
    function wb_bk_validate_datetime(string $input): ?array
    {
        $clean = trim(str_replace('T', ' ', $input));
        // Saniye yoksa ekle
        if (preg_match('/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$/', $clean)) {
            $clean .= ':00';
        }
        if (!preg_match('/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/', $clean)) {
            return null;
        }

        try {
            $tz = new DateTimeZone('Europe/Istanbul');
            $dt = DateTimeImmutable::createFromFormat('Y-m-d H:i:s', $clean, $tz);
            if (!$dt) {
                return null;
            }
            // Format ile geri oluşturup eşleştir (geçersiz tarih tespiti, ör. 2026-02-30)
            if ($dt->format('Y-m-d H:i:s') !== $clean) {
                return null;
            }
            $h = (int)$dt->format('G');
            $m = (int)$dt->format('i');
            return [
                'dt'        => $dt,
                'str'       => $clean,
                'day_str'   => $dt->format('Y-m-d'),
                'start_min' => $h * 60 + $m,
            ];
        } catch (Throwable) {
            return null;
        }
    }
}
