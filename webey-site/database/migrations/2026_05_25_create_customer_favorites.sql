-- =============================================================================
-- Migration: 2026_05_25_create_customer_favorites.sql
-- Müşteri Favori Salonları Tablosu
--
-- Bu tablo olmadan:
--   - GET  /api/mobile/customer/favorites.php      → boş liste döner (güvenli)
--   - POST /api/mobile/customer/favorite-toggle.php → 503 favorites_not_ready
--   - GET  /api/mobile/customer/favorite-check.php  → false döner (güvenli)
--
-- Çalıştırmadan önce:
--   SHOW TABLES LIKE 'customer_favorites';
-- sonucunun boş olduğunu doğrulayın.
--
-- Çalıştırma:
--   mysql -u root -p webey_prod < 2026_05_25_create_customer_favorites.sql
--
-- Kolon tipleri users.id ve businesses.id ile eşleştirilmiştir (INT UNSIGNED).
-- MySQL 8.0 uyumlu, idempotent (CREATE TABLE IF NOT EXISTS).
-- =============================================================================

SET NAMES utf8mb4;
SET foreign_key_checks = 0;

-- -----------------------------------------------------------------------------
-- customer_favorites tablosu
--
-- user_id     : users.id ile eşleşen INT UNSIGNED
-- business_id : businesses.id ile eşleşen INT UNSIGNED
-- UNIQUE KEY uq_user_business → INSERT IGNORE ile duplicate önlenir
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `customer_favorites` (
  `id`          INT UNSIGNED   NOT NULL AUTO_INCREMENT,
  `user_id`     INT UNSIGNED   NOT NULL
                  COMMENT 'users.id referansı — müşteri kullanıcı',
  `business_id` INT UNSIGNED   NOT NULL
                  COMMENT 'businesses.id referansı — favori işletme',
  `created_at`  DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_user_business`    (`user_id`, `business_id`),
  KEY           `idx_user_id`      (`user_id`),
  KEY           `idx_business_id`  (`business_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Müşteri favori salonları. Faz 8A.';

SET foreign_key_checks = 1;

-- =============================================================================
-- Migration tamamlandı.
-- Doğrulama sorguları:
--   SHOW TABLES LIKE 'customer_favorites';
--   DESCRIBE customer_favorites;
-- =============================================================================
