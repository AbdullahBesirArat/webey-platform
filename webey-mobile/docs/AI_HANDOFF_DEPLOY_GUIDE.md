# AI Handoff & Deploy Rehberi — Webey Beauty

> Bu dosya yeni bir AI oturumu başlarken ilk okunacak rehberdir.
> Okuduktan sonra `git status` ve `git diff` ile mevcut durumu doğrula.

---

## 1. Proje Özeti

| Bileşen | Konum |
|---------|-------|
| PHP/MySQL backend + web sitesi | `webey-site/` |
| Flutter customer + business app | `webey-mobile/` |
| Mobile API path | `/api/mobile` |
| Canlı domain | `https://webey.com.tr` |
| Canlı web root | `/var/www/webey` |
| SSH alias | `webey` (bkz. `~/.ssh/config`) |

**Dual Flutter entry point:**
- `main_customer.dart` — müşteri akışı
- `main_business.dart` — işletme akışı

---

## 2. Genel AI Çalışma Kuralları

### Yapma
- Büyük refactor yapma — yalnızca görevin gerektirdiği değişikliği yap
- `build/`, `.dart_tool/`, `android/.gradle/`, `ios/Pods/`, `node_modules/`, `vendor/` içine dokunma
- `.env`, secret, API key, token, şifre, hash değeri dosyaya yazma
- Canlı DB'ye migration uygulamadan önce read-only preflight yap
- Canlı şemanın local şemadan farklı olabileceğini varsay (bkz. Bölüm 5)
- Force push yapma
- Rollback planı olmadan write smoke test yapma

### Yap
- Her deploy öncesi sunucuda timestamp'li backup al
- `php -l` → deploy → canlı `php -l` sırasını uygula
- `flutter analyze --no-fatal-infos` ile sıfır hata doğrula
- Smoke test sonrası test verisini rollback et
- Küçük fazlarla ilerle; tek seferde 1–3 dosya deploy et
- `git commit` öncesi secret taraması yap: `grep -rEi "password|token|secret|api_key" -- <değişen-dosyalar>`

---

## 3. Faz 8 — Canlıya Deploy Edilen Endpointler

**Commit:** `00eb647`
**Mesaj:** `feat(mobile-api): complete phase 8 customer and business endpoints`

> Not: Rebase sonrası hash `dd35ab8` → `00eb647` oldu. Remote main push başarılı.
> Migration dosyaları commit'e alınmadı.

### Customer Endpointleri
| Dosya | Durum |
|-------|-------|
| `/api/mobile/customer/profile-save.php` | Canlıda (Faz 10B hotfix ile güncellendi) |
| `/api/mobile/customer/favorites.php` | Canlıda |
| `/api/mobile/customer/favorite-toggle.php` | Canlıda |
| `/api/mobile/customer/favorite-check.php` | Canlıda |
| `/api/mobile/customer/notifications/read.php` | Canlıda |

### Business Endpointleri
| Dosya | Durum |
|-------|-------|
| `/api/mobile/business/profile.php` | Canlıda |
| `/api/mobile/business/profile-save.php` | Canlıda |
| `/api/mobile/business/hours.php` | Canlıda |
| `/api/mobile/business/hours-save.php` | Canlıda |
| `/api/mobile/business/deposit.php` | Canlıda |
| `/api/mobile/business/deposit-save.php` | Canlıda |

### Faz 8 Smoke Test Sonuçları
- Invalid token → 401 döndü ✓
- `health/` ve `categories/` → 200 döndü ✓
- Migration canlıya uygulanmadı ✓

---

## 4. Canlı DB Şema Farkları — KRİTİK

Bu farklar keşfedildi ve ilgili PHP dosyaları buna göre düzeltildi. Yeni bir AI bu farkları göz ardı etmemeli.

### `customer_favorites` tablosu

| | Yerel taslak | Canlı gerçek |
|-|---|---|
| Kolon adı | `user_id` | `customer_user_id` |

**Etkilenen dosyalar:** `favorites.php`, `favorite-toggle.php`, `favorite-check.php`
→ Hepsi `customer_user_id` kullanacak şekilde düzeltildi.

