-- Harita endpointi (salons.php?view=map) bounds sorguları için konum indexi.
-- Opsiyonel performans migration'ı: mevcut salon sayısında şart değil,
-- salon sayısı binlere yaklaşınca uygulanmalı.
--
-- Preflight: SHOW INDEX FROM businesses WHERE Key_name = 'idx_businesses_location';
-- Uygulama:  mysql -u root -p webey_prod < 2026_06_10_add_location_index_to_businesses.sql
-- Post-check: SHOW INDEX FROM businesses WHERE Key_name = 'idx_businesses_location';

ALTER TABLE businesses
  ADD INDEX idx_businesses_location (latitude, longitude, status);
