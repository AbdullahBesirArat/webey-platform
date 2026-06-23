# Security Policy

## Portfolio-safe repository

This is a **sanitized, public, portfolio version** of the commercial Webey
platform. It was prepared specifically so that it can be shared publicly without
exposing any production secrets or user data.

### What was excluded
The following categories of files were deliberately **not** copied into this
repository, or were replaced with non-sensitive `*.example` templates:

- **Credentials & secrets** — database, SMTP/Brevo, SMS provider, and iyzico
  payment keys; the real `api/keys/` secret store; the real `_iyzico_config.php`.
- **Signing material** — Android keystore (`*.jks`), `key.properties`, and any
  `.pem` / `.p12` / `.mobileprovision` certificates.
- **Firebase configuration** — the real `google-services.json` (a sanitized
  `google-services.json.example` is provided instead).
- **User & operational data** — uploaded media (`uploads/`), database dumps,
  deployment archives (`*.tar.gz`), QA/cleanup SQL scripts, logs, and caches.
- **Build artifacts** — `build/`, `.dart_tool/`, `.gradle/`, release `*.aab` /
  `*.apk` bundles, and IDE/local machine configuration.
- **Internal documents** — internal audit reports and private working notes.

A small amount of business contact information (publicly listed phone numbers
already published on the live website) is retained because it is already public.

### Fresh Git history
This repository was initialized with a **brand-new Git history**. None of the
original project's commits were reused, so no secret that may have existed in the
original history is reachable here.

## Reporting a vulnerability

If you believe you have found a security issue in this portfolio repository,
please open a private report to the repository owner rather than filing a public
issue. Because this is a portfolio mirror, please do not attempt to access any
production system.

## For reviewers

If you spot anything in this public copy that looks like it could be a real secret
or personal datum that slipped through sanitization, please flag it privately so
it can be removed and the history rewritten.
