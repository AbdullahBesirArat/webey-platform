# Webey Beauty Security Notes

Bu notlar production öncesi güvenlik ve veri doğrulama başlıklarını toplar.

## Auth ve Token Saklama

- Access token kısa ömürlü olmalı.
- Refresh token güvenli saklama alanında tutulmalı.
- Çıkışta tokenlar temizlenmeli.
- Rol bazlı erişim backend tarafında zorunlu doğrulanmalı.

## Ödeme Callback Güvenliği

- Provider imzası doğrulanmadan ödeme durumu güncellenmemeli.
- Callback idempotent olmalı.
- Tutar, para birimi, appointment id ve business id backend kaydıyla eşleşmeli.
- Manuel inceleme durumları admin panelde görünmeli.

## Kapora ve İade Süreçleri

- İptal politikası randevu oluşturma anında snapshot olarak saklanmalı.
- İade kararları audit log'a yazılmalı.
- İşletme iptali ve müşteri iptali ayrı iş kurallarıyla değerlendirilmelidir.

## KVKK ve Kişisel Veri

- Telefon, e-posta, randevu geçmişi ve yorum verileri minimum gereklilikle saklanmalı.
- Kullanıcı veri silme ve dışa aktarma talepleri için süreç hazırlanmalı.
- CRM notları private alan olarak işaretlenebilmeli.

## Fotoğraflı Yorum Moderasyonu

- Görsel yükleme production'da içerik moderasyonundan geçmeli.
- Uygunsuz içerik bildirme akışı eklenmeli.
- İşletme yanıtları kötüye kullanım için izlenmeli.

## Admin Yetki Kontrolleri

- Admin aksiyonları role-based access control ile sınırlandırılmalı.
- Kritik aksiyonlar audit log'a yazılmalı.
- Ödeme/iade kayıtlarına erişim minimum yetki prensibiyle yapılmalı.

## Rate Limit ve Abuse

- Login, OTP, yorum gönderme, favori ekleme ve ödeme intent oluşturma endpointleri rate limit gerektirir.
- Şüpheli no-show, spam yorum ve sahte salon kayıtları risk bayrağı üretmelidir.

## Observability

- Crash/error logging production'da merkezi servise bağlanmalı.
- Payment ve auth hataları kişisel veri sızdırmadan loglanmalı.
