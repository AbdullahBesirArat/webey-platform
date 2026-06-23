# Webey — Barbershop Appointment Platform

> **Turkey's online barbershop booking system.** Customers discover nearby businesses and book appointments in seconds; business owners manage their calendar, staff, and subscription from a single dashboard.

**Live Site:** [webey.com.tr](https://webey.com.tr)

---

## 📋 Table of Contents

- [About](#-about)
- [Features](#-features)
- [Tech Stack](#-tech-stack)
- [Architecture](#-architecture)
- [Project Structure](#-project-structure)
- [Database Schema](#-database-schema)
- [API Reference](#-api-reference)
- [Auth Architecture](#-auth-architecture)
- [Frontend Architecture](#-frontend-architecture)
- [PWA & Service Worker](#-pwa--service-worker)
- [Security](#-security)
- [Installation](#-installation)
- [Cron Jobs](#-cron-jobs)
- [Development Notes](#-development-notes)

---

## 🎯 About

Webey is a two-sided SaaS appointment platform:

- **Customers** search for barbershops by city/district, browse prices and staff profiles, and book instantly with real-time slot availability.
- **Business owners** complete a guided onboarding flow, then manage staff, working hours, calendar, and subscription — all from one place.

The project is built on a **monolithic PHP backend** and a **vanilla JS frontend**, designed from scratch with no external frameworks. Every layer is hand-written.

---

## ✨ Features

### Customer Side
- 🔍 Search & filter barbershops by city, district, price range, rating, and "open now"
- 📅 Real-time slot availability check with instant booking
- 🔔 Automated email + SMS reminders 24 hours and 1 hour before the appointment
- 📲 Export appointments to Google / Apple Calendar / Outlook (ICS format)
- ❤️ Favourite businesses list
- ⭐ Post-appointment reviews and ratings
- 🔒 Phone + password registration with a 4-step onboarding flow

### Business Owner / Admin Side
- 📊 Analytics: total appointments, occupancy rate, customer statistics
- 🗓️ Weekly/daily calendar view with block-time support
- 👥 Staff management: photo upload, working hours, service assignment
- 🛠️ Service catalogue: name, duration (minutes), price
- 💳 Iyzico-powered subscription management: add/remove cards, invoice history
- 📩 Cancellation request approval/rejection workflow
- 🔗 Google OAuth for quick sign-in
- 📝 Multi-step onboarding (business info → staff → services → publish)

### Platform / Technical
- 🌐 PWA: installable, offline page, web push notification infrastructure
- 🔒 CSRF token protection, brute-force protection (IP-based rate limiting)
- 🗃️ IP-based API rate limiting on sensitive endpoints
- 🔄 Session fixation protection, HttpOnly + SameSite cookies
- 🤖 Cron-based email queue, SMS queue, subscription reminders, token cleanup
- 🗺️ Business geolocation (latitude/longitude), ready for map integration
- 📦 Schema.org JSON-LD SEO markup, Open Graph, Twitter Card

---

## 🛠 Tech Stack

| Layer | Technology |
|-------|------------|
| **Backend** | PHP 8.2, PDO (MariaDB driver) |
| **Database** | MariaDB 10.4 / MySQL 8+ |
| **Auth** | PHP Sessions (cookie-based), Google OAuth 2.0 |
| **Payments** | Iyzico Payment API |
| **Email** | PHPMailer / SMTP |
| **SMS** | Configurable provider (`_sms_config.php`) |
| **Frontend** | Vanilla JS (ES Modules), HTML5, CSS3 |
| **PWA** | Service Worker, Web Push API, Web App Manifest |
| **Server** | Apache (`.htaccess` URL rewrite + security rules) |
| **Deployment** | Shared hosting / VPS compatible; Composer optional |

---

## 🏛 Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     CLIENT (Browser)                    │
│  HTML/CSS/JS   ←→   api-client.js  ←→   Service Worker │
└────────────────────────┬────────────────────────────────┘
                         │ HTTPS (JSON)
┌────────────────────────▼────────────────────────────────┐
│                  Apache / PHP 8.2                       │
│                                                         │
│  _bootstrap.php  →  Session  →  CSRF  →  Auth guard    │
│                                                         │
│  /api/auth/          Admin login, register, OAuth       │
│  /api/user/          Customer login, register, profile  │
│  /api/appointments/  Appointment CRUD                   │
│  /api/calendar/      Admin calendar view                │
│  /api/billing/       Iyzico subscription & invoices     │
│  /api/public/        Auth-free search & listings        │
│  /api/staff/         Staff management                   │
│  /api/services/      Service management                 │
│  /api/reviews/       Review system                      │
│  /api/push/          Web Push subscriptions             │
└────────────────────────┬────────────────────────────────┘
                         │ PDO
┌────────────────────────▼────────────────────────────────┐
│                   MariaDB 10.4                          │
│  15+ tables: users, businesses, appointments,           │
│  staff, services, reviews, subscriptions ...            │
└─────────────────────────────────────────────────────────┘
```

---

## 📁 Project Structure

```
webey/
│
├── api/                            # All backend endpoints
│   ├── _bootstrap.php              # Admin session + DB + CSRF guard
│   ├── _public_bootstrap.php       # Public endpoint bootstrap (no auth)
│   ├── _init.php                   # Global init (CORS, error settings)
│   ├── wb_response.php             # wb_ok(), wb_err(), wb_validate(), wb_csrf_*()
│   ├── _mailer.php                 # PHPMailer wrapper
│   ├── _sms.php                    # SMS sending wrapper
│   ├── _iyzico.php                 # Iyzico payment integration
│   ├── _helpers.php                # Shared utility functions
│   ├── _slug.php                   # SEO slug generator
│   ├── _logout_helper.php          # Shared logout logic
│   ├── _subscription_check.php     # Subscription validity guard
│   │
│   ├── session/
│   │   └── me.php                  # ★ Unified session endpoint (admin + user)
│   │
│   ├── auth/                       # Admin / business owner auth
│   │   ├── login.php
│   │   ├── register.php
│   │   ├── logout.php
│   │   ├── google-login.php        # Google OAuth callback
│   │   ├── forgot-password.php
│   │   ├── reset-password.php
│   │   ├── verify-email.php
│   │   ├── send-otp.php
│   │   └── verify-otp.php
│   │
│   ├── user/                       # Customer auth & profile
│   │   ├── login.php
│   │   ├── register.php
│   │   ├── logout.php
│   │   ├── me.php                  # → session/me.php shim
│   │   ├── appointments.php        # Customer's appointments list
│   │   ├── appointments/
│   │   │   ├── cancel.php
│   │   │   └── next.php
│   │   ├── favorites/
│   │   │   ├── list.php
│   │   │   ├── toggle.php
│   │   │   └── check.php
│   │   └── profile/
│   │       └── update.php
│   │
│   ├── appointments/               # Appointment CRUD (general)
│   │   ├── book.php                # Create new appointment
│   │   ├── booked-map.php          # Booked slot map
│   │   ├── check-conflict.php      # Conflict detection
│   │   ├── lock.php / unlock.php   # Optimistic slot locking
│   │   ├── cancel.php
│   │   ├── reschedule.php
│   │   ├── setStatus.php
│   │   ├── export-ics.php          # Calendar export (ICS)
│   │   └── counters.php
│   │
│   ├── calendar/                   # Admin calendar view
│   │   ├── bootstrap.php
│   │   ├── appointments.php
│   │   ├── block-time.php
│   │   ├── approve-cancellation.php
│   │   ├── reject-cancellation.php
│   │   ├── cancellation-requests.php
│   │   ├── customer-history.php
│   │   └── pending-notifications.php
│   │
│   ├── billing/                    # Subscription & payments
│   │   ├── subscribe.php
│   │   ├── cancel.php
│   │   ├── cards.php
│   │   ├── add-card.php
│   │   ├── remove-card.php
│   │   ├── invoices.php
│   │   ├── apply-promo.php
│   │   ├── cron_expire.php         # Process expired subscriptions
│   │   ├── cron_reminders.php      # 24h/1h appointment reminders
│   │   └── cron_sub_reminders.php  # Subscription renewal reminders
│   │
│   ├── public/                     # Auth-free public API
│   │   ├── salons.php              # Business listing (filters + pagination)
│   │   ├── business.php            # Single business detail
│   │   ├── businesses.php
│   │   └── suggest.php             # Autocomplete suggestions
│   │
│   ├── staff/                      # Staff management
│   ├── services/                   # Service management
│   ├── reviews/                    # Reviews & ratings
│   ├── settings/                   # Business settings & image upload
│   ├── notifications/              # Admin notifications
│   ├── push/                       # Web Push subscriptions
│   ├── admin/                      # Admin-specific endpoints
│   └── superadmin/                 # Platform management panel
│
├── js/                             # Frontend JavaScript
│   ├── api-client.js               # ★ Central fetch wrapper + session state
│   ├── wb-api-shim.js              # Global window.apiGet / window.apiPost
│   ├── auth.js                     # Customer register/login UI (4 steps)
│   ├── calendar.js                 # Admin calendar
│   ├── appointments.js             # Appointments page
│   ├── settings.js                 # Settings page
│   ├── staff.js                    # Staff management
│   ├── kuafor.js                   # Business detail page
│   ├── index.js                    # Home page
│   ├── service-worker.js           # PWA Service Worker
│   ├── wb-bottom-nav.js            # Mobile bottom navigation
│   ├── wb-notifications.js         # Admin notification system
│   ├── wb-user-notifications.js    # Customer notification system
│   ├── wb-transitions.js           # Page transition animations
│   ├── locations-tr.json           # Turkey city/district dataset
│   └── components/
│       ├── autocomplete.js
│       ├── dob-picker.js
│       ├── select-combo.js
│       └── when-modal.js
│
├── css/                            # Page and component styles
├── database/
│   ├── schema.sql                  # Full database schema
│   └── webey_migration_001.sql     # Indexes + appointment_logs migration
│
├── core/
│   ├── init.php
│   ├── response.php
│   └── uploadTools.php
│
├── service-worker.js               # Root Service Worker (PWA)
├── manifest.json                   # Web App Manifest
├── db.php                          # PDO connection
├── .htaccess                       # Apache rewrite + security rules
└── sitemap.xml
```

---

## 🗄 Database Schema

The project uses **15+ tables**. Core relationships:

```
users (1) ──── (1) admin_users
users (1) ──── (1) customers
users (1) ──── (*) businesses     [owner_id]

businesses (1) ──── (*) staff
businesses (1) ──── (*) services
businesses (1) ──── (*) appointments
businesses (1) ──── (*) reviews
businesses (1) ──── (*) subscriptions
businesses (1) ──── (*) business_hours

staff (1) ──── (*) staff_hours
staff (1) ──── (*) appointments

appointments (1) ──── (*) appointment_logs
appointments (1) ──── (*) appointment_reminders

customers (1) ──── (*) favorites
customers (1) ──── (*) reviews
```

### Key Tables

| Table | Description |
|-------|-------------|
| `users` | All users (admin + customer), UNIQUE by email |
| `admin_users` | 1:1 with `users`, extra data for business owners |
| `businesses` | Business profiles; slug, geolocation, onboarding state |
| `customers` | 1:1 with `users`, customer profiles |
| `appointments` | Appointments; status enum, booking_source, reminder flags |
| `appointment_logs` | Appointment status history (full audit trail) |
| `appointment_reminders` | Send channel (email/SMS) and schedule |
| `services` | Business services; name, duration (minutes), price |
| `staff` | Staff members; photo, bio |
| `staff_hours` | Per-staff weekly working hours |
| `business_hours` | Business-wide working hours |
| `reviews` | Ratings, comments, approval status |
| `favorites` | Customer–business favourite relationship |
| `subscriptions` | Active/cancelled subscription records |
| `invoices` | Invoice history |
| `payment_cards` | Saved Iyzico card tokens |
| `api_rate_limits` | IP-based rate limiting records |
| `login_attempts` | Brute-force tracking table |
| `push_subscriptions` | Web Push notification subscriptions |

### Appointment State Machine

```
pending ──→ approved ──→ completed
   │            │
   │            └──→ cancellation_requested ──→ cancelled
   │                                        └──→ approved (rejected)
   └──→ rejected
   └──→ declined
   └──→ no_show
```

---

## 📡 API Reference

All endpoints are prefixed with `/api/`. Every response follows a standard format:

```json
// Success
{ "ok": true, "data": { ... } }

// Error
{ "ok": false, "error": "Human-readable message", "code": "snake_case_key" }
```

**HTTP Status Codes:** `200` success · `400` validation · `401` unauthenticated · `403` forbidden · `404` not found · `409` conflict · `422` unprocessable · `429` rate limited · `500` server error

---

### 🔐 Session

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| GET/POST | `session/me.php` | — | Unified session check |
| GET | `auth/me.php` | admin | **[shim]** → `session/me.php` |
| GET | `user/me.php` | user | **[shim]** → `session/me.php` |

```json
// Admin session
{ "ok": true, "data": { "role": "admin", "user_id": 1, "business_id": 44 } }
// Customer session
{ "ok": true, "data": { "role": "user", "user_id": 114 } }
// No session
{ "ok": false, "code": "unauthenticated" }
```

---

### 👤 Admin Auth

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `auth/login.php` | Email + password login |
| POST | `auth/register.php` | New admin registration |
| POST | `auth/logout.php` | Logout |
| POST | `auth/google-login.php` | Google OAuth login/register |
| POST | `auth/forgot-password.php` | Send password reset email |
| POST | `auth/reset-password.php` | Set new password via token |
| POST | `auth/verify-email.php` | Email verification |

---

### 📱 Customer Auth

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `user/login.php` | Phone + password login |
| POST | `user/register.php` | New customer registration |
| POST | `user/logout.php` | Logout |
| POST | `user/completeSignup.php` | Complete 4-step onboarding |
| POST | `user/profile/update.php` | Update name, phone, email, password |

---

### 📅 Appointments

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| POST | `appointments/book.php` | — | Create new appointment |
| GET | `appointments/booked-map.php` | — | Booked time slots |
| POST | `appointments/check-conflict.php` | — | Check for scheduling conflicts |
| POST | `appointments/lock.php` | — | Reserve a slot (optimistic lock) |
| POST | `appointments/unlock.php` | — | Release slot lock |
| POST | `appointments/cancel.php` | — | Submit cancellation request |
| POST | `appointments/reschedule.php` | — | Reschedule appointment |
| GET | `appointments/export-ics.php` | user/token | Download ICS calendar file |
| POST | `appointments/setStatus.php` | admin | Update appointment status |
| GET | `appointments/counters.php` | admin | Appointment counts by status |

---

### 🌐 Public API (No Auth Required)

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `public/salons.php` | Business listing with filters |
| GET | `public/business.php` | Single business detail |
| GET | `public/suggest.php` | Autocomplete search suggestions |

**`public/salons.php` Query Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `city` | string | City filter |
| `district` | string | District filter |
| `q` | string | Name/description search |
| `sort` | string | `newest` · `rating` · `price_asc` · `price_desc` · `name` |
| `min_rating` | float | Minimum rating |
| `min_price` / `max_price` | int | Price range (TRY) |
| `open_now` | bool | Only currently open businesses |
| `page` / `limit` | int | Pagination (default: 18 per page) |

Response includes a `meta` object: `{ total, page, limit, pages, has_more }`

---

### 📆 Calendar (Admin)

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `calendar/bootstrap.php` | Initial data (staff, services) |
| GET | `calendar/appointments.php` | Appointments for a date range |
| POST | `calendar/block-time.php` | Add a blocked time period |
| GET | `calendar/cancellation-requests.php` | Pending cancellation requests |
| POST | `calendar/approve-cancellation.php` | Approve cancellation |
| POST | `calendar/reject-cancellation.php` | Reject cancellation |
| GET | `calendar/customer-history.php` | Customer's appointment history |

---

### 💳 Billing (Admin)

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `billing/subscribe.php` | Start subscription (Iyzico) |
| POST | `billing/cancel.php` | Cancel subscription |
| GET | `billing/cards.php` | Saved payment cards |
| POST | `billing/add-card.php` | Add card |
| POST | `billing/remove-card.php` | Remove card |
| GET | `billing/invoices.php` | Invoice history |
| POST | `billing/apply-promo.php` | Apply promo code |

---

## 🔑 Auth Architecture

Two independent user types use separate session key sets:

### Admin / Business Owner
```
Session keys: user_id, admin_id, email, business_id
Login:    POST /api/auth/login.php       { email, password }
Register: POST /api/auth/register.php    { email, password }
Logout:   POST /api/auth/logout.php
```

### Customer
```
Session keys: user_id, user_role='user', user_phone
Login:    POST /api/user/login.php       { phone, password }
Register: POST /api/user/register.php    { phone, password, firstName, ... }
Logout:   POST /api/user/logout.php
```

### Unified Session Check

`api/session/me.php` handles both roles in a single request. `api-client.js → refreshSession()` uses this endpoint exclusively. `api/auth/me.php` and `api/user/me.php` are thin shims that redirect to it.

### Session Security Settings (`_bootstrap.php`)

```php
session.cookie_httponly  = 1         // No JS access to session cookie
session.cookie_samesite  = Lax       // CSRF mitigation
session.cookie_secure    = 1         // HTTPS only (production)
session.use_strict_mode  = 1         // Session fixation protection
session.gc_maxlifetime   = 7200      // 2-hour server-side TTL
```

---

## 🖥 Frontend Architecture

### `api-client.js` — Single Fetch Entry Point

```js
import { api, getSession, onAuthChange, refreshSession } from './api-client.js';

// GET / POST
const res = await api.get('/api/public/salons.php?city=Istanbul');
const res = await api.post('/api/appointments/book.php', { staffId, startAt });

// React to session changes
onAuthChange(session => {
  if (!session) return showLoginPrompt();
  if (session.type === 'admin') return renderAdminUI(session);
  if (session.type === 'user')  return renderUserUI(session);
});
```

### `wb-api-shim.js` — Global API Layer

Provides `window.apiGet` / `window.apiPost` global functions for older-style pages (`calendar.js`, `settings.js`, `staff.js`, `profile.js`).

**Features:**
- 12-second timeout + 1 automatic retry on 5xx errors
- 401/403 → automatic redirect to login page
- Offline detection via `navigator.onLine`
- Automatic CSRF token header injection

### `auth.js` — Customer Register/Login UI

4-step registration flow:
1. Phone number entry
2. Password setup
3. Full name and date of birth
4. Address information

---

## 📲 PWA & Service Worker

`service-worker.js` uses three separate cache buckets:

| Cache | Contents | Strategy |
|-------|----------|----------|
| `webey-static-v2` | CSS, JS, fonts | Stale-while-revalidate |
| `webey-pages-v2` | HTML pages | Network-first |
| `webey-images-v2` | Images | Cache-first, 3-day TTL |

**Key Notes:**
- API requests are **never** cached
- While offline, `/offline.html` is shown and auto-redirects when connectivity returns
- `push` and `notificationclick` event handlers are in place for Web Push
- To invalidate all caches on deploy, increment `CACHE_VERSION` (e.g. `'v3'`); old caches are purged automatically

**`manifest.json` App Shortcuts:**
- "Find Barber" → `/kuafor.html`
- "My Appointments" → `/user-profile.html`

---

## 🔒 Security

### CSRF Protection

```php
// Defined in wb_response.php
wb_csrf_token();   // Generate and return a token
wb_csrf_verify();  // Mandatory check on all POST/PUT/DELETE requests
```

The frontend sends the token via the `X-CSRF-Token` header; `wb-api-shim.js` adds it automatically to every mutating request.

### Brute-Force Protection

IP-based tracking via the `login_attempts` table:
- 10 failed attempts within 5 minutes → HTTP `429 Too Many Requests`
- Active on both admin login and customer login endpoints

### IP-Based Rate Limiting

The `api_rate_limits` table enforces limits on high-risk endpoints such as appointment booking (`book.php`) and slot locking (`lock.php`).

### Input Validation

```php
wb_validate($data, [
    'email'    => ['required', 'email', 'max:191'],
    'password' => ['required', 'min:8'],
    'phone'    => ['required', 'regex:/^5\d{9}$/'],
]);
// Supported rules: required, email, numeric, min:N, max:N, regex:/pattern/, in:a,b,c
```

### Additional Measures
- All SQL queries use PDO prepared statements — no SQL injection possible
- File upload endpoints validate MIME type and file size
- `.htaccess` blocks direct access to `api/keys/` and sensitive PHP files
- `display_errors = 0` enforced in production

---

## 🚀 Installation

### Requirements

- PHP 8.2+
- MariaDB 10.4+ / MySQL 8+
- Apache with `mod_rewrite` enabled
- Composer (optional, for PHPMailer)

### Steps

```bash
# 1. Clone the repository into your web root
git clone https://github.com/yourusername/webey.git /var/www/html/

# 2. Create the database
mysql -u root -p -e "CREATE DATABASE webey_local CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

# 3. Run the schema
mysql -u root -p webey_local < database/schema.sql

# 4. Apply migrations
mysql -u root -p webey_local < database/webey_migration_001.sql

# 5. Configure the database connection
cp db.php.example db.php
# Edit db.php: fill in DB_HOST, DB_NAME, DB_USER, DB_PASS

# 6. Configure email
# Fill in api/_email_config.php (SMTP host, credentials, site_url)

# 7. Set Google OAuth Client ID
# api/auth/google-login.php → CLIENT_ID constant
# index.html → meta[name="google-signin-client_id"]

# 8. Set Iyzico API keys
# api/_iyzico_config.php

# 9. Set upload directory permissions
chmod 755 uploads/
chmod 755 uploads/biz/
```

### Environment Variables (Recommended)

Manage sensitive values via `$_ENV` rather than hardcoding them:

```php
// db.php
$pdo = new PDO(
    'mysql:host=' . ($_ENV['DB_HOST'] ?? 'localhost')
        . ';dbname=' . ($_ENV['DB_NAME'] ?? 'webey_local'),
    $_ENV['DB_USER'] ?? 'root',
    $_ENV['DB_PASS'] ?? ''
);
```

---

## ⏰ Cron Jobs

The following cron jobs must be registered on the server:

```bash
# Appointment reminder emails (every 15 minutes)
*/15 * * * *  php /var/www/html/api/billing/cron_reminders.php    >> /var/log/webey_reminders.log 2>&1

# Subscription renewal reminders (daily)
0 9  * * *    php /var/www/html/api/billing/cron_sub_reminders.php >> /var/log/webey_sub.log 2>&1

# Expire overdue subscriptions (daily)
0 1  * * *    php /var/www/html/api/billing/cron_expire.php        >> /var/log/webey_expire.log 2>&1

# Email queue processor (every 5 minutes)
*/5 * * * *   php /var/www/html/api/cron_send_emails.php           >> /var/log/webey_mail.log 2>&1

# SMS queue processor (every 5 minutes)
*/5 * * * *   php /var/www/html/api/cron_send_sms.php              >> /var/log/webey_sms.log 2>&1

# Rate limit & token cleanup (nightly)
0 3  * * *    php /var/www/html/api/cron_cleanup.php               >> /var/log/webey_cleanup.log 2>&1
```

---

## 📝 Development Notes

### Known Technical Debt

- `calendar.js`, `settings.js`, and `staff.js` still use local `apiGet`/`apiPost` definitions → should be migrated to `wb-api-shim.js` or `api-client.js`
- Google Auth is managed via an inline `<script>` block on some pages → should be consolidated into `auth.js`

### Roadmap (Suggested Next Steps)

1. **SMS OTP** — Customer phone verification via Twilio or Netgsm
2. **Map integration** — `latitude`/`longitude` columns are ready; add Leaflet.js to the business detail page
3. **Multi-service booking** — Allow selecting multiple services in a single appointment
4. **SEO-friendly URLs** — Replace `kuafor.html?id=X` with clean `/{slug}` routes
5. **Live push notifications** — Web Push infrastructure is in place; activate by adding VAPID keys
6. **Superadmin dashboard** — `api/superadmin/` endpoints exist; front-end UI needs to be built

### Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/your-feature-name`
3. Commit your changes: `git commit -m 'feat: description of your feature'`
4. Push the branch: `git push origin feature/your-feature-name`
5. Open a Pull Request

---

## 📄 License

This project is currently under a proprietary license. For inquiries: [webey.com.tr](https://webey.com.tr)

---

<div align="center">
  <strong>Webey</strong> · PHP 8.2 · MariaDB · Vanilla JS · PWA<br/>
  <em>Discover nearby barbershops and book an appointment in seconds.</em>
</div>
