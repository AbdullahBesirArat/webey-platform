# Webey — Geliştirmeler (Mart 2026)

## 🔴 Güvenlik

### 1. `login_attempts` Tablosu (Migration 002)
- `api/user/login.php`'e brute-force koruması eklendi (admin/login.php'de zaten vardı)
- Her başarısız denemede IP kaydediliyor, 5 dakikada 10 başarısız denemede 429 dönüyor

### 2. CSRF Koruması (`api/wb_response.php`)
Yeni fonksiyonlar:
```php
wb_csrf_token()    // Token üret / döndür
wb_csrf_verify()   // POST/PUT/DELETE'de çağır — geçersizse 403
```
Frontend: `X-CSRF-Token` header ile gönderin.

### 3. Input Validator (`api/wb_response.php`)
```php
wb_validate($data, [
    'email'    => ['required', 'email', 'max:191'],
    'password' => ['required', 'min:8'],
    'phone'    => ['required', 'regex:/^5\d{9}$/'],
]);
```
Desteklenen kurallar: `required`, `email`, `numeric`, `min:N`, `max:N`, `regex:/pattern/`, `in:a,b,c`

---

## 🟠 Yeni Özellikler

### 4. Randevu ICS Export (`api/appointments/export-ics.php`)
- `GET /api/appointments/export-ics.php?id=<id>` (oturumlu)
- `GET /api/appointments/export-ics.php?token=<md5>` (e-postadaki link)
- Google Calendar, Apple Calendar, Outlook uyumlu
- 1 saat + 24 saat alarm içeriyor

### 5. Otomatik Hatırlatma Cron (`api/billing/cron_reminders.php`)
Crontab kurulumu:
```
*/15 * * * *  php /var/www/html/api/billing/cron_reminders.php >> /var/log/webey_reminders.log 2>&1
```
- Her randevuya 24 saat ve 1 saat önce email gönderir
- Çift gönderimi önlemek için `reminder_24h_sent` / `reminder_1h_sent` flag'leri kullanılır

### 6. Web Push Subscription (`api/push/subscribe.php`)
- `POST /api/push/subscribe.php { action, endpoint, p256dh, auth }`
- `push_subscriptions` tablosuna kaydedilir (Migration 002)
- Service Worker push event handler hazır

---

## 🟡 API Geliştirmeleri

### 7. `api/public/salons.php` — Pagination + Filtreler
Yeni parametreler:
| Param | Tip | Açıklama |
|-------|-----|----------|
| `page` | int | Sayfa (varsayılan: 1) |
| `limit` | int | Sayfa başı kayıt (varsayılan: 18, max: 100) |
| `q` | string | Ad/açıklama araması |
| `sort` | string | `newest`, `rating`, `price_asc`, `price_desc`, `name` |
| `min_rating` | float | Minimum puan filtresi |
| `min_price` | int | Minimum fiyat (TL) |
| `max_price` | int | Maximum fiyat (TL) |
| `open_now` | bool | Şu an açık olanlar |

Response'a `meta` eklendi: `{ total, page, limit, pages, has_more }`

### 8. `api/admin/analytics.php`
Mevcut analytics API'ye ek olarak `occupancy_rate` (doluluk oranı) eklenmiştir.

---

## 🟢 Kod Kalitesi

### 9. `js/wb-api-shim.js` — Merkezi API Katmanı
`calendar.js`, `settings.js`, `staff.js`, `profile.js`'nin yerel `apiGet`/`apiPost` fonksiyonlarının tek merkezi versiyonu.

**Özellikler:**
- 12sn timeout + 1x retry (5xx'lerde)
- 401/403 → login sayfasına otomatik yönlendirme
- Çevrimdışı kontrolü (`navigator.onLine`)
- CSRF token header otomatik ekleme
- `window.apiGet` / `window.apiPost` olarak global erişilebilir

HTML'e ekle (diğer script'lerden önce):
```html
<script src="/js/wb-api-shim.js"></script>
```

### 10. `service-worker.js` — Geliştirilmiş Cache Stratejisi
- `CACHE_VERSION = 'v2'` (yeni; eski cache'ler silinir)
- 3 cache bucket: `webey-static-v2`, `webey-pages-v2`, `webey-images-v2`
- Resimler için 3 günlük TTL
- Çevrimdışı HTML sayfalar için `/offline.html` fallback
- **Web Push bildirim altyapısı** (`push` ve `notificationclick` event'leri)

### 11. `offline.html` — Çevrimdışı Sayfası
Kullanıcıya internet kesildiğinde gösterilen güzel, responsive sayfa.
Bağlantı geri geldiğinde otomatik geri yönlendirir.

---

## 🗄️ Veritabanı (`database/webey_migration_002.sql`)

```bash
# Önce yedek al
mysqldump -u root -p webey_local > backup_$(date +%Y%m%d).sql

# Migration uygula
mysql -u root -p webey_local < database/webey_migration_002.sql
```

Yeni tablolar/kolonlar:
- `login_attempts` — Brute-force takibi
- `csrf_tokens` — (isteğe bağlı DB tabanlı CSRF)
- `appointment_reminders` — Hatırlatma log'u
- `push_subscriptions` — Web Push abonelikler
- `businesses.latitude`, `.longitude`, `.slug`, `.min_price`, `.max_price`
- `appointments.reminder_24h_sent`, `.reminder_1h_sent`, `.customer_user_id`
- `reviews.idx_business_visible` index
- `favorites.idx_user_created` index
- MySQL Event Scheduler (eski login_attempts temizleme)

---

## Sonraki Adımlar (Öneri)

1. **SMS OTP** — Müşteri telefon doğrulaması için Twilio / Netgsm entegrasyonu
2. **Gerçek ödeme gateway** — İyzico veya PayTR ile `billing/subscribe.php` tamamlanmalı
3. **`calendar.js` + `settings.js` tam migration** — `apiGet`/`apiPost` yerine doğrudan `wb-api-shim.js` importu
4. **Çoklu hizmet randevusu** — Tek randevuya birden fazla hizmet
5. **SEO: business slug** — `/{slug}` yerine `kuafor.html?id=X` yerine güzel URL'ler
6. **Harita entegrasyonu** — `latitude`/`longitude` kolonları eklendi, Leaflet.js ile kuafor.html'e eklenebilir