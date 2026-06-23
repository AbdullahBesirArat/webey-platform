-- ════════════════════════════════════════════════════════════════════════════
-- 2026_06_13_create_business_subscriptions.sql
-- Webey İşletme Aboneliği — Faz 1 altyapısı (manuel / super admin yönetimli).
--
-- ÖNEMLİ:
--  * Bu sistem mevcut `subscriptions` (eski web / iyzico, user_id bazlı) tablosundan
--    TAMAMEN AYRIDIR ve `business_id` bazlıdır. Eski tabloya DOKUNULMAZ.
--  * `businesses` tablosuna abonelik kolonu EKLENMEZ.
--  * Faz 1: yalnızca altyapı + okuma. Mobil görünürlük / salons.php sıralaması
--    bu migration ile DEĞİŞMEZ; gate'e bağlama Faz 3'tedir.
--  * Idempotent: CREATE TABLE IF NOT EXISTS + INSERT IGNORE (seed). İki kez
--    çalıştırıldığında hata vermez, veri ikizlenmez.
--  * Charset: utf8mb4 / utf8mb4_unicode_ci (Türkçe karakter korunur).
-- ════════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────────
-- A) business_subscription_plans — abonelik paketi kataloğu (başta tek satır)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS `business_subscription_plans` (
  `id`            int unsigned NOT NULL AUTO_INCREMENT,
  `code`          varchar(64)  COLLATE utf8mb4_unicode_ci NOT NULL,
  `name`          varchar(160) COLLATE utf8mb4_unicode_ci NOT NULL,
  `monthly_price` decimal(10,2) NOT NULL DEFAULT 0.00,
  `trial_days`    int unsigned NOT NULL DEFAULT 30,
  `description`   text         COLLATE utf8mb4_unicode_ci,
  `is_active`     tinyint(1)   NOT NULL DEFAULT 1,
  `sort_order`    int unsigned NOT NULL DEFAULT 0,
  `created_at`    datetime     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`    datetime     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_plan_code` (`code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ─────────────────────────────────────────────────────────────────────────────
-- B) business_subscriptions — işletme başına abonelik kaydı
--    NOT: business_id için "tek aktif kayıt" unique'i bilerek KONULMADI
--    (riskli). Aktif kayıt seçimi endpoint mantığıyla (en güncel) yapılır.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS `business_subscriptions` (
  `id`                   int unsigned NOT NULL AUTO_INCREMENT,
  `business_id`          int unsigned NOT NULL,
  `plan_id`              int unsigned NOT NULL,
  `status`               enum('trial','active','overdue','suspended','cancelled')
                         COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'trial',
  `monthly_price`        decimal(10,2) DEFAULT NULL,
  `trial_started_at`     datetime DEFAULT NULL,
  `trial_ends_at`        datetime DEFAULT NULL,
  `current_period_start` datetime DEFAULT NULL,
  `current_period_end`   datetime DEFAULT NULL,
  `last_payment_at`      datetime DEFAULT NULL,
  `next_payment_due_at`  datetime DEFAULT NULL,
  `payment_method`       enum('manual_iban','cash','card_manual','free','comped')
                         COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `notes`                text COLLATE utf8mb4_unicode_ci,
  `created_by`           int unsigned DEFAULT NULL,
  `updated_by`           int unsigned DEFAULT NULL,
  `created_at`           datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`           datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_business`     (`business_id`),
  KEY `idx_plan`         (`plan_id`),
  KEY `idx_status`       (`status`),
  KEY `idx_next_due`     (`next_payment_due_at`),
  KEY `idx_period_end`   (`current_period_end`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ─────────────────────────────────────────────────────────────────────────────
-- C) business_subscription_payments — manuel tahsilat defteri
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS `business_subscription_payments` (
  `id`              int unsigned NOT NULL AUTO_INCREMENT,
  `subscription_id` int unsigned NOT NULL,
  `business_id`     int unsigned NOT NULL,
  `amount`          decimal(10,2) NOT NULL DEFAULT 0.00,
  `paid_at`         datetime DEFAULT NULL,
  `method`          enum('manual_iban','cash','card_manual','free','comped')
                    COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'manual_iban',
  `period_start`    datetime DEFAULT NULL,
  `period_end`      datetime DEFAULT NULL,
  `reference`       varchar(160) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `notes`           text COLLATE utf8mb4_unicode_ci,
  `recorded_by`     int unsigned DEFAULT NULL,
  `created_at`      datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_subscription` (`subscription_id`),
  KEY `idx_business`     (`business_id`),
  KEY `idx_paid_at`      (`paid_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ─────────────────────────────────────────────────────────────────────────────
-- D) business_subscription_audit — yazma aksiyonları için iz (Faz 2 kullanımı)
--    payload_json: cross-version güvenliği için longtext (MariaDB'de JSON zaten
--    longtext alias'ıdır). Faz 1'de yazılmaz, sadece şema hazır olur.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS `business_subscription_audit` (
  `id`              int unsigned NOT NULL AUTO_INCREMENT,
  `subscription_id` int unsigned DEFAULT NULL,
  `business_id`     int unsigned NOT NULL,
  `action`          varchar(80) COLLATE utf8mb4_unicode_ci NOT NULL,
  `from_status`     varchar(40) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `to_status`       varchar(40) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `payload_json`    longtext COLLATE utf8mb4_unicode_ci,
  `actor_user_id`   int unsigned DEFAULT NULL,
  `created_at`      datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_business`     (`business_id`),
  KEY `idx_subscription` (`subscription_id`),
  KEY `idx_action`       (`action`),
  KEY `idx_created_at`   (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ─────────────────────────────────────────────────────────────────────────────
-- Seed: ana paket (idempotent — `code` unique olduğu için INSERT IGNORE)
-- ─────────────────────────────────────────────────────────────────────────────
INSERT IGNORE INTO `business_subscription_plans`
  (`code`, `name`, `monthly_price`, `trial_days`, `description`, `is_active`, `sort_order`)
VALUES
  ('webey_business', 'Webey İşletme Paketi', 2500.00, 30,
   'Online randevu, müşteri uygulamasında görünürlük, hizmet/personel yönetimi, galeri, harita, kapora bildirimi ve temel işletme yönetimi.',
   1, 1);
