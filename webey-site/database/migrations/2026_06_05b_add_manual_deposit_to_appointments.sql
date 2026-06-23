-- Manuel (IBAN) kapora takibi için appointments alanları.
-- Mevcut deposit_required / deposit_amount korunur; iyzico appointment_payments'a
-- dokunulmaz. status: pending | paid | not_received | waived | refunded.
ALTER TABLE `appointments`
  ADD COLUMN `deposit_status` varchar(20) COLLATE utf8mb4_unicode_ci DEFAULT NULL AFTER `deposit_amount`,
  ADD COLUMN `deposit_reference_code` varchar(40) COLLATE utf8mb4_unicode_ci DEFAULT NULL AFTER `deposit_status`,
  ADD COLUMN `deposit_paid_at` datetime DEFAULT NULL AFTER `deposit_reference_code`,
  ADD COLUMN `deposit_marked_by` int unsigned DEFAULT NULL AFTER `deposit_paid_at`,
  ADD COLUMN `deposit_marked_at` datetime DEFAULT NULL AFTER `deposit_marked_by`,
  ADD KEY `idx_deposit_status` (`deposit_status`);
