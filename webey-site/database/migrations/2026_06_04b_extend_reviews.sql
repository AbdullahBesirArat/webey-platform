-- reviews tablosunu üretim ilişkileri için genişletir (veri kaybı yok).
-- staff_id / status / updated_at + ek indexler (salon/personel/hizmet
-- yorumları ve ortalama puan hesapları için).
ALTER TABLE `reviews`
  ADD COLUMN `staff_id` int unsigned DEFAULT NULL AFTER `business_id`,
  ADD COLUMN `status` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'active' AFTER `comment`,
  ADD COLUMN `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP AFTER `created_at`,
  ADD KEY `idx_staff` (`staff_id`),
  ADD KEY `idx_service` (`service_id`),
  ADD KEY `idx_rating` (`rating`),
  ADD KEY `idx_status` (`status`);
