-- ════════════════════════════════════════════════════════════════════════════
-- 2026_06_13b_update_boost_packages_pricing.sql
-- Boost paketlerini yeni ticari modele güncelle (Faz 1).
--
--   Günlük Boost  : 250 TL  / 1 gün
--   Haftalık Boost: 1.000 TL / 7 gün
--   Aylık Boost   : 3.000 TL / 30 gün
--
-- YAKLAŞIM:
--  * boost_packages tablosunda `code`/`slug` kolonu YOK → idempotent upsert
--    `name` üzerinden yapılır (INSERT ... WHERE NOT EXISTS). Şema DEĞİŞMEZ.
--  * Eski paketler (Başlangıç / Öne Çıkan / Premium Boost) SİLİNMEZ; yalnızca
--    is_active=0 yapılır. Böylece geçmiş business_boost_requests /
--    business_boost_subscriptions kayıtlarının referans bütünlüğü korunur,
--    ama satın alınabilir listede (is_active=1) görünmezler.
--  * İki kez çalıştırıldığında hata vermez, kayıt ikizlenmez (idempotent).
--  * priority_weight Faz 3 sıralaması içindir; şimdilik yalnızca saklanır.
--  * Charset: utf8mb4 (Türkçe karakter korunur).
--
-- NOT: Canlıya UYGULANMADAN önce preflight + backup (bkz. deploy planı).
-- ════════════════════════════════════════════════════════════════════════════

-- ── Yeni paketler (name üzerinden idempotent INSERT) ─────────────────────────
INSERT INTO `boost_packages`
  (`name`, `description`, `price`, `duration_days`, `priority_weight`, `features`, `is_active`, `sort_order`)
SELECT 'Günlük Boost',
       'Salonunu 1 gün boyunca aramalarda öne çıkar.',
       250.00, 1, 3,
       'Aramada üst sıra;1 gün boyunca öne çıkma;Hızlı görünürlük artışı',
       1, 1
WHERE NOT EXISTS (SELECT 1 FROM `boost_packages` WHERE `name` = 'Günlük Boost');

INSERT INTO `boost_packages`
  (`name`, `description`, `price`, `duration_days`, `priority_weight`, `features`, `is_active`, `sort_order`)
SELECT 'Haftalık Boost',
       'Bir hafta boyunca kategori ve bölge listelerinde belirgin ol.',
       1000.00, 7, 6,
       'Kategori listesinde öne çıkma;7 gün görünürlük;Öncelikli sıralama',
       1, 2
WHERE NOT EXISTS (SELECT 1 FROM `boost_packages` WHERE `name` = 'Haftalık Boost');

INSERT INTO `boost_packages`
  (`name`, `description`, `price`, `duration_days`, `priority_weight`, `features`, `is_active`, `sort_order`)
SELECT 'Aylık Boost',
       'Bir ay boyunca en yüksek görünürlük ve öncelikli sıralama.',
       3000.00, 30, 10,
       'Ana sayfada öne çıkma;En yüksek sıralama önceliği;30 gün maksimum görünürlük',
       1, 3
WHERE NOT EXISTS (SELECT 1 FROM `boost_packages` WHERE `name` = 'Aylık Boost');

-- ── Yeni 3 paket DIŞINDAKİ tüm paketleri pasifleştir (SİLME yok) ─────────────
-- NOT: Eski paket adları farklı/eski encoding ile saklanmış olabilir
-- (ör. 'Başlangıç' → 'Ba??lang????'). Bu yüzden eski adlarla EŞLEŞME yerine
-- "yeni 3 paket DIŞINDAKİ her şeyi pasifleştir" mantığı kullanılır; yeni adlar
-- bu dosyada doğru utf8mb4 ile yazıldığından güvenle eşleşir. Satırlar silinmez,
-- geçmiş kayıtların referans bütünlüğü korunur.
UPDATE `boost_packages`
   SET `is_active` = 0
 WHERE `name` NOT IN ('Günlük Boost', 'Haftalık Boost', 'Aylık Boost');
