-- =============================================================================
-- Migration: 2026_05_22b_add_checkout_url_to_appointment_payments.sql
-- appointment_payments tablosuna checkout_url kolonu ekler.
--
-- Amaç:
--   Pending kapora ödemesinin iyzico checkout URL'ini DB'ye kalıcı olarak kaydeder.
--   Bu sayede kullanıcı ödeme sayfasını kapatıp geri döndüğünde start.php
--   iyzico'ya ikinci kez istek atmadan mevcut URL'i döndürebilir.
--
-- Gereklilik:
--   2026_05_22_create_deposit_payments.sql önce çalışmış olmalı.
--
-- Çalıştırma:
--   mysql -u root -p webey_prod < 2026_05_22b_add_checkout_url_to_appointment_payments.sql
--
-- MySQL 8.0 uyumlu, idempotent.
-- =============================================================================

SET NAMES utf8mb4;

SET @_col = (
    SELECT COUNT(*)
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME   = 'appointment_payments'
      AND COLUMN_NAME  = 'checkout_url'
);
SET @_sql = IF(
    @_col = 0,
    'ALTER TABLE `appointment_payments` ADD COLUMN `checkout_url` VARCHAR(512) DEFAULT NULL COMMENT \'iyzico paymentPageUrl — pending retry retry\'da URL\'i yeniden oluşturmak için\'',
    'SELECT 1 /* appointment_payments.checkout_url zaten mevcut, atlandı */'
);
PREPARE _migstmt FROM @_sql;
EXECUTE _migstmt;
DEALLOCATE PREPARE _migstmt;

-- =============================================================================
-- Doğrulama:
--   SHOW COLUMNS FROM appointment_payments LIKE 'checkout_url';
-- =============================================================================
