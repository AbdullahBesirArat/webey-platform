# Webey Beauty API Plan

Bu doküman mock data ile çalışan Flutter MVP'nin gerçek API'ye bağlanması için kontrat taslağıdır.

## MVP Önceliği

### Auth
- `POST /auth/customer/login`
- `POST /auth/business/login`
- `POST /auth/verify-otp`
- `POST /auth/refresh`
- `POST /auth/logout`

Örnek request:

```json
{ "phone": "+905550000000" }
```

Örnek response:

```json
{ "accessToken": "...", "refreshToken": "...", "user": { "id": "u1", "role": "customer" } }
```

### Customer
- `GET /customer/profile`
- `PUT /customer/profile`
- `GET /customer/appointments`
- `GET /customer/favorites`
- `POST /customer/favorites`

### Salons
- `GET /salons`
- `GET /salons/{id}`
- `GET /salons/{id}/services`
- `GET /salons/{id}/staff`
- `GET /salons/{id}/reviews`
- `GET /salons/{id}/portfolio`
- `GET /salons/{id}/available-slots`
- `POST /salons/{id}/waitlist`

### Appointments
- `POST /appointments`
- `GET /appointments/{id}`
- `POST /appointments/{id}/cancel`
- `POST /appointments/{id}/reschedule`

### Payments
- `POST /payments/deposit/intent`
- `POST /payments/subscription/intent`
- `POST /payments/boost/intent`
- `POST /payments/callback`
- `GET /payments/{id}`

Callback güvenliği:
- Provider imzası zorunlu doğrulanmalı.
- Payment status sadece backend tarafından güncellenmeli.
- Tutar, para birimi ve appointment/business id backend kayıtlarıyla eşleşmeli.

### Business
- `GET /business/dashboard`
- `GET /business/appointments`
- `PUT /business/deposit-settings`
- `GET /business/customers`
- `GET /business/analytics`
- `GET /business/reviews`
- `POST /business/reviews/{id}/reply`
- `GET /business/subscription`
- `POST /business/campaigns`

## Later

### Notifications
- `GET /notifications`
- `POST /notifications/{id}/read`
- `POST /notifications/read-all`

### Admin
- `GET /admin/salons/pending`
- `POST /admin/salons/{id}/approve`
- `POST /admin/salons/{id}/reject`
- `GET /admin/payments`
- `GET /admin/reports`
- `GET /admin/support-tickets`

### Reporting
- `GET /business/revenue-report`
- `GET /business/no-show-report`
- `GET /business/staff-performance`

## Genel Notlar

- Tüm liste endpointleri pagination desteklemeli.
- Tarihler ISO-8601 dönmeli.
- Para alanları minor unit veya decimal standardı ile netleştirilmeli.
- Hata response formatı `code`, `message`, `details` alanlarını içermeli.
