-- 2026_05_29_full_business_customer_fix.sql
-- Idempotent migration — Customer + Business fix turu.
-- Eklenenler:
--   1) businesses.street_name (kolon yoksa eklenir)
--   2) deposit_policies ek kolonları (free_cancel_hours, late_cancel_enabled,
--      late_cancel_rate_pct, no_show_policy, customer_message)
--   3) notification_preferences tablosu (user_type, user_id ya da business_id, prefs_json)
--   4) Onboarded business'ları (status='draft' iken onboarding_completed=1 ve temel
--      bilgiler dolu olanları) status='active' yap

-- ─── 1) businesses.street_name ──────────────────────────────────────────────
SET @col_exists := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'businesses'
    AND COLUMN_NAME = 'street_name'
);
SET @sql := IF(@col_exists = 0,
  'ALTER TABLE businesses ADD COLUMN street_name VARCHAR(120) NULL DEFAULT NULL AFTER building_no',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ─── 2) deposit_policies ek kolonları ───────────────────────────────────────
SET @col_exists := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'deposit_policies'
    AND COLUMN_NAME = 'free_cancel_hours'
);
SET @sql := IF(@col_exists = 0,
  'ALTER TABLE deposit_policies ADD COLUMN free_cancel_hours SMALLINT UNSIGNED NULL DEFAULT 24',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_exists := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'deposit_policies'
    AND COLUMN_NAME = 'late_cancel_enabled'
);
SET @sql := IF(@col_exists = 0,
  'ALTER TABLE deposit_policies ADD COLUMN late_cancel_enabled TINYINT(1) NOT NULL DEFAULT 0',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_exists := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'deposit_policies'
    AND COLUMN_NAME = 'late_cancel_rate_pct'
);
SET @sql := IF(@col_exists = 0,
  'ALTER TABLE deposit_policies ADD COLUMN late_cancel_rate_pct TINYINT UNSIGNED NULL DEFAULT 50',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_exists := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'deposit_policies'
    AND COLUMN_NAME = 'no_show_policy'
);
SET @sql := IF(@col_exists = 0,
  "ALTER TABLE deposit_policies ADD COLUMN no_show_policy VARCHAR(20) NOT NULL DEFAULT 'forfeit'",
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_exists := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'deposit_policies'
    AND COLUMN_NAME = 'customer_message'
);
SET @sql := IF(@col_exists = 0,
  'ALTER TABLE deposit_policies ADD COLUMN customer_message VARCHAR(500) NULL DEFAULT NULL',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ─── 3) notification_preferences tablosu ────────────────────────────────────
CREATE TABLE IF NOT EXISTS notification_preferences (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_type VARCHAR(20) NOT NULL,
  user_id INT UNSIGNED NULL DEFAULT NULL,
  business_id INT UNSIGNED NULL DEFAULT NULL,
  prefs_json LONGTEXT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uniq_user (user_type, user_id),
  UNIQUE KEY uniq_business (user_type, business_id),
  KEY idx_user (user_id),
  KEY idx_business (business_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ─── 4) Onboarded businesses backfill status='active' ───────────────────────
UPDATE businesses
SET status = 'active'
WHERE status = 'draft'
  AND onboarding_completed = 1
  AND name IS NOT NULL AND name <> ''
  AND city IS NOT NULL AND city <> ''
  AND district IS NOT NULL AND district <> '';
