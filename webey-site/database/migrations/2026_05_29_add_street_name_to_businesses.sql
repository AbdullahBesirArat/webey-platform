-- 2026_05_29_add_street_name_to_businesses.sql
-- Idempotent: street_name kolonunu businesses tablosuna ekler.
-- Onboarding "sokak adı" alanı için.

SET @col_exists := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'businesses'
    AND COLUMN_NAME = 'street_name'
);

SET @sql := IF(@col_exists = 0,
  'ALTER TABLE businesses ADD COLUMN street_name VARCHAR(120) NULL DEFAULT NULL AFTER building_no',
  'SELECT 1');

PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
