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
- `discover/` — curated/trending product discovery backed by PostgreSQL. Ingestion (`SitemapWorker` over ~80 brand sitemaps + the internal seed endpoint) calls **`Scrape` only, never `ScrapeImport`** — so the paid ZenRows backstop never fires for discover. In prod the worker runs as the **weekly `discover-batch` Cloud Run Job** (`SitemapWorker.Refresh`); the in-process 24h ticker (`Start`) runs only in the `all` role (TTL 720h ≫ 7d, so nothing expires between runs). Routes are role-split: read/user routes + `POST /internal/discover/starter-packs` (`RegisterRoutes`, api role, nil-safe `scrapeService`) vs the scrape-backed seed route `POST /internal/discover/products` (`RegisterSeedRoutes`, scraper role). It persists **only `auto_complete` products** (the `isSeedable` gate in `application/gate.go`: confident verdict + name + image); `needs_review`/`failed` are dropped, never queued for human review. Each row carries a TTL (`expires_at`, `DISCOVER_ITEM_TTL`, default 30d) that **extends on every re-scrape** (upsert), and the total is capped (`DISCOVER_MAX_PRODUCTS`, default 2000). The maintenance worker's `SweepDiscoverProducts` deletes expired rows then evicts over-cap rows least-saved/oldest first (cascades to `discover_product_saves`).
- `wishlists/` — CRUD, shared access (viewer/editor roles), invite tokens
- `productimports/` — async job queue. `needs_review` is a **terminal, non-retryable** outcome (human review), not a transient failure — `ClaimNext` only re-claims retryable rows, so a review job is never re-scraped. Only `failed` is retryable. The single `needsReviewOutcome` helper enforces this. Two drain paths: in the `all` role an in-process poller (`ProcessNext`, every 2s) drains; in prod the api enqueues + creates a **Cloud Tasks** task (`internal/platform/importdispatch`, gated on `IMPORT_TASKS_QUEUE`+`SCRAPER_URL`) targeting the scraper's `POST /internal/imports/{id}/process` → `ProcessByID`, which `ClaimByID`-claims one job atomically (idempotent no-op on redelivery/terminal). The route returns 2xx only after the outcome persists (non-2xx → Cloud Tasks retries). If the final `Settle` write fails, `ProcessByID` calls `ReleaseToPending` (best-effort, no-op on terminal rows) to revert the row back to `pending` so the Cloud Tasks retry re-claims it promptly via `ClaimByID` rather than waiting for the lease-timeout sweep. Dispatch runs off the request path on a detached goroutine so its Cloud Tasks RPC latency never blocks the user's enqueue. Live dispatch requires `SCRAPER_INVOKER_SA` (else it would enqueue unauthenticated tasks) — a missing SA when dispatch is enabled **fails boot**. The **hourly `import-drain` Job** (`DrainPending`) recovers undispatched/stuck jobs.
- `scrape/` — ONE concurrent pipeline (≤30s): static HTTP fetch + Shopify probe + headless render launch together, early-aborting the render once cheap sources clear the verdict gate (the gate's reconciliation is the auto-complete result — no second reconcile). Multi-extractor → field-level consensus (`application/extractors/` + `consensus.go`) → validation gate → calibrated `Verdict` (auto_complete/needs_review/failed). Adapters: `httpfetch` (static; uses `bogdanfinn/tls-client` via `httpx.NewChromeClient` for a FULL Chrome fingerprint — JA3/JA4 **and** HTTP/2 SETTINGS/header-order — aligned to the UA pool's Chrome 124; follows HTTP 3xx **and** meta-refresh/JS-location redirects with per-hop SSRF re-validation, builds one client+jar per Fetch so cookies carry hop→hop), `headless` (render), `shopify` (probe). Two utls forks coexist **by design**: `bogdanfinn/utls` (via tls-client) for the anti-bot fetcher, and `refraction-networking/utls` (`httpx.NewUTLSTransport`, TLS-only + HTTP/1.1-pinned) for the discover sitemap worker — do NOT consolidate them (noted in go.mod too). The static fetcher disables tls-client's own gzip handling (`DisableCompression`) and decodes the body itself. This fingerprint does NOT beat JS-challenge/datacenter-IP blocks (aritzia/crate&barrel) on its own — those are rescued by the **ZenRows paid backstop** (`adapters/zenrows`, ADR-0002): a presence-gated (`ZENROWS_API_KEY`) second pass that fires ONLY on the product-import path (`Service.ScrapeImport`, called by the import worker — never discover or the synchronous `/scrape` route, which use `Scrape`/`ScrapeWithProgress`) when the own verdict is not `auto_complete`. It makes ONE residential-proxy + headless ZenRows fetch (`js_render`+`premium_proxy`, 25× cost), folds the rendered HTML through the SAME extractors (transport, NOT a source: no new `SourceName`, no migration, no drift/trust-matrix change) and re-reconciles. A **verdict-floor guard** (`verdictRank`) keeps the re-reconcile only when it does not lower the verdict, so a geo-priced exit can never degrade the outcome; the exit is pinned to the site's ccTLD (`inferProxyCountry`; `.com`/`.eu`→unpinned). Its timeout (`ZENROWS_TIMEOUT`, default 30s) is ON TOP of `SCRAPE_BUDGET` (derived from the inbound ctx, worst case ~60s/job). Any ZenRows error soft-fails to the own product, never retried (ADR-0001). Live backstop proof: `ZENROWS_API_KEY=… go test -tags scrapelive -run ZenRows ./internal/features/scrape/adapters/zenrows/`. Live fingerprint proof: `go test -tags scrapelive -run Fingerprint ./internal/features/scrape/adapters/httpfetch/` (hits tls.peet.ws). The set of `price_source` strings is owned by `extractors.AllSourceNames()`; the `price_source` CHECK in `000001_init_wishlists.up.sql` must mirror it exactly (a drift test reading the SQL enforces this). Currency policy is SAFE: a bare `$` is ambiguous and never auto-assigns USD — it falls to locale/TLD inference or `needs_review`. **Auto-complete gate** (`verdict.go`, relaxed): name+price ≥ MEDIUM (price NOT `conflict`/LOW/MISSING) and currency HIGH-or-inferred-MEDIUM; **image is display-only and does not gate**. A failed currency conversion forces review via an explicit override in `service.applyConversion` (a MEDIUM downgrade would now still auto-complete). **Brand-image fallback** (`extractors/brandimage.go`): when no product image survives, `ImageURL` falls back to the site brand asset (apple-touch-icon → favicon → rejected og:image) on its own `FieldBrandImage` candidate — applied AFTER the verdict so it never forces review, never votes in consensus, and adds no `SourceName`. The `eval/` harness (`go test -tags eval`) asserts a <1% false-auto-complete ceiling.
- `uploads/` — authenticated image upload endpoints backed by **native GCS** (`storage.GCSUploader`, ADC). Bucket is uniform-access + public-read; objects are served directly from GCS (`https://storage.googleapis.com/<bucket>/<key>`), no read proxy. Keys are unguessable 16-byte hex (via the shared `platform/randhex` helper, also used by auth/wishlists tokens). Local dev can point the Go SDK at a fake-gcs-server via `STORAGE_EMULATOR_HOST`. When `UPLOADS_ENABLED` but the uploader can't be built (empty bucket / broken ADC) the api **fails boot** (no silent fallback — uploads have none). `GCSUploader.Close` and the Cloud Tasks dispatcher are closed on graceful shutdown via the cleanup `registerDBRoutes` returns.
- `applinks/` — Android App Links + iOS Universal Links
- `health/` — health check endpoint

