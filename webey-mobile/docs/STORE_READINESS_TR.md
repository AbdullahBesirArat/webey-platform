# Webey — Mağaza Yükleme Hazırlık Dokümanı (Google Play + App Store)

> Hazırlık tarihi: 2026-06-15 · Salt-analiz + güvenli düzeltme turu. Store submission YAPILMADI, canlı DB'ye yazılmadı, secret gösterilmedi.
> Bu doküman; Data Safety / App Privacy formları, store metinleri, izin gerekçeleri ve iOS yol haritası içindir. Kopyala-yapıştır kullanılabilir.

İki ayrı uygulama (ayrı Play kaydı + ayrı App Store kaydı):
- **Customer** — `tr.com.webey.beauty` — "Webey Beauty"
- **Business** — `tr.com.webey.business` — "Webey İşletme"

Versiyon: `1.0.0` (versionCode 1). Backend: `https://webey.com.tr/api/mobile`. Ödeme SDK'sı yok; kapora doğrudan salon IBAN'ına havale (Webey tahsil etmez). Analytics/Crashlytics/Reklam/Tracking SDK yok. Üçüncü taraf (Google/Apple) login yok → e-posta/telefon + şifre.

---

## 1) GOOGLE PLAY — DATA SAFETY FORMU

Genel: Tüm veri transit'te şifreli (HTTPS/TLS). Hesap silme uygulama içinden ve `https://webey.com.tr/hesap-silme` üzerinden talep edilebilir. Veri satışı YOK. Reklam YOK.

| Veri türü | Toplanıyor | Paylaşılıyor | Amaç | Zorunlu/Opsiyonel |
|---|---|---|---|---|
| Ad-soyad | Evet | Salon (randevu için) | Hesap, randevu | Zorunlu |
| E-posta | Evet | Hayır | Hesap/kimlik doğrulama | Zorunlu |
| Telefon | Evet | Salon (randevu için) | Hesap, iletişim | Zorunlu |
| Konum (yaklaşık + kesin) | Evet | Hayır | Yakın salon önerisi, harita | Opsiyonel |
| Randevu/işlem bilgisi | Evet | Salon | Uygulama işlevi | Zorunlu |
| Fotoğraf (galeri/profil) | Evet | Herkese açık (salon galerisi) | İşletme galerisi, avatar | Opsiyonel |
| Uygulama içi mesaj/yorum | Evet | Herkese açık | Değerlendirme sistemi | Opsiyonel |
| Push token (cihaz) | Evet | Firebase (Google) | Bildirim | Opsiyonel |
| IBAN (yalnız işletme) | Evet | Müşteriye gösterilir | Kapora havale talimatı | İşletme için zorunlu |
| Uygulama etkileşimi/log | Evet | Hayır | Güvenlik, hata önleme | Zorunlu |

