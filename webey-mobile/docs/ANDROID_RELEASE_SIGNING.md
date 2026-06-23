# Android Release Signing — Webey Beauty

> Bu doküman Play Store yüklemesi için release imzalama kurulumunu anlatır.
> **Hiçbir gerçek değer (parola, alias, keystore) bu dosyaya yazılmaz.** Tüm
> değerler placeholder'dır. Gerçek `key.properties` ve `*.jks` dosyaları
> `.gitignore` ile dışlanmıştır ve asla commit edilmez.

## 0. Mevcut durum

`android/app/build.gradle.kts` şu davranışı uygular:

- `android/key.properties` **varsa** → `release` signing config oluşturulur ve
  release build bununla imzalanır.
- `android/key.properties` **yoksa** → release build **debug keystore**'a düşer.

> ⚠️ Debug keystore ile imzalanmış APK/AAB **Play Console tarafından reddedilir**.
> Cihazda test için yeterlidir, mağaza yüklemesi için **gerçek keystore zorunludur**.

İki flavor tek keystore ile imzalanabilir (önerilen):

| Flavor | applicationId |
|--------|---------------|
| customer | `tr.com.webey.beauty` |
| business | `tr.com.webey.business` |

## 1. Keystore üretimi (bir kez)

```bash
keytool -genkey -v \
  -keystore ~/webey-release.jks \
  -keyalias webey \
  -keyalg RSA -keysize 2048 -validity 10000
```

- Komut seni parola ve sertifika bilgileri için soracaktır.
- Üretilen `.jks` dosyasını **proje dışında, güvenli bir yerde** sakla
  (örn. parola yöneticisi / şifreli yedek). Repo içine koyma.

## 2. `android/key.properties` örnek şablonu

`android/key.properties` dosyasını **elle** oluştur (commit edilmez). Aşağıdaki
değerler PLACEHOLDER'dır — kendi gerçek değerlerinle değiştir:

```properties
storeFile=/ABSOLUTE/PATH/TO/webey-release.jks
storePassword=<STORE_PASSWORD>
keyAlias=webey
keyPassword=<KEY_PASSWORD>
```

- `storeFile` mutlak yol veya `android/` klasörüne göreli yol olabilir
  (gradle `rootProject.file` ile `android/` baz alır).
- Bu dosyayı **asla** versiyon kontrolüne ekleme.

## 3. `.gitignore` doğrulaması

Aşağıdaki kalıplar `webey-mobile/.gitignore` içinde mevcut olmalı (zaten var):

```gitignore
/android/key.properties
/android/app/*.jks
/android/app/*.keystore
*.jks
*.keystore
```

Kontrol:

```bash
git check-ignore android/key.properties   # çıktı vermeli (ignore ediliyor)
git check-ignore webey-release.jks        # çıktı vermeli
```

## 4. Release AAB build komutları

Play Store için **AAB** (Android App Bundle) tercih edilir.

```bash
# Customer
flutter build appbundle --flavor customer -t lib/main_customer.dart --release

# Business
flutter build appbundle --flavor business -t lib/main_business.dart --release
```

Çıktılar:

```
build/app/outputs/bundle/customerRelease/app-customer-release.aab
build/app/outputs/bundle/businessRelease/app-business-release.aab
```

APK gerekiyorsa (örn. cihaza doğrudan kurulum):

```bash
flutter build apk --flavor customer -t lib/main_customer.dart --release
flutter build apk --flavor business -t lib/main_business.dart --release
```

## 5. Play Console upload öncesi checklist

- [ ] `android/key.properties` mevcut ve gerçek keystore'a işaret ediyor.
- [ ] `keytool` ile üretilen `.jks` güvenli yerde yedeklendi.
- [ ] `flutter build appbundle --flavor customer --release` debug değil **release**
      keystore ile imzalandı (build log'unda debug fallback uyarısı yok).
- [ ] `flutter build appbundle --flavor business --release` aynı şekilde.
- [ ] `versionCode` her yüklemede artırıldı (pubspec `version: x.y.z+BUILD`).
- [ ] `google-services.json` her iki package (`beauty`, `business`) için client içeriyor.
- [ ] İki ayrı Play Console uygulaması: biri `tr.com.webey.beauty`, biri
      `tr.com.webey.business`.
- [ ] Gizlilik politikası + veri güvenliği formu (konum, bildirim, foto izinleri).
- [ ] `flutter analyze --no-fatal-infos` → temiz; `flutter test` → geçiyor.
- [ ] Release build gerçek cihazda smoke edildi (login, rezervasyon, kapora/iyzico, push).

## 6. ⚠️ Keystore kaybı uyarısı

Bir uygulamayı Play Store'a yükledikten sonra **aynı keystore ile imzalamaya devam
etmek zorundasın**. Keystore'u (veya parolasını) kaybedersen:

- Aynı uygulamaya **güncelleme yayınlayamazsın**.
- Tek kurtuluş yolu Google Play App Signing'e kayıtlıysan Google üzerinden upload
  key sıfırlama talebidir; aksi halde yeni applicationId ile sıfırdan uygulama
  yayınlaman gerekir (mevcut kullanıcılar otomatik güncelleme alamaz).

**Öneri:** İlk yüklemede **Google Play App Signing**'i etkinleştir; böylece app
signing key'i Google saklar, sen yalnızca upload key'i yönetirsin. Yine de upload
key'i ve keystore'u güvenli yedekle.
