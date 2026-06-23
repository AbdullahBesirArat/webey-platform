# Webey Beauty Admin Plan

Bu doküman gerçek admin panel geliştirilmeden önce ihtiyaçları netleştirmek için hazırlanmıştır.

## MVP Admin Modülleri

- Salon onaylama/reddetme
- Salon belge kontrolü
- İşletme abonelikleri
- Kapora ödemeleri
- İade talepleri
- Şikayetler ve destek talepleri
- Yorum moderasyonu
- Kampanya/öne çıkarma yönetimi
- Kullanıcı yönetimi
- Temel raporlama

## Salon Onay Akışı

1. İşletme kayıt formunu gönderir.
2. Admin eksik alanları ve risk bayraklarını görür.
3. Vergi, adres, hizmet ve görsel kontrolleri tamamlanır.
4. Salon onaylanır, reddedilir veya manuel incelemeye alınır.

## Ödeme ve İade Operasyonu

- Kapora ödeme kayıtları provider transaction id ile izlenmeli.
- İade talepleri appointment, cancellation policy ve provider durumuna göre incelenmeli.
- Admin aksiyonları audit log'a yazılmalı.

## Destek Talepleri

Support ticket alanları:
- kullanıcı adı
- rol
- konu
- mesaj
- öncelik
- durum
- oluşturulma tarihi

## Yetki Rollerinin Taslağı

- Admin: tüm operasyon
- Finance: ödeme/iade kayıtları
- Support: destek ve şikayetler
- Moderator: yorum ve görsel moderasyonu

## Later

- Gelişmiş raporlama
- Otomatik risk skorlaması
- SLA takip paneli
- Admin bildirimleri
- Çoklu ülke/şehir operasyon ayrımı
