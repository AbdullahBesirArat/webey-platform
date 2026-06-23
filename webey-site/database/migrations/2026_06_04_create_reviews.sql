-- Müşteri değerlendirmeleri (randevu sonrası puan + yorum).
-- Her randevu yalnızca bir kez değerlendirilebilir (uniq_appointment).
CREATE TABLE IF NOT EXISTS `reviews` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `appointment_id` int unsigned NOT NULL,
  `business_id` int unsigned NOT NULL,
  `customer_user_id` int unsigned NOT NULL,
  `service_id` int unsigned DEFAULT NULL,
  `rating` tinyint unsigned NOT NULL,
  `comment` varchar(1000) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_appointment` (`appointment_id`),
  KEY `idx_business` (`business_id`),
  KEY `idx_customer` (`customer_user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
