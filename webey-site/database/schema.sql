-- phpMyAdmin SQL Dump
-- version 5.2.1deb3
-- https://www.phpmyadmin.net/
--
-- Anamakine: localhost:3306
-- Üretim Zamanı: 04 Nis 2026, 17:57:07
-- Sunucu sürümü: 8.0.45-0ubuntu0.24.04.1
-- PHP Sürümü: 8.3.6

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Veritabanı: `webey_prod`
--

-- --------------------------------------------------------

--
-- Tablo için tablo yapısı `admin_users`
--

CREATE TABLE `admin_users` (
  `id` int UNSIGNED NOT NULL,
  `user_id` int UNSIGNED NOT NULL,
  `onboarding_completed` tinyint(1) NOT NULL DEFAULT '0',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Tablo için tablo yapısı `api_rate_limits`
--

CREATE TABLE `api_rate_limits` (
  `cache_key` varchar(200) COLLATE utf8mb4_unicode_ci NOT NULL,
  `hits` smallint UNSIGNED NOT NULL DEFAULT '1',
  `expires_at` datetime NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='IP tabanlı rate limiting. Cron ile temizlenir.';

-- --------------------------------------------------------

--
-- Tablo için tablo yapısı `appointments`
--

CREATE TABLE `appointments` (
  `id` int UNSIGNED NOT NULL,
  `business_id` int UNSIGNED NOT NULL,
  `staff_id` int UNSIGNED DEFAULT NULL,
  `service_id` int UNSIGNED DEFAULT NULL,
  `customer_name` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `customer_phone` varchar(20) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `customer_email` varchar(191) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `customer_user_id` int UNSIGNED DEFAULT NULL,
  `start_at` datetime NOT NULL,
  `end_at` datetime NOT NULL,
  `status` enum('pending','approved','cancelled','no_show','completed','rejected','declined','cancellation_requested') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'pending',
  `attended` tinyint(1) DEFAULT NULL,
  `notes` text COLLATE utf8mb4_unicode_ci,
  `booking_source` enum('web','app','admin','phone','api') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'web' COMMENT 'Randevunun oluşturulduğu kanal',
  `reminder_24h_sent` tinyint(1) NOT NULL DEFAULT '0',
  `reminder_1h_sent` tinyint(1) NOT NULL DEFAULT '0',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Tablo için tablo yapısı `appointment_logs`
--

CREATE TABLE `appointment_logs` (
  `id` int UNSIGNED NOT NULL,
  `appointment_id` int UNSIGNED NOT NULL,
  `action` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `prev_status` varchar(50) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `new_status` varchar(50) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `actor_user_id` int UNSIGNED DEFAULT NULL COMMENT 'İşlemi yapan user (null = müşteri)',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Tablo için tablo yapısı `appointment_reminders`
--

CREATE TABLE `appointment_reminders` (
  `id` int UNSIGNED NOT NULL,
  `appointment_id` int UNSIGNED NOT NULL,
  `channel` enum('email','sms') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'email',
  `remind_before` tinyint UNSIGNED NOT NULL DEFAULT '24' COMMENT 'Kaç saat önce (24 veya 1)',
  `sent_at` datetime DEFAULT NULL,
  `status` enum('pending','sent','failed') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'pending',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Tablo için tablo yapısı `businesses`
--

CREATE TABLE `businesses` (
  `id` int UNSIGNED NOT NULL,
  `owner_id` int UNSIGNED NOT NULL,
  `name` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `slug` varchar(120) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `owner_name` varchar(100) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `phone` varchar(20) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `type` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'kuafor',
  `status` enum('draft','pending','active','rejected','suspended') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'draft',
  `city` varchar(80) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `district` varchar(80) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `address_line` varchar(300) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `about` text COLLATE utf8mb4_unicode_ci,
  `min_price` smallint UNSIGNED DEFAULT NULL,
  `max_price` smallint UNSIGNED DEFAULT NULL,
  `map_url` varchar(500) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `latitude` decimal(10,8) DEFAULT NULL,
  `longitude` decimal(11,8) DEFAULT NULL,
  `building_no` varchar(20) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `neighborhood` varchar(100) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `images_json` mediumtext COLLATE utf8mb4_unicode_ci,
  `staff_hours` tinyint(1) DEFAULT '0',
  `onboarding_step` tinyint NOT NULL DEFAULT '1',
  `onboarding_completed` tinyint(1) NOT NULL DEFAULT '0',
  `rejected_at` datetime DEFAULT NULL,
  `reject_reason` text COLLATE utf8mb4_unicode_ci,
  `approved_at` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `draft_data` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin
) ;

-- --------------------------------------------------------

--
-- Tablo için tablo yapısı `business_hours`
--

CREATE TABLE `business_hours` (
  `id` int UNSIGNED NOT NULL,
  `business_id` int UNSIGNED NOT NULL,
  `day` enum('mon','tue','wed','thu','fri','sat','sun') COLLATE utf8mb4_unicode_ci NOT NULL,
  `is_open` tinyint(1) NOT NULL DEFAULT '1',
  `open_time` time DEFAULT NULL,
  `close_time` time DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Tablo için tablo yapısı `csrf_tokens`
--

CREATE TABLE `csrf_tokens` (
  `id` int UNSIGNED NOT NULL,
  `session_id` varchar(128) COLLATE utf8mb4_unicode_ci NOT NULL,
  `token` varchar(64) COLLATE utf8mb4_unicode_ci NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `expires_at` datetime NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Her oturum için CSRF token. 2 saat ömürlü, cron ile temizlenir.';

-- --------------------------------------------------------

--
-- Tablo için tablo yapısı `customers`
--

CREATE TABLE `customers` (
  `id` int UNSIGNED NOT NULL,
  `user_id` int UNSIGNED NOT NULL,
  `first_name` varchar(80) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `last_name` varchar(80) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `phone` varchar(15) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `email` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `birthday` date DEFAULT NULL,
  `city` varchar(80) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `district` varchar(80) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `neighborhood` varchar(100) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `sms_ok` tinyint(1) NOT NULL DEFAULT '1',
  `email_ok` tinyint(1) NOT NULL DEFAULT '0',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Tablo için tablo yapısı `email_otp_tokens`
--

CREATE TABLE `email_otp_tokens` (
  `id` int UNSIGNED NOT NULL,
  `email` varchar(191) COLLATE utf8mb4_unicode_ci NOT NULL,
  `code` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'bcrypt hash',
  `purpose` varchar(30) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'email_verify',
  `attempts` tinyint UNSIGNED NOT NULL DEFAULT '0',
  `expires_at` datetime NOT NULL,
  `used_at` datetime DEFAULT NULL,
  `ip` varchar(45) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Tablo için tablo yapısı `email_queue`
--

CREATE TABLE `email_queue` (
  `id` bigint UNSIGNED NOT NULL,
  `to_email` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `to_name` varchar(100) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `subject` varchar(300) COLLATE utf8mb4_unicode_ci NOT NULL,
  `body_html` mediumtext COLLATE utf8mb4_unicode_ci NOT NULL,
  `status` enum('pending','sent','failed') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'pending',
  `attempts` tinyint UNSIGNED NOT NULL DEFAULT '0',
  `last_error` text COLLATE utf8mb4_unicode_ci,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `scheduled_at` datetime DEFAULT NULL COMMENT 'NULL = hemen gönder',
  `sent_at` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Async email kuyruğu. cron_send_emails.php tarafından işlenir.';

-- --------------------------------------------------------

--
-- Tablo için tablo yapısı `invoices`
--

CREATE TABLE `invoices` (
  `id` int UNSIGNED NOT NULL,
  `subscription_id` int UNSIGNED DEFAULT NULL,
  `user_id` int UNSIGNED NOT NULL,
  `plan_label` varchar(60) COLLATE utf8mb4_unicode_ci NOT NULL,
  `amount` decimal(10,2) NOT NULL,
  `status` enum('pending','paid','failed','refunded') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'pending',
  `iyzico_payment_id` varchar(100) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `pdf_url` varchar(300) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `paid_at` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Tablo için tablo yapısı `login_attempts`
--

CREATE TABLE `login_attempts` (
  `id` bigint UNSIGNED NOT NULL,
  `ip` varchar(45) COLLATE utf8mb4_unicode_ci NOT NULL,
  `attempted_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Tablo için tablo yapısı `mobile_device_tokens`
--

CREATE TABLE `mobile_device_tokens` (
  `id` int NOT NULL AUTO_INCREMENT,
  `user_id` int NOT NULL,
  `business_id` int DEFAULT NULL,
  `token` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `platform` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'android',
  `device_id` varchar(120) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `last_seen_at` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_token` (`token`),
  KEY `idx_user_active` (`user_id`, `is_active`),
  KEY `idx_business_active` (`business_id`, `is_active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Tablo için tablo yapısı `notifications`
--

CREATE TABLE `notifications` (
  `id` int UNSIGNED NOT NULL,
  `business_id` int UNSIGNED NOT NULL,
  `appointment_id` int UNSIGNED DEFAULT NULL,
  `type` enum('booking','cancellation','review','subscription_expiry_3d','subscription_expiry_1d','subscription_expired') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'booking',
  `customer_name` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `customer_phone` varchar(30) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `service_name` varchar(100) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `staff_name` varchar(100) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `appointment_start` datetime DEFAULT NULL,
  `result` enum('pending','approved','rejected','cancelled','cancel_approved','cancel_rejected','info') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'pending',
  `is_read` tinyint(1) NOT NULL DEFAULT '0',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0',
  `read_at` datetime DEFAULT NULL,
  `deleted_at` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Tablo için tablo yapısı `otp_tokens`
--

CREATE TABLE `otp_tokens` (
  `id` int UNSIGNED NOT NULL,
  `phone` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL,
  `code` char(6) COLLATE utf8mb4_unicode_ci NOT NULL,
  `purpose` enum('register','login','phone_change') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'register',
  `attempts` tinyint UNSIGNED NOT NULL DEFAULT '0',
  `expires_at` datetime NOT NULL,
  `used_at` datetime DEFAULT NULL,
  `ip` varchar(45) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='SMS OTP doğrulama token''ları. 5 dakika TTL.';

-- --------------------------------------------------------

--
-- Tablo için tablo yapısı `payment_cards`
--

CREATE TABLE `payment_cards` (
  `id` int UNSIGNED NOT NULL,
  `user_id` int UNSIGNED NOT NULL,
  `iyzico_card_token` varchar(200) COLLATE utf8mb4_unicode_ci NOT NULL,
  `card_brand` varchar(30) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'Visa, Mastercard, Troy, Amex',
  `card_last4` varchar(4) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `expire_month` varchar(2) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `expire_year` varchar(4) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `is_default` tinyint(1) NOT NULL DEFAULT '0',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `deleted_at` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Tablo için tablo yapısı `promo_codes`
--

CREATE TABLE `promo_codes` (
  `id` int UNSIGNED NOT NULL,
  `code` varchar(32) COLLATE utf8mb4_unicode_ci NOT NULL,
  `plan` varchar(30) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `discount_type` enum('free','percent','fixed') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'free',
  `discount_value` decimal(10,2) NOT NULL DEFAULT '100.00',
  `max_uses` int UNSIGNED DEFAULT NULL,
  `used_count` int UNSIGNED NOT NULL DEFAULT '0',
  `expires_at` datetime DEFAULT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  `note` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_by` int UNSIGNED DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Tablo için tablo yapısı `promo_code_uses`
--

CREATE TABLE `promo_code_uses` (
  `id` int UNSIGNED NOT NULL,
  `promo_id` int UNSIGNED NOT NULL,
  `user_id` int UNSIGNED NOT NULL,
  `business_id` int UNSIGNED DEFAULT NULL,
  `subscription_id` int UNSIGNED DEFAULT NULL,
  `used_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Tablo için tablo yapısı `push_subscriptions`
--

CREATE TABLE `push_subscriptions` (
  `id` int UNSIGNED NOT NULL,
  `user_id` int UNSIGNED NOT NULL,
  `endpoint` text COLLATE utf8mb4_unicode_ci NOT NULL,
  `p256dh` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `auth` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `user_agent` varchar(300) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `last_used_at` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Tablo için tablo yapısı `services`
--

CREATE TABLE `services` (
  `id` int UNSIGNED NOT NULL,
  `business_id` int UNSIGNED NOT NULL,
  `name` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `price` decimal(10,2) DEFAULT NULL,
  `duration_min` smallint NOT NULL DEFAULT '30',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Tablo için tablo yapısı `slot_locks`
--

CREATE TABLE `slot_locks` (
  `id` bigint UNSIGNED NOT NULL,
  `business_id` int UNSIGNED NOT NULL,
  `staff_id` int UNSIGNED NOT NULL DEFAULT '0' COMMENT '0 = tüm işletme için blok (staff bazlı değil)',
  `day_str` date NOT NULL,
  `start_min` smallint NOT NULL,
  `duration_min` smallint NOT NULL,
  `lock_token` varchar(64) COLLATE utf8mb4_unicode_ci NOT NULL,
  `expires_at` datetime NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Tablo için tablo yapısı `sms_queue`
--

CREATE TABLE `sms_queue` (
  `id` bigint UNSIGNED NOT NULL,
  `phone` varchar(15) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT '905XXXXXXXXX formatı',
  `message` varchar(480) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'Max 3 SMS uzunluğu (480 karakter)',
  `type` varchar(30) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'booking|approved|rejected|reminder_24h|reminder_1h',
  `appointment_id` int UNSIGNED DEFAULT NULL COMMENT 'İlgili randevu (opsiyonel)',
  `status` enum('pending','sent','failed') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'pending',
  `attempts` tinyint UNSIGNED NOT NULL DEFAULT '0',
  `last_error` text COLLATE utf8mb4_unicode_ci,
  `scheduled_at` datetime DEFAULT NULL COMMENT 'NULL = hemen gönder',
  `sent_at` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='SMS kuyruğu. cron_send_sms.php tarafından işlenir.';

-- --------------------------------------------------------

--
-- Tablo için tablo yapısı `staff`
--

CREATE TABLE `staff` (
  `id` int UNSIGNED NOT NULL,
  `business_id` int UNSIGNED NOT NULL,
  `name` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `phone` varchar(20) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `color` varchar(30) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `is_active` tinyint(1) NOT NULL DEFAULT '1'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Tablo için tablo yapısı `staff_hours`
--

CREATE TABLE `staff_hours` (
  `id` int UNSIGNED NOT NULL,
  `staff_id` int UNSIGNED NOT NULL,
  `business_id` int UNSIGNED NOT NULL,
  `day` enum('mon','tue','wed','thu','fri','sat','sun') COLLATE utf8mb4_unicode_ci NOT NULL,
  `is_open` tinyint(1) NOT NULL DEFAULT '1',
  `open_time` time DEFAULT NULL,
  `close_time` time DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Tablo için tablo yapısı `staff_services`
--

CREATE TABLE `staff_services` (
  `staff_id` int UNSIGNED NOT NULL,
  `service_id` int UNSIGNED NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Tablo için tablo yapısı `subscriptions`
--

CREATE TABLE `subscriptions` (
  `id` int UNSIGNED NOT NULL,
  `user_id` int UNSIGNED NOT NULL,
  `plan` varchar(30) COLLATE utf8mb4_unicode_ci NOT NULL,
  `status` enum('trialing','active','cancelled','expired','past_due','queued') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'trialing',
  `price` decimal(10,2) NOT NULL DEFAULT '0.00',
  `start_date` datetime NOT NULL,
  `end_date` datetime NOT NULL,
  `cancel_at_period_end` tinyint(1) NOT NULL DEFAULT '0',
  `cancelled_at` datetime DEFAULT NULL,
  `iyzico_subscription_id` varchar(100) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Tablo için tablo yapısı `subscription_reminders`
--

CREATE TABLE `subscription_reminders` (
  `id` int UNSIGNED NOT NULL,
  `subscription_id` int UNSIGNED NOT NULL,
  `remind_type` enum('expiry_3d','expiry_1d','expired') COLLATE utf8mb4_unicode_ci NOT NULL,
  `channel` enum('notification','email','sms') COLLATE utf8mb4_unicode_ci NOT NULL,
  `status` enum('sent','failed') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'sent',
  `sent_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Tablo için tablo yapısı `users`
--

CREATE TABLE `users` (
  `id` int UNSIGNED NOT NULL,
  `google_id` varchar(64) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `email` varchar(191) COLLATE utf8mb4_unicode_ci NOT NULL,
  `avatar_url` varchar(500) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `email_verified_at` datetime DEFAULT NULL,
  `phone_verified_at` datetime DEFAULT NULL,
  `email_verify_token` varchar(128) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `email_verify_sent_at` datetime DEFAULT NULL,
  `password_hash` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `reset_token` varchar(128) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `reset_token_expires` datetime DEFAULT NULL,
  `name` varchar(100) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `role` enum('admin','user','staff','superadmin') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'user',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `last_login_at` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Tablo için tablo yapısı `user_notifications`
--

CREATE TABLE `user_notifications` (
  `id` int UNSIGNED NOT NULL,
  `user_id` int UNSIGNED NOT NULL,
  `appointment_id` int UNSIGNED DEFAULT NULL,
  `type` enum('appt_approved','appt_cancelled','appt_rejected','appt_reminder','info') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'info',
  `title` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `message` text COLLATE utf8mb4_unicode_ci,
  `business_name` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `is_read` tinyint(1) NOT NULL DEFAULT '0',
  `read_at` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dökümü yapılmış tablolar için indeksler
--

--
-- Tablo için indeksler `admin_users`
--
ALTER TABLE `admin_users`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_admin_users_user_id` (`user_id`);

--
-- Tablo için indeksler `api_rate_limits`
--
ALTER TABLE `api_rate_limits`
  ADD PRIMARY KEY (`cache_key`),
  ADD KEY `idx_rl_expires` (`expires_at`);

--
-- Tablo için indeksler `appointments`
--
ALTER TABLE `appointments`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_appt_business_start` (`business_id`,`start_at`),
  ADD KEY `idx_appt_staff_start` (`staff_id`,`start_at`),
  ADD KEY `fk_appt_service` (`service_id`),
  ADD KEY `idx_appt_status` (`status`),
  ADD KEY `idx_appt_customer_phone` (`customer_phone`),
  ADD KEY `idx_reminder_check` (`status`,`start_at`,`reminder_24h_sent`,`reminder_1h_sent`),
  ADD KEY `idx_appt_biz_staff_time` (`business_id`,`staff_id`,`start_at`),
  ADD KEY `idx_appt_customer_time` (`customer_user_id`,`start_at`),
  ADD KEY `idx_customer_user_id` (`customer_user_id`),
  ADD KEY `idx_business_start_at` (`business_id`,`start_at`),
  ADD KEY `idx_staff_start_status` (`staff_id`,`start_at`,`status`),
  ADD KEY `idx_status_created` (`status`,`created_at`);

--
-- Tablo için indeksler `appointment_logs`
--
ALTER TABLE `appointment_logs`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_appt_log_appt` (`appointment_id`),
  ADD KEY `idx_appt_log_created` (`created_at`);

--
-- Tablo için indeksler `appointment_reminders`
--
ALTER TABLE `appointment_reminders`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_appt_remind` (`appointment_id`,`channel`,`remind_before`),
  ADD KEY `idx_status_created` (`status`,`created_at`);

--
-- Tablo için indeksler `businesses`
--
ALTER TABLE `businesses`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_businesses_owner` (`owner_id`),
  ADD UNIQUE KEY `uq_business_slug` (`slug`),
  ADD KEY `idx_owner_id` (`owner_id`),
  ADD KEY `idx_biz_status` (`status`),
  ADD KEY `idx_biz_city_district` (`city`,`district`),
  ADD KEY `idx_biz_onboarding` (`onboarding_completed`),
  ADD KEY `idx_biz_city_status` (`city`,`status`,`id`),
  ADD KEY `idx_city_district_status` (`city`,`district`,`status`),
  ADD KEY `idx_status_onboarding` (`status`,`onboarding_completed`),
  ADD KEY `idx_slug` (`slug`);

--
-- Tablo için indeksler `business_hours`
--
ALTER TABLE `business_hours`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_business_hours_day` (`business_id`,`day`);

--
-- Tablo için indeksler `csrf_tokens`
--
ALTER TABLE `csrf_tokens`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_session` (`session_id`),
  ADD KEY `idx_token` (`token`),
  ADD KEY `idx_expires` (`expires_at`);

--
-- Tablo için indeksler `customers`
--
ALTER TABLE `customers`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_user` (`user_id`),
  ADD UNIQUE KEY `uq_cust_email` (`email`),
  ADD KEY `idx_cust_phone` (`phone`),
  ADD KEY `idx_phone` (`phone`);

--
-- Tablo için indeksler `email_otp_tokens`
--
ALTER TABLE `email_otp_tokens`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_email_otp` (`email`,`expires_at`);

--
-- Tablo için indeksler `email_queue`
--
ALTER TABLE `email_queue`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_eq_status_scheduled` (`status`,`scheduled_at`,`created_at`);

--
-- Tablo için indeksler `invoices`
--
ALTER TABLE `invoices`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_user_id` (`user_id`),
  ADD KEY `idx_subscription_id` (`subscription_id`);

--
-- Tablo için indeksler `login_attempts`
--
ALTER TABLE `login_attempts`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_ip_time` (`ip`,`attempted_at`);

--
-- Tablo için indeksler `notifications`
--
ALTER TABLE `notifications`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_business` (`business_id`),
  ADD KEY `idx_business_read` (`business_id`,`is_deleted`,`is_read`),
  ADD KEY `idx_appt_type` (`appointment_id`,`type`);

--
-- Tablo için indeksler `otp_tokens`
--
ALTER TABLE `otp_tokens`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_otp_phone_expires` (`phone`,`expires_at`),
  ADD KEY `idx_otp_code` (`code`,`expires_at`);

--
-- Tablo için indeksler `payment_cards`
--
ALTER TABLE `payment_cards`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `unique_token` (`iyzico_card_token`),
  ADD KEY `idx_user_id` (`user_id`);

--
-- Tablo için indeksler `promo_codes`
--
ALTER TABLE `promo_codes`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_promo_code` (`code`),
  ADD KEY `idx_promo_active` (`is_active`,`expires_at`),
  ADD KEY `idx_promo_plan` (`plan`);

--
-- Tablo için indeksler `promo_code_uses`
--
ALTER TABLE `promo_code_uses`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_promo_user` (`promo_id`,`user_id`),
  ADD KEY `idx_pcu_user` (`user_id`),
  ADD KEY `idx_pcu_promo` (`promo_id`);

--
-- Tablo için indeksler `push_subscriptions`
--
ALTER TABLE `push_subscriptions`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_user` (`user_id`);

--
-- Tablo için indeksler `services`
--
ALTER TABLE `services`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_svc_business_name` (`business_id`,`name`);

--
-- Tablo için indeksler `slot_locks`
--
ALTER TABLE `slot_locks`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_slot` (`business_id`,`staff_id`,`day_str`,`start_min`),
  ADD KEY `idx_business_date` (`business_id`,`day_str`,`expires_at`),
  ADD KEY `idx_token` (`lock_token`),
  ADD KEY `idx_expires` (`expires_at`);

--
-- Tablo için indeksler `sms_queue`
--
ALTER TABLE `sms_queue`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_sms_status_scheduled` (`status`,`scheduled_at`,`created_at`),
  ADD KEY `idx_sms_appt` (`appointment_id`),
  ADD KEY `idx_sms_phone` (`phone`);

--
-- Tablo için indeksler `staff`
--
ALTER TABLE `staff`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_staff_biz_active` (`business_id`,`is_active`);

--
-- Tablo için indeksler `staff_hours`
--
ALTER TABLE `staff_hours`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_staff_day` (`staff_id`,`day`),
  ADD KEY `fk_sh_business` (`business_id`);

--
-- Tablo için indeksler `staff_services`
--
ALTER TABLE `staff_services`
  ADD PRIMARY KEY (`staff_id`,`service_id`),
  ADD KEY `service_id` (`service_id`);

--
-- Tablo için indeksler `subscriptions`
--
ALTER TABLE `subscriptions`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_sub_user_status_end` (`user_id`,`status`,`end_date`);

--
-- Tablo için indeksler `subscription_reminders`
--
ALTER TABLE `subscription_reminders`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_sub_remind` (`subscription_id`,`remind_type`,`channel`);

--
-- Tablo için indeksler `users`
--
ALTER TABLE `users`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_users_email` (`email`),
  ADD KEY `idx_email_verify_token` (`email_verify_token`),
  ADD KEY `idx_reset_token` (`reset_token`),
  ADD KEY `idx_users_google_id` (`google_id`),
  ADD KEY `idx_role_created` (`role`,`created_at`);

--
-- Tablo için indeksler `user_notifications`
--
ALTER TABLE `user_notifications`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_un_user_read` (`user_id`,`is_read`),
  ADD KEY `idx_un_user_created` (`user_id`,`created_at`);

--
-- Dökümü yapılmış tablolar için AUTO_INCREMENT değeri
--

--
-- Tablo için AUTO_INCREMENT değeri `admin_users`
--
ALTER TABLE `admin_users`
  MODIFY `id` int UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- Tablo için AUTO_INCREMENT değeri `appointments`
--
ALTER TABLE `appointments`
  MODIFY `id` int UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- Tablo için AUTO_INCREMENT değeri `appointment_logs`
--
ALTER TABLE `appointment_logs`
  MODIFY `id` int UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- Tablo için AUTO_INCREMENT değeri `appointment_reminders`
--
ALTER TABLE `appointment_reminders`
  MODIFY `id` int UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- Tablo için AUTO_INCREMENT değeri `businesses`
--
ALTER TABLE `businesses`
  MODIFY `id` int UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- Tablo için AUTO_INCREMENT değeri `business_hours`
--
ALTER TABLE `business_hours`
  MODIFY `id` int UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- Tablo için AUTO_INCREMENT değeri `csrf_tokens`
--
ALTER TABLE `csrf_tokens`
  MODIFY `id` int UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- Tablo için AUTO_INCREMENT değeri `customers`
--
ALTER TABLE `customers`
  MODIFY `id` int UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- Tablo için AUTO_INCREMENT değeri `email_otp_tokens`
--
ALTER TABLE `email_otp_tokens`
  MODIFY `id` int UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- Tablo için AUTO_INCREMENT değeri `email_queue`
--
ALTER TABLE `email_queue`
  MODIFY `id` bigint UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- Tablo için AUTO_INCREMENT değeri `invoices`
--
ALTER TABLE `invoices`
  MODIFY `id` int UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- Tablo için AUTO_INCREMENT değeri `login_attempts`
--
ALTER TABLE `login_attempts`
  MODIFY `id` bigint UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- Tablo için AUTO_INCREMENT değeri `notifications`
--
ALTER TABLE `notifications`
  MODIFY `id` int UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- Tablo için AUTO_INCREMENT değeri `otp_tokens`
--
ALTER TABLE `otp_tokens`
  MODIFY `id` int UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- Tablo için AUTO_INCREMENT değeri `payment_cards`
--
ALTER TABLE `payment_cards`
  MODIFY `id` int UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- Tablo için AUTO_INCREMENT değeri `promo_codes`
--
ALTER TABLE `promo_codes`
  MODIFY `id` int UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- Tablo için AUTO_INCREMENT değeri `promo_code_uses`
--
ALTER TABLE `promo_code_uses`
  MODIFY `id` int UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- Tablo için AUTO_INCREMENT değeri `push_subscriptions`
--
ALTER TABLE `push_subscriptions`
  MODIFY `id` int UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- Tablo için AUTO_INCREMENT değeri `services`
--
ALTER TABLE `services`
  MODIFY `id` int UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- Tablo için AUTO_INCREMENT değeri `slot_locks`
--
ALTER TABLE `slot_locks`
  MODIFY `id` bigint UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- Tablo için AUTO_INCREMENT değeri `sms_queue`
--
ALTER TABLE `sms_queue`
  MODIFY `id` bigint UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- Tablo için AUTO_INCREMENT değeri `staff`
--
ALTER TABLE `staff`
  MODIFY `id` int UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- Tablo için AUTO_INCREMENT değeri `staff_hours`
--
ALTER TABLE `staff_hours`
  MODIFY `id` int UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- Tablo için AUTO_INCREMENT değeri `subscriptions`
--
ALTER TABLE `subscriptions`
  MODIFY `id` int UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- Tablo için AUTO_INCREMENT değeri `subscription_reminders`
--
ALTER TABLE `subscription_reminders`
  MODIFY `id` int UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- Tablo için AUTO_INCREMENT değeri `users`
--
ALTER TABLE `users`
  MODIFY `id` int UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- Tablo için AUTO_INCREMENT değeri `user_notifications`
--
ALTER TABLE `user_notifications`
  MODIFY `id` int UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- Dökümü yapılmış tablolar için kısıtlamalar
--

--
-- Tablo kısıtlamaları `admin_users`
--
ALTER TABLE `admin_users`
  ADD CONSTRAINT `fk_admin_users_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;

--
-- Tablo kısıtlamaları `appointments`
--
ALTER TABLE `appointments`
  ADD CONSTRAINT `fk_appt_business` FOREIGN KEY (`business_id`) REFERENCES `businesses` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_appt_customer_user` FOREIGN KEY (`customer_user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_appt_service` FOREIGN KEY (`service_id`) REFERENCES `services` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_appt_staff` FOREIGN KEY (`staff_id`) REFERENCES `staff` (`id`) ON DELETE SET NULL;

--
-- Tablo kısıtlamaları `businesses`
--
ALTER TABLE `businesses`
  ADD CONSTRAINT `fk_businesses_owner` FOREIGN KEY (`owner_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;

--
-- Tablo kısıtlamaları `business_hours`
--
ALTER TABLE `business_hours`
  ADD CONSTRAINT `fk_bh_business` FOREIGN KEY (`business_id`) REFERENCES `businesses` (`id`) ON DELETE CASCADE;

--
-- Tablo kısıtlamaları `customers`
--
ALTER TABLE `customers`
  ADD CONSTRAINT `fk_cust_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;

--
-- Tablo kısıtlamaları `push_subscriptions`
--
ALTER TABLE `push_subscriptions`
  ADD CONSTRAINT `fk_push_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;

--
-- Tablo kısıtlamaları `services`
--
ALTER TABLE `services`
  ADD CONSTRAINT `fk_services_business` FOREIGN KEY (`business_id`) REFERENCES `businesses` (`id`) ON DELETE CASCADE;

--
-- Tablo kısıtlamaları `staff`
--
ALTER TABLE `staff`
  ADD CONSTRAINT `fk_staff_business` FOREIGN KEY (`business_id`) REFERENCES `businesses` (`id`) ON DELETE CASCADE;

--
-- Tablo kısıtlamaları `staff_hours`
--
ALTER TABLE `staff_hours`
  ADD CONSTRAINT `fk_sh_business` FOREIGN KEY (`business_id`) REFERENCES `businesses` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_sh_staff` FOREIGN KEY (`staff_id`) REFERENCES `staff` (`id`) ON DELETE CASCADE;

--
-- Tablo kısıtlamaları `staff_services`
--
ALTER TABLE `staff_services`
  ADD CONSTRAINT `staff_services_ibfk_1` FOREIGN KEY (`staff_id`) REFERENCES `staff` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `staff_services_ibfk_2` FOREIGN KEY (`service_id`) REFERENCES `services` (`id`) ON DELETE CASCADE;

--
-- Tablo kısıtlamaları `user_notifications`
--
ALTER TABLE `user_notifications`
  ADD CONSTRAINT `fk_un_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;

DELIMITER $$
--
-- Olaylar
--
CREATE DEFINER=`root`@`localhost` EVENT `evt_cleanup_login_attempts` ON SCHEDULE EVERY 1 HOUR STARTS '2026-03-02 03:13:48' ON COMPLETION NOT PRESERVE ENABLE COMMENT 'Eski giriş denemelerini temizle' DO DELETE FROM `login_attempts`
    WHERE `attempted_at` < DATE_SUB(NOW(), INTERVAL 1 HOUR)$$

CREATE DEFINER=`root`@`localhost` EVENT `evt_cleanup_csrf_tokens` ON SCHEDULE EVERY 4 HOUR STARTS '2026-03-02 03:13:48' ON COMPLETION NOT PRESERVE ENABLE COMMENT 'Süresi dolmuş CSRF tokenlarını temizle' DO DELETE FROM `csrf_tokens`
    WHERE `expires_at` < NOW()$$

DELIMITER ;
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
