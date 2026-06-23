# Local Setup Guide

This guide walks through running Webey locally. Every credential shown is a
**placeholder** — provide your own values and never commit real ones.

## 1. Prerequisites

| Component | Recommended |
|-----------|-------------|
| Flutter   | Stable channel, Dart SDK `^3.11` |
| Android   | Android Studio + SDK, a device or emulator |
| iOS       | Xcode (macOS only) |
| Backend   | PHP 8.x |
| Database  | MySQL 8.x |
| Push      | A Firebase project with Android (and iOS) apps registered |

## 2. Mobile apps

```bash
cd webey-mobile
flutter pub get
```

### Firebase / signing config (required for builds)
Copy the example templates and fill in your own values:

```bash
# Firebase Android config
cp android/app/google-services.json.example android/app/google-services.json

# Release signing (only needed for release builds)
cp android/key.properties.example android/key.properties
# then edit key.properties to point at your own keystore
```

### Run

```bash
# Customer app
flutter run -t lib/main_customer.dart --flavor customer

# Business app
flutter run -t lib/main_business.dart --flavor business
```

### Analyze & test

```bash
flutter analyze
flutter test
```

## 3. Backend (PHP API)

1. Serve the `webey-site/` directory with PHP 8 (Apache, Nginx + PHP-FPM, or
   `php -S localhost:8000` for quick local testing).
2. Provide configuration through environment variables. Start from the root
   `.env.example` and expose the values to PHP via your server:

   **Apache** (`.htaccess` / VirtualHost):
   ```apache
   SetEnv DB_HOST "localhost"
   SetEnv DB_NAME "webey_local"
   SetEnv DB_USER "root"
   SetEnv DB_PASS ""
   ```

   **Nginx** (site config / fastcgi_params):
   ```nginx
   fastcgi_param DB_HOST "localhost";
   fastcgi_param DB_NAME "webey_local";
   fastcgi_param DB_USER "root";
   fastcgi_param DB_PASS "";
   ```

   `webey-site/db.php` reads these and falls back to safe local defaults.

3. Optional integrations — copy the example configs to their real names and fill
   in your keys (these real files are git-ignored):
   ```bash
   cp _iyzico_config.php.example _iyzico_config.php          # payments
   cp api/keys/email.php.example api/keys/email.php          # email
   ```
   SMS credentials are read from environment variables (see `.env.example`).

## 4. Database

```bash
mysql -u <user> -p
CREATE DATABASE webey_local CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
exit

# Load base schema
mysql -u <user> -p webey_local < webey-site/database/schema.sql

# Apply migrations in chronological (filename) order
# webey-site/database/migrations/2026_*.sql
```

## 5. Verify

- The API responds to a public endpoint over HTTP/JSON.
- The mobile app can reach your API base URL (configure it in the app's config
  layer under `lib/core/config/`).
- Push notifications require a valid Firebase project and device token
  registration.

## Troubleshooting

- **DB connection fails** — confirm the `DB_*` environment variables are visible
  to PHP (`getenv('DB_HOST')` should return your value).
- **Missing google-services.json** — Firebase plugins will fail to build until
  the real file is in place.
- **Release build fails to sign** — ensure `key.properties` points to a valid
  keystore that you control.
