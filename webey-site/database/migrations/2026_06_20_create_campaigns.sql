-- Kampanyalar (MVP) — işletme kampanya yönetimi + randevu snapshot.
-- İdempotent: CREATE TABLE IF NOT EXISTS + appointments kolonları için
-- INFORMATION_SCHEMA kontrollü geçici prosedür. Tablo DROP / veri silme YOK.
--
-- Desteklenen MVP biçimleri (condition_type):
--   general  : genel indirim (gün/saat opsiyonel)
--   weekday  : hafta içi / seçili günler (days_of_week)
--   hourly   : saat aralığı (start_time/end_time)
-- discount_kind: percent | fixed
-- scope_type   : all_services | selected_services
-- status       : active | paused | archived  (hard delete yerine archived)

-- ── 1) Kampanya ana tablosu ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS `business_campaigns` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `business_id` int unsigned NOT NULL,
  `title` varchar(120) COLLATE utf8mb4_unicode_ci NOT NULL,
  `description` varchar(500) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `condition_type` varchar(16) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'general',
  `discount_kind` varchar(16) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'percent',
  `discount_value` decimal(10,2) NOT NULL DEFAULT 0.00,
  `scope_type` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'all_services',
  `start_date` date DEFAULT NULL,
  `end_date` date DEFAULT NULL,
  `start_time` time DEFAULT NULL,
  `end_time` time DEFAULT NULL,
  `days_of_week` varchar(32) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'ISO gün CSV: 1=Pzt .. 7=Paz',
  `status` varchar(16) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'active',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_campaign_business` (`business_id`),
  KEY `idx_campaign_status` (`status`),
  KEY `idx_campaign_dates` (`start_date`, `end_date`),
  KEY `idx_campaign_business_status` (`business_id`, `status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ── 2) Kampanya ↔ hizmet bağ tablosu (selected_services kapsamı) ─────────────
CREATE TABLE IF NOT EXISTS `campaign_services` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `campaign_id` int unsigned NOT NULL,
  `service_id` int unsigned NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_campaign_service` (`campaign_id`, `service_id`),
  KEY `idx_cs_service` (`service_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ── 3) appointments kampanya snapshot alanları (idempotent) ──────────────────
DROP PROCEDURE IF EXISTS `wb_add_campaign_appt_cols`;
DELIMITER //
CREATE PROCEDURE `wb_add_campaign_appt_cols`()
BEGIN
  IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'appointments' AND COLUMN_NAME = 'campaign_id') THEN
    ALTER TABLE `appointments`
      ADD COLUMN `campaign_id` int unsigned DEFAULT NULL AFTER `deposit_marked_at`;
    ALTER TABLE `appointments` ADD KEY `idx_appt_campaign` (`campaign_id`);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'appointments' AND COLUMN_NAME = 'campaign_title_snapshot') THEN
    ALTER TABLE `appointments`
      ADD COLUMN `campaign_title_snapshot` varchar(120) COLLATE utf8mb4_unicode_ci DEFAULT NULL AFTER `campaign_id`;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'appointments' AND COLUMN_NAME = 'campaign_discount_kind') THEN
    ALTER TABLE `appointments`
      ADD COLUMN `campaign_discount_kind` varchar(16) COLLATE utf8mb4_unicode_ci DEFAULT NULL AFTER `campaign_title_snapshot`;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'appointments' AND COLUMN_NAME = 'campaign_discount_value') THEN
    ALTER TABLE `appointments`
      ADD COLUMN `campaign_discount_value` decimal(10,2) DEFAULT NULL AFTER `campaign_discount_kind`;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'appointments' AND COLUMN_NAME = 'campaign_discount_amount') THEN
    ALTER TABLE `appointments`
      ADD COLUMN `campaign_discount_amount` decimal(10,2) NOT NULL DEFAULT 0.00 AFTER `campaign_discount_value`;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'appointments' AND COLUMN_NAME = 'original_amount') THEN
    ALTER TABLE `appointments`
      ADD COLUMN `original_amount` decimal(10,2) DEFAULT NULL AFTER `campaign_discount_amount`;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'appointments' AND COLUMN_NAME = 'final_amount') THEN
    ALTER TABLE `appointments`
      ADD COLUMN `final_amount` decimal(10,2) DEFAULT NULL AFTER `original_amount`;
  END IF;
END //
DELIMITER ;
CALL `wb_add_campaign_appt_cols`();
DROP PROCEDURE IF EXISTS `wb_add_campaign_appt_cols`;