Each feature follows: `domain/` → `ports/` → `application/` → `adapters/`

Cross-cutting concerns in `internal/platform/`: config, HTTP server, DB connection, logger, authctx context helpers, storage.

**`SERVICE_ROLE`** (read in `config.go`, branched in `cmd/api/main.go`) selects which slice of the one binary runs. Cloud Run scale-to-zero kills background goroutines, so all periodic work is externally triggered in prod (ADR-0003):

| Role | Host | Chromium | Work |
|------|------|----------|------|
| `all` (default) | local docker-compose / tests | yes | every route + all 3 in-process loops + boot-migrate |
| `api` | `wishiz-api` service | no | applinks, health, auth, wishlists, uploads, discover read routes, import enqueue (+ Cloud Tasks dispatch), `POST /internal/maintenance`. No scrape engine, no loops |
| `scraper` | `wishiz-scraper` service | yes | health, scrape engine + `GET /scrape`, `POST /internal/imports/{id}/process` (live), `POST /internal/discover/products` (seed). No loops |
| `migrate` | `wishiz-migrate` Job | no | `ConnectSimple` (simple protocol over the pooler) → `RunMigrations` → exit |
| `discover-batch` | `wishiz-discover-batch` Job | yes | engine (no ZenRows) → `SitemapWorker.Refresh` → exit |
| `import-drain` | `wishiz-import-drain` Job | yes | engine → `Service.DrainPending` → exit |

