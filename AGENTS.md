# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Wishiz — editorial-style wishlist manager. Monorepo with:
- `apps/api/` — Go 1.23 REST API + PostgreSQL
- `apps/mobile/` — Flutter 3.35+ app (iOS, Android, web)
- `contracts/openapi/` — OpenAPI specs

## Commands

### API (Go)
```bash
make test          # Run unit tests
make lint          # Run golangci-lint

docker compose -f docker-compose-dev.yml up --build    # Dev environment
docker compose up --build                               # Production
curl http://localhost:8080/health                       # Verify running
```

### Mobile (Flutter)
```bash
flutter pub get
flutter analyze
flutter test
flutter run -d chrome

# Override API in dev:
flutter run --dart-define=WISHIZ_API_BASE_URL=http://127.0.0.1:8080
```

Platform note: iOS simulator uses `127.0.0.1`, Android emulator uses `10.0.2.2`.

## API Architecture

Hexagonal/Clean Architecture, feature-based modules under `internal/features/`:

- `auth/` — signup, login, logout, 30-day session tokens
- `wishlists/` — CRUD, shared access (viewer/editor roles), invite tokens
- `productimports/` — async job queue (workers poll DB every 2s)
- `scrape/` — dual-mode: fast (goquery) or headless (chromedp) with 15s timeout
- `applinks/` — Android App Links + iOS Universal Links
- `health/` — health check endpoint

Each feature follows: `domain/` → `ports/` → `application/` → `adapters/`

Cross-cutting concerns in `internal/platform/`: config, HTTP server, DB connection, logger, authctx middleware.

**Startup sequence** (`cmd/api/main.go`): config → logger → routes → DB → migrations → background workers (import queue, exchange rate refresh) → HTTP server on `:8080` → graceful shutdown (10s).

## Mobile Architecture

Feature-based under `lib/`:
- `core/` — design system, API client, auth service, navigation, theme, shared widgets
- `features/auth/`, `features/home/`, `features/wishlists/`, `features/product_imports/`

**Design system ("The Curated Pulse"):**
- Manrope (headlines) + Inter (body)
- Lavender-Smoke base (`#FAF4FF`), primary gradient `#4647D3 → #9396FF`
- No dividing lines — hierarchy via tonal surface layers
- Card radius: 24px (xl), glassmorphism: 20px backdrop blur on floating nav

## Database

PostgreSQL 16. Migrations in `internal/platform/db/migrations/`. Extensions: pgcrypto, citext.

Core tables: `app_users`, `app_sessions`, `wishlists`, `wishlist_items`, `wishlist_members`, `wishlist_invites`. All have TIMESTAMPTZ timestamps with auto `updated_at` trigger.

Full schema: `docs/postgres_schema.md`.

## Key Config (Environment Variables)

| Var | Default | Notes |
|-----|---------|-------|
| `DATABASE_URL` | — | Required in prod |
| `APP_ENV` | `development` | |
| `HTTP_ADDR` | `:8080` | |
| `RUN_DB_MIGRATIONS` | `false` | Set `true` in dev |
| `PRODUCT_IMPORT_WORKER_COUNT` | `5` | Concurrent scrapers |
| `PRODUCT_IMPORT_POLL_INTERVAL` | `2s` | Queue poll rate |
| `EXCHANGE_RATE_REFRESH_INTERVAL` | `12h` | ECB source |
| `SHARE_BASE_URL` | `https://wishiz.app` | Deep link base |

## Linting

Go: `.golangci.yml` — 120 char line limit, local import prefix `github.com/danielrispler/wishiz/apps/api`. Enabled: govet, errcheck, staticcheck, goimports, gocritic, and others.
