-- Business 6-alan paketi: personel profil fotoğrafı + randevu iptal politikası snapshot.
-- İdempotent (INFORMATION_SCHEMA kontrollü). Tablo DROP / veri silme YOK.
-- Mevcut deposit_policies cancel alanları + notification_preferences.prefs_json kullanılır
-- (onlar için migration GEREKMEZ).

DROP PROCEDURE IF EXISTS `wb_add_business_policy_cols`;
DELIMITER //
CREATE PROCEDURE `wb_add_business_policy_cols`()
BEGIN
  -- Personel profil fotoğrafı (galeri kotasına dahil DEĞİL).
  IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'staff' AND COLUMN_NAME = 'profile_photo_url') THEN
    ALTER TABLE `staff`
      ADD COLUMN `profile_photo_url` varchar(500) COLLATE utf8mb4_unicode_ci DEFAULT NULL AFTER `color`;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'staff' AND COLUMN_NAME = 'profile_photo_updated_at') THEN
    ALTER TABLE `staff`
      ADD COLUMN `profile_photo_updated_at` datetime DEFAULT NULL AFTER `profile_photo_url`;
  END IF;

  -- Randevu iptal politikası snapshot'ları (booking anında yazılır; sonradan
  -- politika değişse bile bu randevunun kuralı sabit kalır).
  IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'appointments' AND COLUMN_NAME = 'free_cancel_hours_snapshot') THEN
    ALTER TABLE `appointments`
      ADD COLUMN `free_cancel_hours_snapshot` smallint unsigned DEFAULT NULL,
      ADD COLUMN `late_cancel_fee_pct_snapshot` tinyint unsigned DEFAULT NULL,
      ADD COLUMN `no_show_refund_pct_snapshot` tinyint unsigned DEFAULT NULL,
      ADD COLUMN `paid_deposit_amount_snapshot` decimal(8,2) DEFAULT NULL,
      ADD COLUMN `cancel_refund_amount` decimal(8,2) DEFAULT NULL,
      ADD COLUMN `cancel_retained_amount` decimal(8,2) DEFAULT NULL,
      ADD COLUMN `cancel_rule_result` varchar(30) COLLATE utf8mb4_unicode_ci DEFAULT NULL;
  END IF;
END //
DELIMITER ;
CALL `wb_add_business_policy_cols`();
DROP PROCEDURE IF EXISTS `wb_add_business_policy_cols`;

-- Günlük özet bildirimi dedup tablosu (aynı gün ikinci kez gönderilmesin).
CREATE TABLE IF NOT EXISTS `business_daily_summary_log` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `business_id` int unsigned NOT NULL,
  `summary_date` date NOT NULL,
  `sent_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `appointment_count` int unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_biz_date` (`business_id`, `summary_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