Images: `Dockerfile.api` (slim) → `api`+`migrate`; `Dockerfile.scraper` (Chromium) → `scraper`+`discover-batch`+`import-drain`; `Dockerfile` → local `all`.

**Startup sequence** (`cmd/api/main.go`): config → logger → `migrate` role returns early (`runMigrate`) → tuned DB pool (when `DATABASE_URL` set; boot-migrate only in `all`) → scrape engine for scrape-capable roles (`setupScrape`; exchange refresh is per-role — `discover-batch` skips it (never converts), the short-lived `import-drain` Job warms rates **synchronously** before draining so its imports don't race a cold cache, long-lived `all`/`scraper` refresh async on cold start; the refresh ticker `Start` runs only in `all`) → `discover-batch`/`import-drain` roles run their task and exit → otherwise build the HTTP server: base routes always, scrape routes for scraper/all, DB-backed routes role-gated (`registerDBRoutes`), in-process loops only in `all` → serve on `HTTP_ADDR` (overridden by `PORT` when Cloud Run injects it) → graceful shutdown (10s).

The **DB pool** (`db.Connect`) is tuned for the Supabase transaction pooler: `QueryExecModeExec` with statement/description caches disabled (PgBouncer-safe), `MinConns=0`, `MaxConns=DB_MAX_CONNS`. No-arg `Exec` still uses the simple protocol, so multi-statement migrations work through it.

The **maintenance worker** (`internal/platform/maintenance`) deletes expired `app_sessions` and expired/unaccepted `wishlist_invites` — rows nothing else removes once they lapse — and, when the DB is up (`WithDiscoverSweeper`), sweeps TTL-expired and over-cap `discover_products`. The ticker (`CLEANUP_INTERVAL`, default 1h) runs only in the `all` role; in prod it is driven by `POST /internal/maintenance` (api role, hourly Cloud Scheduler) calling `Worker.Sweep`, which now **returns an error** (ctx-cancel/shutdown excluded) so the route returns 500 on a genuine sweep failure instead of a misleading 200.

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

Migrations apply via the **pre-deploy `migrate` Cloud Run Job** in prod (`ConnectSimple` → `RunMigrations`, simple-query-protocol over the transaction pooler so multi-statement DDL works PgBouncer-safe); boot-migrate (`RUN_DB_MIGRATIONS=true`) runs only in the single-instance `all` role. `RunMigrations` takes a minimal `Execer` interface so both `*pgxpool.Pool` and `*pgx.Conn` drive it.

Core tables: `app_users`, `app_sessions`, `wishlists`, `wishlist_items`, `wishlist_members`, `wishlist_invites`. All have TIMESTAMPTZ timestamps with auto `updated_at` trigger. `wishlist_items` keeps both the display `price_label` and structured `price_amount`/`price_currency_code` (written at import time from the scraper, preserved on item edits).

Full schema: `docs/postgres_schema.md`.

## Key Config (Environment Variables)

| Var | Default | Notes |
|-----|---------|-------|
| `DATABASE_URL` | — | Required in prod (Supabase pooler, port 6543) |
| `SERVICE_ROLE` | `all` | `all`/`api`/`scraper`/`migrate`/`discover-batch`/`import-drain` |
| `APP_ENV` | `development` | |
| `HTTP_ADDR` | `:8080` | `PORT` (Cloud Run) overrides it |
| `PORT` | — | Cloud Run-injected; takes precedence over `HTTP_ADDR` |
| `DB_MAX_CONNS` | `5` | Pool size/instance; keep Σ(instances × this) under pooler cap |
| `RUN_DB_MIGRATIONS` | `false` | Boot-migrate; honored only in `all` (prod uses the migrate Job) |
| `UPLOADS_ENABLED` | `false` | Enable GCS-backed upload routes (api role) |
| `BUCKET_NAME` | `""` | GCS upload bucket |
| `GCS_PUBLIC_BASE_URL` | `https://storage.googleapis.com` | Public object URL base |
| `IMPORT_TASKS_QUEUE` | `""` | Full Cloud Tasks queue path; with `SCRAPER_URL` enables live dispatch |
| `SCRAPER_URL` | `""` | Scraper service base URL (Cloud Tasks target) |
| `SCRAPER_AUDIENCE` | =`SCRAPER_URL` | OIDC token audience for the live-import task |
| `SCRAPER_INVOKER_SA` | `""` | SA email Cloud Tasks mints the OIDC token as. **Required** when live dispatch is enabled (`IMPORT_TASKS_QUEUE`+`SCRAPER_URL` set) — empty → api fails boot |
| `IMPORT_DRAIN_LIMIT` | `20` | Max jobs the `import-drain` Job processes per run |
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
