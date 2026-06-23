-- Türkiye il / ilçe / mahalle dataset tabloları.
-- Idempotent: tablolar yoksa oluşturur, varsa dokunmaz.
-- Sokak/cadde tablosu opsiyonel (bu turda kullanılmıyor) ama şema hazır.

CREATE TABLE IF NOT EXISTS address_provinces (
  id INT PRIMARY KEY,
  name VARCHAR(80) NOT NULL,
  slug VARCHAR(80) NOT NULL,
  plate_code SMALLINT NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_provinces_slug (slug),
  UNIQUE KEY uq_provinces_plate (plate_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS address_districts (
  id INT PRIMARY KEY AUTO_INCREMENT,
  province_id INT NOT NULL,
  name VARCHAR(100) NOT NULL,
  slug VARCHAR(120) NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY idx_districts_province (province_id),
  KEY idx_districts_province_name (province_id, name),
  UNIQUE KEY uq_districts_province_slug (province_id, slug),
  CONSTRAINT fk_districts_province FOREIGN KEY (province_id) REFERENCES address_provinces(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS address_neighborhoods (
  id INT PRIMARY KEY AUTO_INCREMENT,
  province_id INT NOT NULL,
  district_id INT NOT NULL,
  name VARCHAR(160) NOT NULL,
  slug VARCHAR(180) NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY idx_neigh_district (district_id),
  KEY idx_neigh_district_name (district_id, name),
  KEY idx_neigh_province_district (province_id, district_id),
  UNIQUE KEY uq_neigh_district_slug (district_id, slug),
  CONSTRAINT fk_neigh_province FOREIGN KEY (province_id) REFERENCES address_provinces(id) ON DELETE CASCADE,
  CONSTRAINT fk_neigh_district FOREIGN KEY (district_id) REFERENCES address_districts(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
