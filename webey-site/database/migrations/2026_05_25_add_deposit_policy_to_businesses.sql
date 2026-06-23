-- =============================================================================
-- Migration: 2026_05_25_add_deposit_policy_to_businesses.sql
-- businesses tablosuna işletme kapora politika kolonları ekler.
--
-- ÖN KOŞUL: 2026_05_22_create_deposit_payments.sql daha önce uygulanmış olmalı
--           (deposit_required ve deposit_amount zaten var).
--
-- Eklenenler:
--   deposit_rate_pct      : Kapora oranı (0-100 %), varsayılan 25
--   deposit_per_service   : Kapora hizmet başına mı?, varsayılan 0 (hayır)
--   deposit_cancel_policy : İptal politikası etiketi (esnek|siki|yok), varsayılan 'esnek'
--
-- Kullanım:
--   SHOW COLUMNS FROM businesses LIKE 'deposit_rate_pct';
--   sonucunun boş olduğunu doğrulayın, ardından:
--   mysql -u root -p webey_prod < 2026_05_25_add_deposit_policy_to_businesses.sql
--
-- MySQL 8.0 uyumlu, idempotent (INFORMATION_SCHEMA kontrolü).
-- =============================================================================

SET NAMES utf8mb4;
SET foreign_key_checks = 0;

-- -----------------------------------------------------------------------------
-- deposit_rate_pct
-- -----------------------------------------------------------------------------
SET @_col = (
    SELECT COUNT(*)
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME   = 'businesses'
      AND COLUMN_NAME  = 'deposit_rate_pct'
);
SET @_sql = IF(
    @_col = 0,
    'ALTER TABLE `businesses` ADD COLUMN `deposit_rate_pct` TINYINT UNSIGNED NOT NULL DEFAULT 25 COMMENT \'Kapora oranı (%) — 0-100\'',
    'SELECT 1 /* businesses.deposit_rate_pct zaten mevcut, atlandı */'
);
PREPARE _migstmt FROM @_sql;
EXECUTE _migstmt;
DEALLOCATE PREPARE _migstmt;

-- -----------------------------------------------------------------------------
-- deposit_per_service
-- -----------------------------------------------------------------------------
SET @_col = (
    SELECT COUNT(*)
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME   = 'businesses'
      AND COLUMN_NAME  = 'deposit_per_service'
);
SET @_sql = IF(
    @_col = 0,
    'ALTER TABLE `businesses` ADD COLUMN `deposit_per_service` TINYINT(1) NOT NULL DEFAULT 0 COMMENT \'Kapora hizmet başına hesaplanır mı\'',
    'SELECT 1 /* businesses.deposit_per_service zaten mevcut, atlandı */'
);
PREPARE _migstmt FROM @_sql;
EXECUTE _migstmt;
DEALLOCATE PREPARE _migstmt;

-- -----------------------------------------------------------------------------
-- deposit_cancel_policy
-- -----------------------------------------------------------------------------
SET @_col = (
    SELECT COUNT(*)
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME   = 'businesses'
      AND COLUMN_NAME  = 'deposit_cancel_policy'
);
SET @_sql = IF(
    @_col = 0,
    'ALTER TABLE `businesses` ADD COLUMN `deposit_cancel_policy` VARCHAR(50) NOT NULL DEFAULT \'esnek\' COMMENT \'İptal politikası: esnek|siki|yok\'',
    'SELECT 1 /* businesses.deposit_cancel_policy zaten mevcut, atlandı */'
);
PREPARE _migstmt FROM @_sql;
EXECUTE _migstmt;
DEALLOCATE PREPARE _migstmt;

SET foreign_key_checks = 1;

-- =============================================================================
-- Migration tamamlandı.
-- Doğrulama:
--   SHOW COLUMNS FROM businesses LIKE 'deposit%';
-- Beklenen çıktı: deposit_required, deposit_amount, deposit_rate_pct,
--                 deposit_per_service, deposit_cancel_policy
-- =============================================================================
