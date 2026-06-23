<?php
declare(strict_types=1);
/**
 * api/mobile/_loyalty.php
 * Sadakat sistemi ortak yardımcılar — programs / progress / events.
 *
 * Idempotent appointment completion: aynı appointment_id için 'visit' event
 * unique key sayesinde ikinci kez insert edilemez.
 */

if (!function_exists('wb_loyalty_tables_ready')) {
    function wb_loyalty_tables_ready(PDO $pdo): bool
    {
        static $cached = null;
        if ($cached !== null) return $cached;
        try {
            $stmt = $pdo->prepare(
                "SELECT COUNT(*) FROM information_schema.TABLES
                  WHERE TABLE_SCHEMA = DATABASE()
                    AND TABLE_NAME IN ('business_loyalty_programs','business_loyalty_progress','business_loyalty_events')"
            );
            $stmt->execute();
            $cached = (int)$stmt->fetchColumn() === 3;
        } catch (Throwable $e) {
            error_log('[wb_loyalty_tables_ready] ' . $e->getMessage());
            $cached = false;
        }
        return $cached;
    }
}

if (!function_exists('wb_loyalty_program')) {
    /**
     * @return array{is_active:bool,required_visits:int,reward_title:string,reward_description:?string}
     */
    function wb_loyalty_program(PDO $pdo, int $businessId): array
    {
        $default = [
            'is_active' => false,
            'required_visits' => 5,
            'reward_title' => '',
            'reward_description' => null,
        ];
        if (!wb_loyalty_tables_ready($pdo)) return $default;
        try {
            $stmt = $pdo->prepare(
                'SELECT is_active, required_visits, reward_title, reward_description
                   FROM business_loyalty_programs WHERE business_id = ? LIMIT 1'
            );
            $stmt->execute([$businessId]);
            $row = $stmt->fetch();
            if (!$row) return $default;
            return [
                'is_active' => (bool)$row['is_active'],
                'required_visits' => max(1, min(99, (int)$row['required_visits'])),
                'reward_title' => (string)($row['reward_title'] ?? ''),
                'reward_description' => $row['reward_description'] ?? null,
            ];
        } catch (Throwable $e) {
            error_log('[wb_loyalty_program] ' . $e->getMessage());
            return $default;
        }
    }
}

if (!function_exists('wb_loyalty_normalize_phone')) {
    function wb_loyalty_normalize_phone(?string $phone): ?string
    {
        if ($phone === null) return null;
        $digits = preg_replace('/[^0-9]/', '', $phone) ?? '';
        if ($digits === '') return null;
        // Türkiye: +90 önekini at, 10 hane bırak.
        if (strlen($digits) > 10 && str_starts_with($digits, '90')) {
            $digits = substr($digits, 2);
        }
        if (strlen($digits) > 10 && str_starts_with($digits, '0')) {
            $digits = substr($digits, 1);
        }
        return $digits !== '' ? $digits : null;
    }
}

if (!function_exists('wb_loyalty_find_or_create_progress')) {
    function wb_loyalty_find_or_create_progress(
        PDO $pdo,
        int $businessId,
        ?int $customerUserId,
        ?string $customerPhoneRaw,
        string $customerName
    ): ?int {
        if (!wb_loyalty_tables_ready($pdo)) return null;
        $phone = wb_loyalty_normalize_phone($customerPhoneRaw);
        try {
            if ($customerUserId !== null && $customerUserId > 0) {
                $stmt = $pdo->prepare(
                    'SELECT id FROM business_loyalty_progress
                       WHERE business_id = ? AND customer_user_id = ? LIMIT 1'
                );
                $stmt->execute([$businessId, $customerUserId]);
                $id = (int)($stmt->fetchColumn() ?: 0);
                if ($id > 0) return $id;
            }
            if ($phone !== null) {
                $stmt = $pdo->prepare(
                    'SELECT id FROM business_loyalty_progress
                       WHERE business_id = ? AND customer_phone = ? LIMIT 1'
                );
                $stmt->execute([$businessId, $phone]);
                $id = (int)($stmt->fetchColumn() ?: 0);
                if ($id > 0) return $id;
            }
            $ins = $pdo->prepare(
                'INSERT INTO business_loyalty_progress
                    (business_id, customer_user_id, customer_phone, customer_name,
                     visits_count, rewards_earned, rewards_used, created_at, updated_at)
                 VALUES (?, ?, ?, ?, 0, 0, 0, NOW(), NOW())'
            );
            $ins->execute([
                $businessId,
                $customerUserId,
                $phone,
                mb_substr(trim($customerName), 0, 160),
            ]);
            return (int)$pdo->lastInsertId();
        } catch (Throwable $e) {
            error_log('[wb_loyalty_find_or_create_progress] ' . $e->getMessage());
            return null;
        }
    }
}

