-- ════════════════════════════════════════════════════════════════════════════
-- 2026_06_13c_backfill_subscriptions.sql
-- Faz 3 geçiş backfill: müşteri tarafında ŞU AN görünen aktif işletmelerin,
-- görünürlük abonelik durumuna bağlanınca KAYBOLMAMASI için başlangıç aboneliği.
--
-- KURAL:
--  * Yalnızca businesses.status='active' VE onboarding_completed=1 işletmeler.
--  * Halihazırda business_subscriptions kaydı OLMAYANLAR (NOT EXISTS).
--  * draft/pending/rejected/suspended işletmelere DOKUNMAZ.
--  * status='trial', 30 günlük, monthly_price=2500, payment_method='free',
--    notes='Faz 3 geçiş backfill denemesi'.
--  * Her backfill kaydı için audit (action='transition_backfill_trial').
--  * IDEMPOTENT: ikinci kez çalıştırıldığında ikinci kayıt/ikinci audit açmaz.
--  * Eski iyzico `subscriptions` tablosuna DOKUNMAZ.
--
-- ÖNEMLİ: Canlıda full backup SONRASI çalıştır; backfill öncesi/sonrası public
-- salon sayısını karşılaştır (beklenmedik düşüş olmamalı).
-- ════════════════════════════════════════════════════════════════════════════

-- 1) Backfill abonelik kayıtları (idempotent: NOT EXISTS).
INSERT INTO `business_subscriptions`
  (`business_id`, `plan_id`, `status`, `monthly_price`,
   `trial_started_at`, `trial_ends_at`, `current_period_start`, `current_period_end`,
   `next_payment_due_at`, `payment_method`, `notes`, `created_by`, `updated_by`, `created_at`, `updated_at`)
SELECT
   b.id,
   (SELECT p.id FROM `business_subscription_plans` p WHERE p.code = 'webey_business' AND p.is_active = 1 LIMIT 1),
   'trial', 2500.00,
   NOW(), DATE_ADD(NOW(), INTERVAL 30 DAY), NOW(), DATE_ADD(NOW(), INTERVAL 30 DAY),
   DATE_ADD(NOW(), INTERVAL 30 DAY), 'free', 'Faz 3 geçiş backfill denemesi', NULL, NULL, NOW(), NOW()
FROM `businesses` b
WHERE b.status = 'active'
  AND b.onboarding_completed = 1
  AND NOT EXISTS (SELECT 1 FROM `business_subscriptions` s WHERE s.business_id = b.id);

-- 2) Backfill kayıtları için audit (idempotent: aynı sub için ikinci audit açma).
INSERT INTO `business_subscription_audit`
  (`subscription_id`, `business_id`, `action`, `from_status`, `to_status`, `payload_json`, `actor_user_id`, `created_at`)
SELECT s.id, s.business_id, 'transition_backfill_trial', NULL, 'trial',
       JSON_OBJECT('source', 'faz3_backfill'), NULL, NOW()
FROM `business_subscriptions` s
WHERE s.notes = 'Faz 3 geçiş backfill denemesi'
  AND NOT EXISTS (
    SELECT 1 FROM `business_subscription_audit` a
    WHERE a.subscription_id = s.id AND a.action = 'transition_backfill_trial'
  );