### Kapora (Deposit) sistemi

| | Yerel taslak | Canlı gerçek |
|-|---|---|
| Kolon yeri | `businesses.deposit_*` | Ayrı `deposit_policies` tablosu |

**`deposit_policies` tablo şeması:**
```
id int, business_id int UNIQUE,
rate_pct tinyint DEFAULT 25,
per_service tinyint(1) DEFAULT 0,
cancel_policy varchar(20) DEFAULT 'esnek',
updated_at datetime ON UPDATE CURRENT_TIMESTAMP
```

**Etkilenen dosyalar:** `business/deposit.php`, `business/deposit-save.php`
→ Her ikisi de `deposit_policies` tablosunu kullanacak şekilde yeniden yazıldı.

---

## 5. Uygulanmayan Migrationlar — DOKUNMA

Aşağıdaki iki migration canlıda **uygulanmadı** ve şu an uygulanmamalı:

```
database/migrations/2026_05_25_create_customer_favorites.sql
database/migrations/2026_05_25_add_deposit_policy_to_businesses.sql
```

**Sebep:**
- `customer_favorites` canlıda zaten mevcut ve `customer_user_id` kullanıyor.
- Kapora sistemi canlıda `deposit_policies` tablosunu kullanıyor.

Bu migrationları canlıya uygularsan şemayı bozarsın.

---

## 6. Faz 9 — Gerçek Token Smoke Testleri

| Endpoint | Sonuç |
|----------|-------|
| `GET /auth/me.php` | 200 ✓ |
| `GET /customer/profile.php` | 200 ✓ |
| `GET /customer/favorites.php` | 200, gerçek favori döndü ✓ |
| `GET /customer/favorite-check.php` | 200 ✓ |
| `POST /customer/notifications/read.php` | 200 ✓ |
| Business token testi | Atlandı (test hesabı yoktu) |

---

## 7. Faz 10A — Customer Write Smoke Testleri

- `profile-save` write + rollback: başarılı ✓
- `favorite-toggle` false/true + rollback: başarılı ✓
- 500 / SQL error: yok ✓

**Bug tespit edildi:** `profile-save.php`'de boş body `{}` gönderilince profil alanları `NULL` oluyordu.
Canlı veri hemen restore edildi.

---

## 8. Faz 10B — profile-save.php Hotfix

**Sorun:** `$in['field'] ?? ''` + `$val !== '' ? $val : null` kombinasyonu
body'de olmayan key'leri `NULL` olarak yazıyordu.

**Fix:** `array_key_exists` ile sadece request body'de gerçekten gelen alanlar işleniyor.

```php
// Düzeltilmiş mantık özeti:
$fields = [];
foreach ($colMaxLen as $col => $max) {
    if (!array_key_exists($col, $in)) continue;  // body'de yoksa atla
    $val = mb_substr(trim((string)($in[$col] ?? '')), 0, $max);
    $fields[$col] = $val !== '' ? $val : null;
}
// $fields === [] ise hiç DB write yapılmaz
```

**Canlı test sonuçları:**
- NEG 3 — boş body `{}` → `ok:true`, profil alanları değişmedi ✓
- Partial update — sadece `neighborhood` gönderildi → sadece `neighborhood` değişti ✓
- Diğer alanlar (`first_name`, `last_name`, `phone`, `city`, `district`) değişmedi ✓
- Rollback başarılı ✓
- Backup: `/var/www/webey/_backups/faz10b_20260525_221606/profile-save.php`

---

## 9. Flutter Test Altyapisi Son Durum - Faz 13B-13G

**Mobile repo remote:** `https://github.com/AbdullahBesirArat/webey-mobile-app.git`

### Son onemli test commitleri

| Commit | Mesaj |
|--------|-------|
| `29b5a4d` | `test: block live network calls in widget tests` |
| `75be800` | `test: make auth flow tests use offline fake auth` |
| `d024ae6` | `test: update business UI tests for current labels` |
| `ae72b0f` | `test: update widget tests for current UI labels` |
| `bf752d8` | `test: inject fake customer repositories in widget tests` |
| `cc68a36` | `test: inject fake business repository in widget tests` |