/**
 * Bir randevu completed olduğunda çağrılır. Idempotent (aynı appointment_id için
 * 'visit' event unique key sayesinde tekrar insert edilmez).
 */
if (!function_exists('wb_loyalty_record_visit')) {
    function wb_loyalty_record_visit(
        PDO $pdo,
        int $businessId,
        int $appointmentId,
        ?int $customerUserId,
        ?string $customerPhone,
        string $customerName
    ): void {
        try {
            if (!wb_loyalty_tables_ready($pdo)) return;
            $program = wb_loyalty_program($pdo, $businessId);
            if (!$program['is_active']) return;

            $progressId = wb_loyalty_find_or_create_progress(
                $pdo, $businessId, $customerUserId, $customerPhone, $customerName
            );
            if ($progressId === null) return;

            // Idempotent event insert: aynı appointment_id+event_type için duplicate.
            $stmt = $pdo->prepare(
                "INSERT INTO business_loyalty_events
                    (business_id, progress_id, customer_user_id, customer_phone, appointment_id,
                     event_type, visits_delta, rewards_delta, created_at)
                 VALUES (?, ?, ?, ?, ?, 'visit', 1, 0, NOW())
                 ON DUPLICATE KEY UPDATE id = id"
            );
            $stmt->execute([
                $businessId, $progressId, $customerUserId,
                wb_loyalty_normalize_phone($customerPhone),
                $appointmentId,
            ]);
            if ($stmt->rowCount() === 0) {
                // Zaten kayıtlı — double count yok.
                return;
            }

            // Progress güncelle.
            $upd = $pdo->prepare(
                'UPDATE business_loyalty_progress
                    SET visits_count = visits_count + 1,
                        last_appointment_id = ?,
                        last_visit_at = NOW(),
                        updated_at = NOW()
                  WHERE id = ?'
            );
            $upd->execute([$appointmentId, $progressId]);

            // Reward earned kontrolü.
            $cur = $pdo->prepare(
                'SELECT visits_count FROM business_loyalty_progress WHERE id = ? LIMIT 1'
            );
            $cur->execute([$progressId]);
            $visits = (int)($cur->fetchColumn() ?: 0);
            $req = max(1, (int)$program['required_visits']);
            if ($visits >= $req) {
                $remaining = $visits % $req; // wrap-around
                $pdo->prepare(
                    'UPDATE business_loyalty_progress
                        SET visits_count = ?, rewards_earned = rewards_earned + 1, updated_at = NOW()
                      WHERE id = ?'
                )->execute([$remaining, $progressId]);
                $pdo->prepare(
                    "INSERT INTO business_loyalty_events
                        (business_id, progress_id, customer_user_id, customer_phone, appointment_id,
                         event_type, visits_delta, rewards_delta, created_at)
                     VALUES (?, ?, ?, ?, ?, 'reward_earned', 0, 1, NOW())"
                )->execute([
                    $businessId, $progressId, $customerUserId,
                    wb_loyalty_normalize_phone($customerPhone),
                    $appointmentId,
                ]);
            }
        } catch (Throwable $e) {
            error_log('[wb_loyalty_record_visit] ' . $e->getMessage());
        }
    }
}
