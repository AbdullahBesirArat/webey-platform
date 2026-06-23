-- Business sadakat sistemi: program + müşteri progress + event log.
-- Idempotent: tablo varsa dokunmaz.

CREATE TABLE IF NOT EXISTS business_loyalty_programs (
  id INT PRIMARY KEY AUTO_INCREMENT,
  business_id INT NOT NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 0,
  required_visits SMALLINT NOT NULL DEFAULT 5,
  reward_title VARCHAR(160) NOT NULL DEFAULT '',
  reward_description TEXT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_loyalty_business (business_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS business_loyalty_progress (
  id INT PRIMARY KEY AUTO_INCREMENT,
  business_id INT NOT NULL,
  customer_user_id INT NULL,
  customer_phone VARCHAR(40) NULL,
  customer_name VARCHAR(160) NOT NULL DEFAULT '',
  visits_count INT NOT NULL DEFAULT 0,
  rewards_earned INT NOT NULL DEFAULT 0,
  rewards_used INT NOT NULL DEFAULT 0,
  last_appointment_id INT NULL,
  last_visit_at DATETIME NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY idx_loyalty_progress_business (business_id),
  KEY idx_loyalty_progress_user (business_id, customer_user_id),
  KEY idx_loyalty_progress_phone (business_id, customer_phone)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS business_loyalty_events (
  id INT PRIMARY KEY AUTO_INCREMENT,
  business_id INT NOT NULL,
  progress_id INT NULL,
  customer_user_id INT NULL,
  customer_phone VARCHAR(40) NULL,
  appointment_id INT NULL,
  event_type ENUM('visit','reward_earned','reward_used','adjustment') NOT NULL,
  visits_delta INT NOT NULL DEFAULT 0,
  rewards_delta INT NOT NULL DEFAULT 0,
  note VARCHAR(255) NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY idx_loyalty_events_business (business_id),
  KEY idx_loyalty_events_appt (appointment_id),
  UNIQUE KEY uq_loyalty_events_visit_appt (event_type, appointment_id, business_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
