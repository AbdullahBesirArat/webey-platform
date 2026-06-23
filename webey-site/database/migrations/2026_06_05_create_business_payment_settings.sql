-- Salonun kapora IBAN bilgileri (MVP: para Webey'de toplanmaz, doğrudan salona).
CREATE TABLE IF NOT EXISTS `business_payment_settings` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `business_id` int unsigned NOT NULL,
  `deposit_enabled` tinyint(1) NOT NULL DEFAULT 0,
  `iban` varchar(34) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `account_holder` varchar(160) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `bank_name` varchar(120) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `instructions` text COLLATE utf8mb4_unicode_ci,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_business` (`business_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
