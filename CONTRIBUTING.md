# Contributing

Thank you for your interest in Webey. This repository is a **portfolio-safe
public mirror** of a commercial product, shared for evaluation and demonstration.
It is not an open-source project accepting general feature contributions.

## Scope

Because this is a portfolio copy:

- The canonical development happens in a separate private repository.
- Production infrastructure and confidential configuration are not present here.
- Pull requests that depend on private services may not be runnable end-to-end.

That said, the following are welcome:

- Bug reports about the **public code** in this repository.
- Documentation fixes and clarifications.
- Notes if you believe a sensitive value slipped through sanitization
  (please report these privately — see [`SECURITY.md`](SECURITY.md)).

## Development conventions

### Mobile (Flutter)
- Feature-first structure under `lib/features/`, with shared code in `lib/shared/`
  and cross-cutting concerns in `lib/core/`.
- Run static analysis and tests before submitting:
  ```bash
  cd webey-mobile
  flutter pub get
  flutter analyze
  flutter test
  ```

### Backend (PHP)
- Endpoints are grouped by domain under `webey-site/api/`.
- Use PDO with prepared statements; never interpolate user input into SQL.
- Keep secrets out of source — use environment variables or the git-ignored
  `api/keys/` directory (see the `*.example` templates).
- Lint changed files:
  ```bash
  php -l path/to/file.php
  ```

### Database
- Schema changes are expressed as dated migration files in
  `webey-site/database/migrations/` and must be idempotent where practical.

## Commit style

- Keep commits focused and descriptive.
- Never commit credentials, keys, `.env` files, build artifacts, or user data.
  The root `.gitignore` is configured to help prevent this.
