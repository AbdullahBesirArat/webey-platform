# Portfolio Notes

Ready-to-use copy for publishing this project across GitHub, your CV, and
LinkedIn. Adjust wording to taste.

## Suggested GitHub repository name

```
webey-platform
```

## Suggested GitHub repository description

> Full-stack, two-sided appointment booking & beauty business management platform
> — two Flutter apps (customer + business), a PHP REST API, MySQL, and Firebase
> push. Portfolio-safe public mirror.

## Suggested GitHub topics

```
flutter, dart, php, mysql, rest-api, mobile-app, firebase,
firebase-cloud-messaging, booking-system, appointment-scheduling,
beauty-tech, saas, monorepo, full-stack, portfolio
```

## Suggested CV project description

> **Webey — Full-Stack Appointment & Business Management Platform**
> Designed and built a two-sided platform for the beauty industry: a customer
> Flutter app (salon discovery, booking, favorites, campaigns, deposits,
> cancellations, push notifications) and a business Flutter app (profile, staff,
> services, gallery, bookings, campaigns, deposit/cancellation policies). Both
> share a single Flutter codebase via build flavors and communicate with a
> domain-organized PHP REST API over MySQL, with Firebase Cloud Messaging for
> push and SMTP/SMS for transactional messaging.
> *Stack: Flutter/Dart, PHP, MySQL, Firebase, REST.*

## Suggested LinkedIn project description

> **Webey** is a full-stack appointment booking and business management platform
> I built for the beauty and personal-care industry. It consists of two Flutter
> mobile apps — one for customers and one for businesses — backed by a PHP REST
> API, a MySQL database with a versioned migration history, and Firebase Cloud
> Messaging for push notifications.
>
> Highlights:
> • Single Flutter codebase producing two apps (customer & business) via flavors
> • Booking flow with availability selection, deposits, and cancellation policies
> • Campaign/discount system, favorites, reviews, and staff management
> • OTP-gated auth, CSRF protection, and a super-admin panel
> • Email (SMTP/Brevo), pluggable SMS providers, and push notifications
>
> This public repository is a portfolio-safe version with all production secrets,
> signing keys, and user data removed.

## Talking points (for interviews)

- **Monorepo / flavors:** one Flutter codebase, two published apps with distinct
  package IDs (`tr.com.webey.beauty`, `tr.com.webey.business`).
- **Feature-first architecture:** `core` / `features` / `shared` separation.
- **API design:** domain-organized PHP endpoints; PDO + prepared statements.
- **Data modeling:** schema plus dated, idempotent migrations.
- **Security posture:** secrets via env vars / git-ignored key store; CSRF and
  security headers; OTP-gated registration.
- **Notifications:** transactional email + SMS + Firebase push working together.