### Test sonucu

| Komut / dosya | Durum |
|---------------|-------|
| `flutter analyze` | `No issues found` |
| `flutter test` | `+78 All tests passed` |
| `test/auth_flow_test.dart` | Geciyor |
| `test/webey_ui_test.dart` | Geciyor |
| `test/widget_test.dart` | Geciyor |

Default `flutter test` canli API'ye cikmamalidir. No-network guard aktiftir.

### No-network guard

| Dosya | Gorev |
|-------|-------|
| `test/flutter_test_config.dart` | Test ortaminda guard'i baslatir |
| `test/helpers/no_network_http_overrides.dart` | Widget testlerinde gercek network isteklerini engeller |
| `lib/shared/services/api_client.dart` | Test guard flag'i vardir; runtime default kapalidir |

Kurallar:
- Guard sadece test helper tarafindan aktif edilir.
- Production runtime network davranisi degismedi.
- Test kosusunda `https://webey.com.tr` cagrisi gorulmemelidir.

### Fake auth

- `AuthFlow` optional `authService` alir.
- Default davranis `WebeyAuthService.instance` olarak korunur.
- `test/auth_flow_test.dart` deterministic fake auth service kullanir.
- Testlerde gercek credential, gercek API veya gercek oturum degeri kullanilmaz.

### Fake customer repository injection

| Ekran | Test injection |
|-------|----------------|
| `CustomerAppointmentsScreen` | Optional `CustomerAppointmentRepository repository` |
| `CustomerNotificationsScreen` | Optional `CustomerNotificationRepository repository` |
| `CustomerFavoritesScreen` | Optional `CustomerFavoriteRepository repository` |

Default production davranisi singleton repository'lerle korunur:
- `CustomerAppointmentRepository.instance`
- `CustomerNotificationRepository.instance`
- `CustomerFavoriteRepository.instance`

`test/widget_test.dart`, customer appointment / notification / favorites testlerini fake customer repositories ile besler.

### Fake business repository injection

| Ekran | Test injection |
|-------|----------------|
| `BusinessDashboardScreen` | Optional `BusinessRepository repository` |
| `BusinessCalendarScreen` | Optional `BusinessRepository repository` |

Default production davranisi `BusinessRepository.instance` olarak korunur.

`test/widget_test.dart`, dashboard ve calendar testlerini fake business repository ile besler.

### Yeni test yazarken kurallar

- Default test suite'e canli API cagrisi ekleme.
- Fake HTTP fixture veya base URL override kullanma.
- Widget testlerini fake repository veya constructor injection ile veriyle besle.
- Production default davranisi singleton repository ile korunmali.
- `pumpAndSettle` timeout riski varsa bounded pump tercih et.
- Text matcher'lari mumkun oldugunca scoped/stabil tut.
- Integration/live smoke testleri default `flutter test` disinda tut.

---

## 10. Standart Deploy Prosedürü

```
1. Preflight
   ssh webey "php -v && mysql -u root webey_prod -e 'SELECT COUNT(*) FROM users;'"

2. Backup
   ssh webey "mkdir -p /var/www/webey/_backups/fazXX_$(date +%Y%m%d_%H%M%S) && \
              cp /var/www/webey/api/mobile/<dosya>.php <backup_dir>/"

3. Local syntax
   php -l webey-site/api/mobile/<dosya>.php

4. Deploy
   scp webey-site/api/mobile/<dosya>.php webey:/var/www/webey/api/mobile/<dosya>.php

5. İzin/sahiplik
   ssh webey "chown www-data:www-data <remote_path> && chmod 644 <remote_path>"

6. Canlı syntax
   ssh webey "php -l <remote_path>"
   # Fail → backup'tan geri al:
   # ssh webey "cp <backup_dir>/<dosya>.php <remote_path>"

7. Public smoke (token gerektirmez)
   curl -s https://webey.com.tr/api/mobile/health/ | grep ok

8. Invalid token → 401
   curl -s -H "Authorization: Bearer GECERSIZ" <endpoint>

9. Gerçek token read-only smoke
   # Geçici session: sunucuda php script ile oluştur, test sonrası sil
   # (parola değiştirme gerekmez)

10. Write test (rollback planıyla)
    - Before snapshot al
    - Değişikliği yap
    - After snapshot al ve karşılaştır
    - Rollback yap
    - Rollback doğrula
```