Form cevap özeti:
- "Does your app collect or share any of the required user data types?" → **Yes**
- "Is all of the user data collected by your app encrypted in transit?" → **Yes**
- "Do you provide a way for users to request that their data be deleted?" → **Yes** (`https://webey.com.tr/hesap-silme`)
- Data for tracking across apps/companies → **No**
- Data sold to third parties → **No**
- Reklam kimliği (AAID) kullanımı → **No** (reklam SDK'sı yok)

---

## 2) APPLE — APP PRIVACY (NUTRITION LABEL)

"Data Used to Track You": **YOK** (tracking SDK / ATT yok).
"Data Linked to You" (kimliğe bağlı, yalnızca uygulama işlevi için):
- Contact Info: Ad, E-posta, Telefon — App Functionality
- Location: Precise + Coarse — App Functionality (opsiyonel)
- User Content: Photos, yorumlar — App Functionality
- Identifiers: Kullanıcı/cihaz (push token) — App Functionality
- Financial Info (yalnız işletme): IBAN — App Functionality
- Usage/Diagnostics: yok (analytics SDK yok)

"Data Not Linked to You": yok. **Tracking: No.**

---

## 3) POLİTİKA DEĞERLENDİRMELERİ

- **IAP gerekli mi? HAYIR.** Randevu/kapora gerçek dünya hizmetidir; kapora doğrudan salon IBAN'ına havale edilir, Webey tahsil etmez (Apple 3.1.3 / Google "physical goods & services" istisnası). Uygulamada ödeme SDK'sı yok.
  - İşletme abonelik/boost: şu an uygulama içi kart tahsilatı YOK (admin/mock). İleride gerçek tahsilat eklenirse iOS'ta harici web checkout ile yapılmalı.
- **Sign in with Apple gerekli mi? HAYIR.** Uygulamada üçüncü taraf/sosyal login yok (yalnız e-posta/telefon + şifre). (Doğrulandı: `google_sign_in`/`sign_in_with_apple` paketi yok.)
- **App Tracking Transparency gerekli mi? HAYIR.** Reklam/analytics/tracking SDK ve IDFA kullanımı yok.
- **UGC (fotoğraf):** İşletmeler salon fotoğrafı yükler. Apple 1.2 / Google UGC için **şikayet/raporlama + içerik politikası** önerilir (orta öncelikli; Apple inceleme sırasında sorabilir).

İzin gerekçeleri:
- **Konum (FINE/COARSE / NSLocationWhenInUse):** Yakındaki salonları listelemek ve haritada göstermek; işletme tarafında salon konumunu seçmek. Kullanıcı reddedebilir; uygulama çalışmaya devam eder.
- **Kamera (NSCamera):** Salon/galeri ve profil fotoğrafı çekmek (image_picker).
- **Fotoğraf (NSPhotoLibrary):** Galeri/profil için cihazdan görsel seçmek.
- **Bildirim (POST_NOTIFICATIONS / APNs):** Randevu onayı, hatırlatma, kapora bildirimleri (FCM).

---

## 4) STORE METİNLERİ — CUSTOMER (tr.com.webey.beauty)

- **App adı (Play başlık ≤30 / Apple ≤30):** `Webey Beauty` _(alternatif: `Webey – Güzellik Randevu`)_
- **Apple subtitle (≤30):** `Kuaför & güzellik randevusu`
- **Kısa açıklama (Play ≤80):** `Yakındaki kuaför ve güzellik salonlarını keşfet, anında randevu al.`
- **Tam açıklama (≤4000):**
  > Webey ile güzellik ve bakım randevunu dakikalar içinde al. Yakınındaki kuaför, berber, güzellik ve bakım salonlarını keşfet; hizmetleri, fiyatları ve uygun saatleri gör; sana en yakın salonu haritada bul.
  >
  > • Keşfet ve ara: Kategoriye, konuma ve hizmete göre salon bul.
  > • Harita: Yakındaki salonları haritada gör.
  > • Randevu: Uygun saati seç, birkaç dokunuşla randevunu oluştur.
  > • Kapora ile garanti: Kaporalı salonlarda randevunu güvenle garantiye al. Kapora doğrudan salonun banka hesabına (IBAN) gönderilir; Webey ödeme tahsil etmez.
  > • Favoriler & profil: Sevdiğin salonları kaydet, geçmiş randevularını gör.
  > • Bildirimler: Randevu onayı ve hatırlatmalarını kaçırma.
  >
  > Webey, salon ile müşteri arasında güvenli bir randevu köprüsüdür. Hesabını dilediğin zaman uygulama içinden silebilirsin.
- **Kategori:** Play → Beauty (alt: Lifestyle) · Apple → Lifestyle
- **Keywords (Apple ≤100):** `kuaför,güzellik,salon,randevu,berber,saç,tırnak,bakım,spa,makyaj`
- **Contact email:** destek@webey.com.tr
- **Privacy policy URL:** https://webey.com.tr/gizlilik-politikasi  *(deploy sonrası)*
- **Account deletion URL:** https://webey.com.tr/hesap-silme  *(deploy sonrası)*
- **Support URL:** https://webey.com.tr/sss · **Website:** https://webey.com.tr
- **App access (demo hesap):** GEREKLİ — inceleyiciye bir müşteri test hesabı (telefon/e-posta + şifre). _(Gerçek değerleri siz girin.)_

## 5) STORE METİNLERİ — BUSINESS (tr.com.webey.business)

- **App adı:** `Webey İşletme` _(alternatif: `Webey İşletme – Salon Yönetimi`)_
- **Apple subtitle (≤30):** `Salonunu yönet`
- **Kısa açıklama (Play ≤80):** `Salonunu yönet: randevular, takvim, kapora, galeri, personel ve boost.`
- **Tam açıklama (≤4000):**
  > Webey İşletme, salonunu tek yerden yönetmeni sağlar. Randevularını takip et, takvimini düzenle, hizmet ve personel bilgilerini güncelle, salon galerini yönet.
  >
  > • Randevular & takvim: Gelen randevuları gör, onayla, düzenle.
  > • Kapora: Kaporanı IBAN ile al. Müşteri "gönderdim" der, sen "para geldi" ile onaylarsın. Webey ödeme tahsil etmez; kapora doğrudan senin banka hesabına gelir.
  > • Hizmet & personel: Hizmetlerini, fiyatlarını ve personelini yönet.
  > • Galeri & kapak: Salon fotoğraflarını yükle, kapak görselini seç.
  > • Webey Paketim & Boost: Aramada öne çık.
  > • Bildirimler: Yeni randevu ve kapora bildirimlerini anında al.
  >
  > Hesabını dilediğin zaman uygulama içinden silme talebi oluşturabilirsin.
- **Kategori:** Play → Business · Apple → Business
- **Keywords (Apple ≤100):** `kuaför,salon yönetimi,randevu,işletme,berber,takvim,personel,kapora`
- **Contact email:** destek@webey.com.tr
- **Privacy / Account deletion / Support / Website:** Customer ile aynı URL'ler.
- **App access (demo hesap):** GEREKLİ — inceleyiciye bir işletme test hesabı. _(Gerçek değerleri siz girin; not: "para geldi/onayla" gibi aksiyonlar canlı veriyi etkiler, inceleyiciye not düşün.)_

---

## 6) GÖRSEL / ASSET CHECKLIST (her uygulama için ayrı)

Google Play:
- [ ] Uygulama ikonu 512×512 (PNG, 32-bit)
- [ ] Feature graphic 1024×500
- [ ] Telefon ekran görüntüsü: en az 2 (önerilen 4–8), 1080×1920 veya benzeri
- [ ] (Opsiyonel) 7"/10" tablet görüntüleri
Apple App Store:
- [ ] iPhone 6.7" (1290×2796) — zorunlu, 3–10 adet
- [ ] iPhone 6.5" (1242×2688)
- [ ] (Opsiyonel) iPad 12.9"
- [ ] App icon 1024×1024 (zaten projede var)

Önerilen ekranlar: Customer → Keşfet, Harita, Salon detay, Randevu/kapora, Profil. Business → Dashboard, Randevular, Kapora, Galeri, Paketim/Boost.

---

## 7) İÇERİK DERECELENDİRME / HEDEF KİTLE

- Play IARC: şiddet/cinsellik/kumar yok → büyük olasılıkla **Everyone / 3+**. UGC (fotoğraf) olduğunu işaretle.
- Apple yaş: **4+**.
- Hedef kitle: 18+ (randevu/işletme); çocuklara yönelik değil.

---

## 8) TEST PLANI

Google Play (Android):
1. **Internal testing** — AAB yükle, ekip e-postaları ekle (anında, limitsiz). Hızlı doğrulama.
2. **Closed testing** — Kişisel/bireysel geliştirici hesabıysa: **en az 12 test kullanıcısı, 14 gün kesintisiz** opt-in zorunlu (production erişimi için). Organizasyon hesabıysa bu şart yok.
3. **Production** — Data Safety + içerik derecelendirme + gizlilik/hesap-silme URL'leri canlı olduktan sonra.

Apple (iOS): App Store Connect kaydı → TestFlight **internal** (≤100 tester, beta review yok) → gerekirse **external** (beta review). Sonra App Review.

---

## 9) iOS HAZIRLIK CHECKLIST & YOL HARİTASI

Mevcut durum (Windows'ta doğrulandı): iOS = **store-ready DEĞİL**, build alınamaz (Mac/Xcode veya CI gerekir).
Eksikler: Podfile yok · GoogleService-Info.plist yok · PrivacyInfo.xcprivacy yok · entitlements yok · tek `Runner` scheme (flavor yok) · bundle id `tr.com.webey.webeyMobile` (yanlış) · signing team yok.

Yol haritası (ayrı büyük faz):
1. Mac/Xcode veya CI (Codemagic / GitHub Actions macOS / Bitrise) kur.
2. Apple Developer Program; App ID'ler: `tr.com.webey.beauty`, `tr.com.webey.business`.
3. Xcode flavor (xcconfig veya scheme): customer / business; doğru bundle id + display name.
4. Firebase iOS app'leri oluştur; `GoogleService-Info.plist` (×2) ekle.
5. APNs key + Push Notifications capability + `UIBackgroundModes: remote-notification`.
6. `PrivacyInfo.xcprivacy` (required-reason API'ler: shared_preferences, flutter_secure_storage, image_picker).
7. `Info.plist`: gereksiz `NSLocationAlwaysAndWhenInUse` kaldır (yalnız when-in-use kullanılıyor).
8. `pod install`, archive, TestFlight internal.

---

## 10) AÇIK BLOCKER'LAR

- **BLK-02-DEPLOY (✅ ÇÖZÜLDÜ — 2026-06-15 canlıya alındı):** 4 legal clean URL artık canlıda 200 + doğru içerik:
  - `https://webey.com.tr/gizlilik-politikasi` ✅ · `/kvkk` ✅ · `/kullanim-sartlari` ✅ · `/hesap-silme` ✅ (SPA'ya düşmüyor).
  - Deploy: `gizlilik-politikasi.html` (+kapora callout), `kvkk.html`, `hesap-silme.html`, `.htaccess` (yalnız 4 rewrite eklendi). Backup: `/root/webey_legal_backup_20260615/`. Regression smoke PASS (SPA+API sağlam, 500 yok, error log temiz). API/PHP/DB'ye dokunulmadı.
- **iOS (Critical):** iOS yapılandırması sıfır; ayrı faz.
- **MISC (Medium):** Business app gerçek işletme hesabıyla cihaz smoke'u yapılmadı.

Deploy talimatı (onaylanırsa, yalnız static): webey-site içinden SADECE `gizlilik-politikasi.html`, `kvkk.html`, `hesap-silme.html`, `.htaccess` → `/var/www/webey` (SCP). PHP/API/DB'ye DOKUNMA. Deploy öncesi canlı `.htaccess` yedeği al. Deploy sonrası 4 clean URL'yi HTTP 200 + doğru içerik ile doğrula.
