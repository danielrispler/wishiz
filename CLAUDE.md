# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Maintenance Rule

Treat this file as living documentation. If you change the repo in a way that makes `CLAUDE.md` inaccurate or incomplete, update `CLAUDE.md` in the same task so the instructions stay current.

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

cp .env.example .env
docker compose up --build
curl http://localhost:8080/health
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
- `discover/` — curated/trending product discovery backed by PostgreSQL
- `wishlists/` — CRUD, shared access (viewer/editor roles), invite tokens
- `productimports/` — async job queue (workers poll DB every 2s). `needs_review` is a **terminal, non-retryable** outcome (human review), not a transient failure — `ClaimNext` only re-claims retryable rows, so a review job is never re-scraped. Only `failed` is retryable. The single `needsReviewOutcome` helper enforces this.
- `scrape/` — ONE concurrent pipeline (≤30s): static HTTP fetch + Shopify probe + headless render launch together, early-aborting the render once cheap sources clear the verdict gate (the gate's reconciliation is the auto-complete result — no second reconcile). Multi-extractor → field-level consensus (`application/extractors/` + `consensus.go`) → validation gate → calibrated `Verdict` (auto_complete/needs_review/failed). Adapters: `httpfetch` (static, utls+anti-bot, follows meta-refresh/JS-location redirects), `headless` (render), `shopify` (probe). The set of `price_source` strings is owned by `extractors.AllSourceNames()`; the `price_source` CHECK in `000001_init_wishlists.up.sql` must mirror it exactly (a drift test reading the SQL enforces this). Currency policy is SAFE: a bare `$` is ambiguous and never auto-assigns USD — it falls to locale/TLD inference or `needs_review`.
- `uploads/` — authenticated image upload endpoints backed by S3-compatible storage
- `applinks/` — Android App Links + iOS Universal Links
- `health/` — health check endpoint

Each feature follows: `domain/` → `ports/` → `application/` → `adapters/`

Cross-cutting concerns in `internal/platform/`: config, HTTP server, DB connection, logger, authctx context helpers, storage.

**Startup sequence** (`cmd/api/main.go`): config → logger → base routes (`applinks`, `health`) → scraper + exchange-rate setup → optional DB connection → optional migrations → conditional registration of auth/wishlists/productimports/discover/uploads → background workers (product-import, discover sitemap, maintenance sweep) → HTTP server on `HTTP_ADDR` (default `:8080`) → graceful shutdown (10s).

The **maintenance worker** (`internal/platform/maintenance`) is a ticker (default `CLEANUP_INTERVAL` = 1h) that deletes expired `app_sessions` and expired/unaccepted `wishlist_invites` — rows nothing else removes once they lapse.

## Mobile Architecture

Feature-based under `lib/`:
- `app/` — app bootstrap and dependency wiring
- `core/` — config, constants, navigation, services, theme, utilities
- `shared/` — reusable shared widgets
- `features/auth/`, `features/discover/`, `features/home/`, `features/onboarding/`, `features/product_imports/`, `features/wishlists/`

**Design system ("The Curated Pulse"):**
- Manrope (headlines) + Inter (body)
- Lavender-Smoke base (`#FAF4FF`), primary gradient `#4647D3 → #9396FF`
- No dividing lines — hierarchy via tonal surface layers
- Card radius: 24px (xl), glassmorphism: 20px backdrop blur on floating nav

## Database

PostgreSQL 16. Migrations in `internal/platform/db/migrations/`. Extensions: pgcrypto, citext.

Pre-launch (0 users) the convention is to **edit the existing migration SQL in place** rather than add new migration files. Because migrations are versioned and `000001` uses `CREATE TABLE IF NOT EXISTS`, an in-place column add will **not** re-run on a DB that already has the table — **drop & recreate the local dev DB** after such a change (e.g. `docker compose down -v && docker compose up --build`). `product_import_jobs` carries `progress_stage`/`progress_percent` for the live import progress bar.

Core tables: `app_users`, `app_sessions`, `wishlists`, `wishlist_items`, `wishlist_members`, `wishlist_invites`. All have TIMESTAMPTZ timestamps with auto `updated_at` trigger. `wishlist_items` keeps both the display `price_label` and structured `price_amount`/`price_currency_code` (written at import time from the scraper, preserved on item edits).

Full schema: `docs/postgres_schema.md`.

## Key Config (Environment Variables)

| Var | Default | Notes |
|-----|---------|-------|
| `DATABASE_URL` | — | Required in prod |
| `APP_ENV` | `development` | |
| `HTTP_ADDR` | `:8080` | |
| `RUN_DB_MIGRATIONS` | `false` | Set `true` in dev |
| `UPLOADS_ENABLED` | `false` | Enable S3-backed upload routes |
| `STORAGE_S3_ENDPOINT` | `""` | S3-compatible endpoint |
| `STORAGE_S3_REGION` | `us-east-1` | Storage region |
| `STORAGE_S3_BUCKET` | `""` | Upload bucket name |
| `STORAGE_S3_ACCESS_KEY_ID` | `""` | Storage access key |
| `STORAGE_S3_SECRET_ACCESS_KEY` | `""` | Storage secret key |
| `STORAGE_S3_USE_PATH_STYLE` | `true` | Path-style S3 URLs |
| `STORAGE_PUBLIC_BASE_URL` | `""` | Public asset base URL |
| `CHROMIUM_PATH` | `""` | Optional path for headless scraping |
| `SCRAPE_BUDGET` | `30s` | Total wall-clock budget per scrape |
| `SCRAPE_RENDER_TIMEOUT` | `26s` | Headless render sub-timeout (< budget) |
| `SCRAPE_MAX_CONCURRENT_RENDERS` | `3` | Render semaphore (below worker count to bound memory) |
| `SCRAPE_SHOPIFY_PROBE` | `true` | Enable Shopify `/products/<handle>.json` probe |
| `SCRAPE_INFER_DOTCOM_USD` | `false` | Infer USD for `.com` w/o currency (silent-wrong-price trap; off) |
| `SCRAPE_MAX_PRICE` | `1e7` | Upper sanity bound on a scraped price amount |
| `EXCHANGE_RATES_URL` | `https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml` | ECB rates feed |
| `PRODUCT_IMPORT_WORKER_COUNT` | `5` | Concurrent scrapers |
| `PRODUCT_IMPORT_POLL_INTERVAL` | `2s` | Queue poll rate |
| `EXCHANGE_RATE_REFRESH_INTERVAL` | `12h` | ECB source |
| `CLEANUP_INTERVAL` | `1h` | Maintenance sweep rate for expired sessions/invites |
| `SHARE_BASE_URL` | `https://wishiz.app` | Deep link base |
| `ANDROID_APP_LINK_SHA256_CERT_FINGERPRINT` | built-in default | Android App Links fingerprint |
| `INTERNAL_API_KEY` | — | Used by internal discover ingestion routes |

## Linting

Go: `apps/api/.golangci.yml` — 120 char line limit, local import prefix `github.com/danielrispler/wishiz/apps/api`. Enabled: govet, errcheck, staticcheck, goimports, gocritic, and others.

Flutter: `flutter analyze` using `apps/mobile/analysis_options.yaml`, which includes `package:flutter_lints/flutter.yaml`.

## Agent skills

### Issue tracker

Issues live in GitHub Issues (`danielrispler/wishiz`). See `docs/agents/issue-tracker.md`.

### Triage labels

Default canonical label strings (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` + `docs/adr/` at repo root. See `docs/agents/domain.md`.
