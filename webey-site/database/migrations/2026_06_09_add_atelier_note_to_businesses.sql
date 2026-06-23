-- İşletme "Atölye notu" alanı (kısa, italik vitrin notu — about'tan ayrı).
-- Mevcut `about` korunur; atelier_note opsiyonel ve kısa tutulur.
ALTER TABLE `businesses`
  ADD COLUMN `atelier_note` varchar(280) COLLATE utf8mb4_unicode_ci DEFAULT NULL AFTER `about`;