---

## 11. Git Prosedürü

```bash
# 1. Durum kontrolü
git -C webey-site status
git -C webey-site diff --stat

# 2. Secret taraması (commit öncesi zorunlu)
git -C webey-site diff -- <değişen-dosyalar> | grep -Ei "password|token|secret|api_key|hash" || echo "CLEAN"

# 3. Sadece ilgili dosyaları stage et
git -C webey-site add api/mobile/customer/profile-save.php
# Migration dosyalarını stage etme

# 4. Commit
git -C webey-site commit -m "feat(mobile-api): <açıklama>"

# 5. Push öncesi remote kontrol
git -C webey-site log origin/main..HEAD --oneline   # push edilecekler
git -C webey-site log HEAD..origin/main --oneline   # remote'da fazladan var mı?

# Remote ilerideyse:
git -C webey-site pull --rebase origin main

# 6. Push
git -C webey-site push origin main
# Force push YAPMA
```

---

## 12. Sonraki Mantikli Adimlar

1. Mevcut test harness uzerine yeni feature testleri ekle
2. Customer repository hata / empty-state ayrimini iyilestir
3. Business deposit preview icindeki hardcoded `1200 TL` baz fiyatini ileride gercek service price ile bagla
4. Mock / dead code cleanup yap
5. Reviews sistemini tasarla ve test et
6. Push notifications / FCM entegrasyonunu planla

---

## 13. Kesinlikle Yapılmaması Gerekenler

| Yasak | Sebep |
|-------|-------|
| `2026_05_25_create_customer_favorites.sql` canlıya uygulanmamalı | Tablo canlıda farklı şemada zaten var |
| `2026_05_25_add_deposit_policy_to_businesses.sql` canlıya uygulanmamalı | Canlı kapora sistemi `deposit_policies` tablosunu kullanıyor |
| `customer_favorites.user_id` kullanılmamalı | Canlıda kolon adı `customer_user_id` |
| `businesses.deposit_*` kolonları kullanılmamalı | Canlıda bu kolonlar kapora sistemi değil |
| Force push yapılmamalı | Geçmişi bozar |
| Secret/token/password/hash commit'lenmemeli | Güvenlik riski |
| Test kullanıcı şifresi değiştirilip restore edilmeden çıkılmamalı | Veri bütünlüğü |
| Rollback planı olmadan write smoke test yapılmamalı | Canlı veriyi bozabilir |

---

## 14. Mevcut Durum Özeti

| Alan | Durum |
|------|-------|
| Faz 8 — 11 endpoint | Canlıda ✓ |
| Customer read smoke test | Geçti ✓ |
| Customer write smoke test | Geçti ✓ |
| profile-save boş body bug fix | Canlıda ✓ |
| Business read/write smoke test | Geçti ✓ |
| Flutter profile payload fix | Commit/push yapıldı ✓ |
| Flutter test no-network guard | Aktif ✓ |
| auth_flow_test.dart | Geçiyor ✓ |
| webey_ui_test.dart | Geçiyor ✓ |
| widget_test.dart | Geçiyor ✓ |
| Full `flutter test` | `+78 All tests passed` ✓ |

**Yeni bir AI oturumu başlıyorsa:**
1. Bu dosyayı oku
2. `git -C webey-site status` ve `git -C webey-site diff --stat` çalıştır
3. `git -C webey-mobile status`, `git -C webey-mobile log -2 --oneline`, `git -C webey-mobile remote -v` çalıştır
4. `flutter analyze` ve `flutter test` çalıştır
5. Sonra göreve devam et
