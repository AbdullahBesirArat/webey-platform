-- Boost (öne çıkarma) sistemi: paketler, abonelikler, talepler.
-- Ödeme entegrasyonu yok; "Talep Et" gerçek bir kayıt oluşturur (business_boost_requests).
-- priority_weight ileride search/listing sıralamasında kullanılacak (ayrı faz).

CREATE TABLE IF NOT EXISTS `boost_packages` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(80) COLLATE utf8mb4_unicode_ci NOT NULL,
  `description` varchar(280) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `price` decimal(10,2) NOT NULL DEFAULT 0.00,
  `duration_days` int unsigned NOT NULL DEFAULT 30,
  `priority_weight` int unsigned NOT NULL DEFAULT 1,
  `features` text COLLATE utf8mb4_unicode_ci,
  `is_active` tinyint(1) NOT NULL DEFAULT 1,
  `sort_order` int unsigned NOT NULL DEFAULT 0,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `business_boost_subscriptions` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `business_id` int unsigned NOT NULL,
  `package_id` int unsigned NOT NULL,
  `status` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'pending',
  `starts_at` datetime DEFAULT NULL,
  `ends_at` datetime DEFAULT NULL,
  `paid_amount` decimal(10,2) DEFAULT NULL,
  `payment_status` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'unpaid',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_biz_status` (`business_id`, `status`),
  KEY `idx_ends_at` (`ends_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `business_boost_requests` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `business_id` int unsigned NOT NULL,
  `package_id` int unsigned NOT NULL,
  `status` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'pending',
  `note` varchar(500) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_biz` (`business_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Varsayılan paketler (idempotent: sabit id ile INSERT IGNORE).
INSERT IGNORE INTO `boost_packages`
  (`id`, `name`, `description`, `price`, `duration_days`, `priority_weight`, `features`, `is_active`, `sort_order`)
VALUES
  (1, 'Başlangıç Boost', 'Aramalarda bir üst sırada görün, daha fazla profil ziyareti al.', 299.00, 7, 2,
   'Aramada üst sıra;7 gün boyunca öne çıkma;Profil ziyaret artışı', 1, 1),
  (2, 'Öne Çıkan Boost', 'Kategori ve bölge listelerinde belirgin biçimde öne çık.', 749.00, 30, 5,
   'Kategori listesinde öne çıkma;30 gün görünürlük;Rozet ile vurgulama;Öncelikli sıralama', 1, 2),
  (3, 'Premium Boost', 'Ana sayfa ve önerilenlerde en üst görünürlük seviyesi.', 1499.00, 30, 10,
   'Ana sayfada öne çıkma;En yüksek sıralama önceliği;Premium rozet;30 gün maksimum görünürlük', 1, 3);
