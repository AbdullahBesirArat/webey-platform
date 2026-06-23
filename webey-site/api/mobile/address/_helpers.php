<?php
declare(strict_types=1);
/**
 * Adres dataset endpointleri için ortak yardımcılar.
 */

if (!function_exists('wb_address_table_ready')) {
    function wb_address_table_ready(PDO $pdo, string $table): bool
    {
        $allowed = ['address_provinces', 'address_districts', 'address_neighborhoods'];
        if (!in_array($table, $allowed, true)) {
            return false;
        }
        static $cache = [];
        if (array_key_exists($table, $cache)) {
            return $cache[$table];
        }
        try {
            $stmt = $pdo->prepare(
                "SELECT COUNT(*) FROM information_schema.TABLES
                  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?"
            );
            $stmt->execute([$table]);
            $cache[$table] = (int)$stmt->fetchColumn() > 0;
        } catch (Throwable $e) {
            error_log('[wb_address_table_ready] ' . $e->getMessage());
            $cache[$table] = false;
        }
        return $cache[$table];
    }
}
