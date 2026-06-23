-- 2026_06_11_create_service_categories.sql
-- Idempotent migration: hizmet kategorisi altyapisi.
--
--   1) service_categories tablosu
--      - business_id = 0  -> sistem (global) kategorisi
--      - business_id > 0  -> isletmeye ozel kategori
--   2) Sistem kategorileri seed (INSERT IGNORE, slug sabit)
--   3) business_categories tablosu (onboarding ana kategori secimi)
--   4) services tablosuna eksik kolonlar (guarded):
--      description, category (text fallback), is_active, sort_order, category_id
--   5) services(business_id, category_id) index
--   6) Mevcut services.category text degerlerini sistem kategorilerine map et
--   7) businesses.type -> business_categories seed
--
-- Veri kaybi yok: hicbir satir silinmez, mevcut category text alani korunur.

-- ----- 1) service_categories ------------------------------------------------
CREATE TABLE IF NOT EXISTS service_categories (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  business_id INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '0 = sistem kategorisi',
  name VARCHAR(80) COLLATE utf8mb4_unicode_ci NOT NULL,
  slug VARCHAR(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  icon_key VARCHAR(40) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  sort_order INT NOT NULL DEFAULT 0,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_business_slug (business_id, slug),
  KEY idx_business (business_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----- 2) Sistem kategorileri seed -------------------------------------------
-- Slug'lar mobil uygulamadaki mevcut filtre/ikon slug'lariyla birebir ayni
-- kalmali (nail_studio, lash_brow, ...). INSERT IGNORE: tekrar calistirilabilir.
INSERT IGNORE INTO service_categories
  (business_id, name, slug, icon_key, sort_order, is_active)
VALUES
  (0, 'Tırnak Stüdyosu',  'nail_studio',      'nail',     10, 1),
  (0, 'Kirpik ve Kaş',    'lash_brow',        'eye',      20, 1),
  (0, 'Cilt Bakımı',      'skin_care',        'sparkles', 30, 1),
  (0, 'Lazer Epilasyon',  'laser_epilation',  'zap',      40, 1),
  (0, 'Kuaför',           'hair_salon',       'scissors', 50, 1),
  (0, 'Makyaj Stüdyosu',  'makeup_studio',    'brush',    60, 1),
  (0, 'Spa ve Masaj',     'spa_massage',      'spa',      70, 1),
  (0, 'Güzellik Salonu',  'beauty_salon',     'sparkles', 80, 1),
  (0, 'Manikür / Pedikür','manicure_pedicure','nail',     90, 1),
  (0, 'Saç Bakımı',       'hair_care',        'scissors', 100, 1),
  (0, 'Kaş Tasarım',      'brow_design',      'eye',      110, 1),
  (0, 'Protez Tırnak',    'prosthetic_nail',  'nail',     120, 1),
  (0, 'Kalıcı Makyaj',    'permanent_makeup', 'brush',    130, 1);

-- ----- 3) business_categories (onboarding ana kategori secimi) ---------------
CREATE TABLE IF NOT EXISTS business_categories (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  business_id INT UNSIGNED NOT NULL,
  category_id INT UNSIGNED NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_business_category (business_id, category_id),
  KEY idx_category (category_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----- 4) services eksik kolonlar (guarded) -----------------------------------
SET @col_exists := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'services' AND COLUMN_NAME = 'description'
);
SET @sql := IF(@col_exists = 0,
  'ALTER TABLE services ADD COLUMN description TEXT NULL DEFAULT NULL AFTER name',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_exists := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'services' AND COLUMN_NAME = 'category'
);
SET @sql := IF(@col_exists = 0,
  'ALTER TABLE services ADD COLUMN category VARCHAR(80) NULL DEFAULT NULL AFTER description',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_exists := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'services' AND COLUMN_NAME = 'is_active'
);
SET @sql := IF(@col_exists = 0,
  'ALTER TABLE services ADD COLUMN is_active TINYINT(1) NOT NULL DEFAULT 1',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_exists := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'services' AND COLUMN_NAME = 'sort_order'
);
SET @sql := IF(@col_exists = 0,
  'ALTER TABLE services ADD COLUMN sort_order INT NOT NULL DEFAULT 0',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_exists := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'services' AND COLUMN_NAME = 'category_id'
);
SET @sql := IF(@col_exists = 0,
  'ALTER TABLE services ADD COLUMN category_id INT UNSIGNED NULL DEFAULT NULL AFTER category',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ----- 5) services(business_id, category_id) index ----------------------------
SET @idx_exists := (
  SELECT COUNT(*) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'services' AND INDEX_NAME = 'idx_services_business_category'
);
SET @sql := IF(@idx_exists = 0,
  'ALTER TABLE services ADD INDEX idx_services_business_category (business_id, category_id)',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ----- 6) Mevcut category text -> category_id map (best effort) ---------------
-- Once birebir slug/isim eslesmesi:
UPDATE services s
JOIN service_categories sc ON sc.business_id = 0 AND sc.is_active = 1
SET s.category_id = sc.id
WHERE s.category_id IS NULL
  AND s.category IS NOT NULL
  AND (LOWER(TRIM(s.category)) = sc.slug OR LOWER(TRIM(s.category)) = LOWER(sc.name));

-- Sik kullanilan anahtar kelimeler (eski serbest metin degerler):
UPDATE services s
JOIN service_categories sc ON sc.business_id = 0 AND sc.slug = 'nail_studio'
SET s.category_id = sc.id
WHERE s.category_id IS NULL AND s.category IS NOT NULL
  AND (LOWER(s.category) LIKE '%nail%' OR LOWER(s.category) LIKE '%tirnak%'
       OR LOWER(s.category) LIKE '%tırnak%' OR LOWER(s.category) LIKE '%oje%'
       OR LOWER(s.category) LIKE '%manik%' OR LOWER(s.category) LIKE '%pedik%');

UPDATE services s
JOIN service_categories sc ON sc.business_id = 0 AND sc.slug = 'hair_salon'
SET s.category_id = sc.id
WHERE s.category_id IS NULL AND s.category IS NOT NULL
  AND (LOWER(s.category) LIKE '%hair%' OR LOWER(s.category) LIKE '%sac%'
       OR LOWER(s.category) LIKE '%saç%' OR LOWER(s.category) LIKE '%kuaf%');

UPDATE services s
JOIN service_categories sc ON sc.business_id = 0 AND sc.slug = 'skin_care'
SET s.category_id = sc.id
WHERE s.category_id IS NULL AND s.category IS NOT NULL
  AND (LOWER(s.category) LIKE '%skin%' OR LOWER(s.category) LIKE '%cilt%');

UPDATE services s
JOIN service_categories sc ON sc.business_id = 0 AND sc.slug = 'laser_epilation'
SET s.category_id = sc.id
WHERE s.category_id IS NULL AND s.category IS NOT NULL
  AND (LOWER(s.category) LIKE '%laser%' OR LOWER(s.category) LIKE '%lazer%'
       OR LOWER(s.category) LIKE '%epilasyon%');

UPDATE services s
JOIN service_categories sc ON sc.business_id = 0 AND sc.slug = 'lash_brow'
SET s.category_id = sc.id
WHERE s.category_id IS NULL AND s.category IS NOT NULL
  AND (LOWER(s.category) LIKE '%lash%' OR LOWER(s.category) LIKE '%brow%'
       OR LOWER(s.category) LIKE '%kirpik%' OR LOWER(s.category) LIKE '%kas%'
       OR LOWER(s.category) LIKE '%kaş%');

UPDATE services s
JOIN service_categories sc ON sc.business_id = 0 AND sc.slug = 'makeup_studio'
SET s.category_id = sc.id
WHERE s.category_id IS NULL AND s.category IS NOT NULL
  AND (LOWER(s.category) LIKE '%makeup%' OR LOWER(s.category) LIKE '%makyaj%');

UPDATE services s
JOIN service_categories sc ON sc.business_id = 0 AND sc.slug = 'spa_massage'
SET s.category_id = sc.id
WHERE s.category_id IS NULL AND s.category IS NOT NULL
  AND (LOWER(s.category) LIKE '%spa%' OR LOWER(s.category) LIKE '%masaj%'
       OR LOWER(s.category) LIKE '%massage%');

-- Map edilemeyenler: category_id NULL kalir, eski text 'category' fallback olarak
-- korunur ("Kategorisiz" / eski metin gosterimi app tarafinda yapilir).

-- ----- 7) businesses.type -> business_categories seed --------------------------
INSERT IGNORE INTO business_categories (business_id, category_id)
SELECT b.id, sc.id
FROM businesses b
JOIN service_categories sc ON sc.business_id = 0 AND sc.slug = (
  CASE
    WHEN LOWER(b.type) IN ('kuafor', 'kuaför', 'hair', 'hair_salon') THEN 'hair_salon'
    WHEN LOWER(b.type) IN ('nail', 'nail_studio') THEN 'nail_studio'
    WHEN LOWER(b.type) IN ('guzellik', 'güzellik', 'beauty', 'beauty_salon') THEN 'beauty_salon'
    WHEN LOWER(b.type) IN ('makeup', 'makeup_studio', 'makyaj') THEN 'makeup_studio'
    WHEN LOWER(b.type) IN ('spa', 'spa_massage', 'masaj') THEN 'spa_massage'
    WHEN LOWER(b.type) IN ('lash', 'lash_brow') THEN 'lash_brow'
    WHEN LOWER(b.type) IN ('skin', 'skin_care', 'cilt') THEN 'skin_care'
    WHEN LOWER(b.type) IN ('laser', 'laser_epilation', 'lazer') THEN 'laser_epilation'
    ELSE NULL
  END
)
WHERE b.type IS NOT NULL AND b.type <> '';
