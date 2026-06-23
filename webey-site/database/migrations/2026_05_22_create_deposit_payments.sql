-- =============================================================================
-- Migration: 2026_05_22_create_deposit_payments.sql
-- Webey Kapora (Deposit) Ödeme Altyapısı
--
-- Çalıştırmadan önce:
--   SHOW COLUMNS FROM businesses LIKE 'deposit_required';
--   SHOW COLUMNS FROM appointments LIKE 'deposit_required';
--   SHOW TABLES LIKE 'appointment_payments';
-- sonuçlarının boş olduğunu doğrulayın.
--
-- Çalıştırma:
--   mysql -u root -p webey_prod < 2026_05_22_create_deposit_payments.sql
--
-- MySQL 8.0 uyumlu, idempotent.
-- NOT: MySQL 8.0 "ADD COLUMN IF NOT EXISTS" desteklemez (MariaDB 10.x özelliği).
--      PREPARE/EXECUTE + INFORMATION_SCHEMA yaklaşımı kullanılmıştır.
-- =============================================================================

SET NAMES utf8mb4;
SET foreign_key_checks = 0;

-- -----------------------------------------------------------------------------
-- 1. appointment_payments tablosu
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `appointment_payments` (
  `id`                  BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `appointment_id`      BIGINT UNSIGNED NOT NULL,
  `customer_user_id`    BIGINT UNSIGNED NOT NULL,
  `business_id`         BIGINT UNSIGNED NOT NULL,
  `provider`            VARCHAR(30)     NOT NULL DEFAULT 'iyzico',
  `provider_payment_id` VARCHAR(120)    DEFAULT NULL,
  `conversation_id`     VARCHAR(120)    DEFAULT NULL,
  `checkout_token`      VARCHAR(255)    DEFAULT NULL,
  `amount`              DECIMAL(10,2)   NOT NULL,
  `currency`            CHAR(3)         NOT NULL DEFAULT 'TRY',
  `status`              ENUM('pending','paid','failed','refunded','cancelled')
                          NOT NULL DEFAULT 'pending',
  `paid_at`             DATETIME        DEFAULT NULL,
  `refunded_at`         DATETIME        DEFAULT NULL,
  `raw_payload`         MEDIUMTEXT      DEFAULT NULL
                          COMMENT 'iyzico callback raw JSON — audit amaçlı',
  `created_at`          DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`          DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP
                          ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_appointment_payments_appointment` (`appointment_id`),
  KEY `idx_appointment_payments_customer`     (`customer_user_id`),
  KEY `idx_appointment_payments_business`     (`business_id`),
  KEY `idx_appointment_payments_status`       (`status`),
  KEY `idx_appointment_payments_conversation` (`conversation_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Randevu kapora ödemeleri. Faz 8C''de payment start/callback ile dolacak.';

-- -----------------------------------------------------------------------------
-- 2. businesses tablosuna kapora ayar kolonları
--    deposit_required : İşletme kapora gerektiriyor mu?
--    deposit_amount   : Kapora tutarı (TL)
-- -----------------------------------------------------------------------------

SET @_col = (
    SELECT COUNT(*)
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME   = 'businesses'
      AND COLUMN_NAME  = 'deposit_required'
);
SET @_sql = IF(
    @_col = 0,
    'ALTER TABLE `businesses` ADD COLUMN `deposit_required` TINYINT(1) NOT NULL DEFAULT 0 COMMENT \'Randevu alırken kapora zorunlu mu\'',
    'SELECT 1 /* businesses.deposit_required zaten mevcut, atlandı */'
);
PREPARE _migstmt FROM @_sql;
EXECUTE _migstmt;
DEALLOCATE PREPARE _migstmt;

SET @_col = (
    SELECT COUNT(*)
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME   = 'businesses'
      AND COLUMN_NAME  = 'deposit_amount'
);
SET @_sql = IF(
    @_col = 0,
    'ALTER TABLE `businesses` ADD COLUMN `deposit_amount` DECIMAL(10,2) DEFAULT NULL COMMENT \'Kapora tutarı TL — deposit_required=1 ise geçerli\'',
    'SELECT 1 /* businesses.deposit_amount zaten mevcut, atlandı */'
);
PREPARE _migstmt FROM @_sql;
EXECUTE _migstmt;
DEALLOCATE PREPARE _migstmt;

-- -----------------------------------------------------------------------------
-- 3. appointments tablosuna randevu bazlı kapora snapshot
--    Randevu oluşturulduğu andaki işletme deposit ayarını kopyalar.
--    Sonradan işletme ayarı değişse bile randevu kendi snapshot'ını korur.
-- -----------------------------------------------------------------------------

SET @_col = (
    SELECT COUNT(*)
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME   = 'appointments'
      AND COLUMN_NAME  = 'deposit_required'
);
SET @_sql = IF(
    @_col = 0,
    'ALTER TABLE `appointments` ADD COLUMN `deposit_required` TINYINT(1) NOT NULL DEFAULT 0 COMMENT \'Randevu oluşturulduğu anda işletme deposit_required snapshot\'',
    'SELECT 1 /* appointments.deposit_required zaten mevcut, atlandı */'
);
PREPARE _migstmt FROM @_sql;
EXECUTE _migstmt;
DEALLOCATE PREPARE _migstmt;

SET @_col = (
    SELECT COUNT(*)
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME   = 'appointments'
      AND COLUMN_NAME  = 'deposit_amount'
);
SET @_sql = IF(
    @_col = 0,
    'ALTER TABLE `appointments` ADD COLUMN `deposit_amount` DECIMAL(10,2) DEFAULT NULL COMMENT \'Randevu oluşturulduğu anda deposit_amount snapshot\'',
    'SELECT 1 /* appointments.deposit_amount zaten mevcut, atlandı */'
);
PREPARE _migstmt FROM @_sql;
EXECUTE _migstmt;
DEALLOCATE PREPARE _migstmt;

SET foreign_key_checks = 1;

-- =============================================================================
-- Migration tamamlandı.
-- Doğrulama sorguları:
--   DESCRIBE appointment_payments;
--   SHOW COLUMNS FROM businesses LIKE 'deposit%';
--   SHOW COLUMNS FROM appointments LIKE 'deposit%';
-- =============================================================================
