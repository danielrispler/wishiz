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
- `discover/` — curated/trending product discovery backed by PostgreSQL. Ingestion (background `SitemapWorker` over ~80 brand sitemaps + the internal seed endpoint) calls **`Scrape` only, never `ScrapeImport`** — so the paid ZenRows backstop never fires for discover. It persists **only `auto_complete` products** (the `isSeedable` gate in `application/gate.go`: confident verdict + name + image); `needs_review`/`failed` are dropped, never queued for human review. Each row carries a TTL (`expires_at`, `DISCOVER_ITEM_TTL`, default 30d) that **extends on every re-scrape** (upsert), and the total is capped (`DISCOVER_MAX_PRODUCTS`, default 2000). The maintenance worker's `SweepDiscoverProducts` deletes expired rows then evicts over-cap rows least-saved/oldest first (cascades to `discover_product_saves`).
- `wishlists/` — CRUD, shared access (viewer/editor roles), invite tokens
- `productimports/` — async job queue (workers poll DB every 2s). `needs_review` is a **terminal, non-retryable** outcome (human review), not a transient failure — `ClaimNext` only re-claims retryable rows, so a review job is never re-scraped. Only `failed` is retryable. The single `needsReviewOutcome` helper enforces this.
- `scrape/` — ONE concurrent pipeline (≤30s): static HTTP fetch + Shopify probe + headless render launch together, early-aborting the render once cheap sources clear the verdict gate (the gate's reconciliation is the auto-complete result — no second reconcile). Multi-extractor → field-level consensus (`application/extractors/` + `consensus.go`) → validation gate → calibrated `Verdict` (auto_complete/needs_review/failed). Adapters: `httpfetch` (static; uses `bogdanfinn/tls-client` via `httpx.NewChromeClient` for a FULL Chrome fingerprint — JA3/JA4 **and** HTTP/2 SETTINGS/header-order — aligned to the UA pool's Chrome 124; follows HTTP 3xx **and** meta-refresh/JS-location redirects with per-hop SSRF re-validation, builds one client+jar per Fetch so cookies carry hop→hop), `headless` (render), `shopify` (probe). Two utls forks coexist **by design**: `bogdanfinn/utls` (via tls-client) for the anti-bot fetcher, and `refraction-networking/utls` (`httpx.NewUTLSTransport`, TLS-only + HTTP/1.1-pinned) for the discover sitemap worker — do NOT consolidate them (noted in go.mod too). The static fetcher disables tls-client's own gzip handling (`DisableCompression`) and decodes the body itself. This fingerprint does NOT beat JS-challenge/datacenter-IP blocks (aritzia/crate&barrel) on its own — those are rescued by the **ZenRows paid backstop** (`adapters/zenrows`, ADR-0002): a presence-gated (`ZENROWS_API_KEY`) second pass that fires ONLY on the product-import path (`Service.ScrapeImport`, called by the import worker — never discover or the synchronous `/scrape` route, which use `Scrape`/`ScrapeWithProgress`) when the own verdict is not `auto_complete`. It makes ONE residential-proxy + headless ZenRows fetch (`js_render`+`premium_proxy`, 25× cost), folds the rendered HTML through the SAME extractors (transport, NOT a source: no new `SourceName`, no migration, no drift/trust-matrix change) and re-reconciles. A **verdict-floor guard** (`verdictRank`) keeps the re-reconcile only when it does not lower the verdict, so a geo-priced exit can never degrade the outcome; the exit is pinned to the site's ccTLD (`inferProxyCountry`; `.com`/`.eu`→unpinned). Its timeout (`ZENROWS_TIMEOUT`, default 30s) is ON TOP of `SCRAPE_BUDGET` (derived from the inbound ctx, worst case ~60s/job). Any ZenRows error soft-fails to the own product, never retried (ADR-0001). Live backstop proof: `ZENROWS_API_KEY=… go test -tags scrapelive -run ZenRows ./internal/features/scrape/adapters/zenrows/`. Live fingerprint proof: `go test -tags scrapelive -run Fingerprint ./internal/features/scrape/adapters/httpfetch/` (hits tls.peet.ws). The set of `price_source` strings is owned by `extractors.AllSourceNames()`; the `price_source` CHECK in `000001_init_wishlists.up.sql` must mirror it exactly (a drift test reading the SQL enforces this). Currency policy is SAFE: a bare `$` is ambiguous and never auto-assigns USD — it falls to locale/TLD inference or `needs_review`. **Auto-complete gate** (`verdict.go`, relaxed): name+price ≥ MEDIUM (price NOT `conflict`/LOW/MISSING) and currency HIGH-or-inferred-MEDIUM; **image is display-only and does not gate**. A failed currency conversion forces review via an explicit override in `service.applyConversion` (a MEDIUM downgrade would now still auto-complete). **Brand-image fallback** (`extractors/brandimage.go`): when no product image survives, `ImageURL` falls back to the site brand asset (apple-touch-icon → favicon → rejected og:image) on its own `FieldBrandImage` candidate — applied AFTER the verdict so it never forces review, never votes in consensus, and adds no `SourceName`. The `eval/` harness (`go test -tags eval`) asserts a <1% false-auto-complete ceiling.
- `uploads/` — authenticated image upload endpoints backed by S3-compatible storage
- `applinks/` — Android App Links + iOS Universal Links
- `health/` — health check endpoint

Each feature follows: `domain/` → `ports/` → `application/` → `adapters/`

Cross-cutting concerns in `internal/platform/`: config, HTTP server, DB connection, logger, authctx context helpers, storage.

**Startup sequence** (`cmd/api/main.go`): config → logger → base routes (`applinks`, `health`) → scraper + exchange-rate setup → optional DB connection → optional migrations → conditional registration of auth/wishlists/productimports/discover/uploads → background workers (product-import, discover sitemap, maintenance sweep) → HTTP server on `HTTP_ADDR` (default `:8080`) → graceful shutdown (10s).

The **maintenance worker** (`internal/platform/maintenance`) is a ticker (default `CLEANUP_INTERVAL` = 1h) that deletes expired `app_sessions` and expired/unaccepted `wishlist_invites` — rows nothing else removes once they lapse — and, when the DB is up (`WithDiscoverSweeper`), sweeps TTL-expired and over-cap `discover_products`.

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
| `ZENROWS_API_KEY` | `""` | Presence-gates the paid scrape backstop (import path only). Unset → disabled |
| `ZENROWS_TIMEOUT` | `30s` | Backstop fetch timeout, applied ON TOP of `SCRAPE_BUDGET` |
| `EXCHANGE_RATES_URL` | `https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml` | ECB rates feed |
| `PRODUCT_IMPORT_WORKER_COUNT` | `5` | Concurrent scrapers |
| `PRODUCT_IMPORT_POLL_INTERVAL` | `2s` | Queue poll rate |
| `EXCHANGE_RATE_REFRESH_INTERVAL` | `12h` | ECB source |
| `DISCOVER_ITEM_TTL` | `720h` | Discover product lifetime; stamped on `expires_at`, extended on every re-scrape |
| `DISCOVER_MAX_PRODUCTS` | `2000` | Global cap on stored discover rows; over-cap evicted least-saved/oldest first (0 disables) |
| `CLEANUP_INTERVAL` | `1h` | Maintenance sweep rate for expired sessions/invites + discover TTL/cap |
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
