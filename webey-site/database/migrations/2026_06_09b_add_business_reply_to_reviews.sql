-- İşletmenin yorumlara cevap vermesi ve beğenmesi için reviews alanları.
-- Veri kaybı yok; tüm alanlar opsiyonel/nullable veya default'lu.
ALTER TABLE `reviews`
  ADD COLUMN `business_reply` TEXT COLLATE utf8mb4_unicode_ci DEFAULT NULL AFTER `comment`,
  ADD COLUMN `business_reply_at` DATETIME DEFAULT NULL AFTER `business_reply`,
  ADD COLUMN `business_liked` TINYINT(1) NOT NULL DEFAULT 0 AFTER `business_reply_at`,
  ADD COLUMN `business_liked_at` DATETIME DEFAULT NULL AFTER `business_liked`;
