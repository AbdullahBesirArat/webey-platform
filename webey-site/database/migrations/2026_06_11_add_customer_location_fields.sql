-- 2026_06_11_add_customer_location_fields.sql
-- Idempotent customer location fields for mobile profile/register flows.
-- No data is deleted.

SET @col_exists := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'customers' AND COLUMN_NAME = 'address_line'
);
SET @sql := IF(@col_exists = 0,
  'ALTER TABLE customers ADD COLUMN address_line TEXT NULL DEFAULT NULL AFTER neighborhood',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_exists := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'customers' AND COLUMN_NAME = 'latitude'
);
SET @sql := IF(@col_exists = 0,
  'ALTER TABLE customers ADD COLUMN latitude DECIMAL(10,7) NULL DEFAULT NULL AFTER address_line',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_exists := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'customers' AND COLUMN_NAME = 'longitude'
);
SET @sql := IF(@col_exists = 0,
  'ALTER TABLE customers ADD COLUMN longitude DECIMAL(10,7) NULL DEFAULT NULL AFTER latitude',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_exists := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'customers' AND COLUMN_NAME = 'location_updated_at'
);
SET @sql := IF(@col_exists = 0,
  'ALTER TABLE customers ADD COLUMN location_updated_at DATETIME NULL DEFAULT NULL AFTER longitude',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
