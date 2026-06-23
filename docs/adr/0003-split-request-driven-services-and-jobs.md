# Split into request-driven api + scraper services with scheduled Cloud Run Jobs

## Status

accepted (scheduled-Jobs topology + maintenance endpoint superseded by ADR-0004:
`discover-batch` + `import-drain` Jobs and `POST /internal/maintenance` are
consolidated into one weekly `weekly-batch` Job)

## Decision

The single Go binary (`cmd/api`) keeps starting everything in-process for local
dev (`SERVICE_ROLE=all`), but in production it is deployed several ways, selected
by `SERVICE_ROLE` and branched in `cmd/api/main.go`. Cloud Run scale-to-zero kills
background goroutines, so every periodic loop becomes externally triggered.

**Roles** (one binary, six wirings):

| Role | Host | Chromium | Work |
|------|------|----------|------|
| `all` | local / tests | yes | every route + all 3 in-process loops + boot-migrate |
| `api` | `wishiz-api` service | no | applinks, health, auth, wishlists, uploads, discover read routes, import enqueue (+ Cloud Tasks dispatch), `POST /internal/maintenance` |
| `scraper` | `wishiz-scraper` service | yes | health, scrape engine + `GET /scrape`, `POST /internal/imports/{id}/process` (live import), `POST /internal/discover/products` (seed) |
| `migrate` | `wishiz-migrate` Job | no | connect (simple protocol) → `RunMigrations` → exit |
| `discover-batch` | `wishiz-discover-batch` Job | yes | build engine (no ZenRows) → `SitemapWorker.Refresh` → exit |
| `import-drain` | `wishiz-import-drain` Job | yes | build engine → `Service.DrainPending` → exit |

Two images: `Dockerfile.api` (slim) runs `api` + `migrate`; `Dockerfile.scraper`
(Chromium) runs `scraper` + `discover-batch` + `import-drain`. `Dockerfile` builds
the local `all` monolith.

**Migrations run as a pre-deploy Job**, never on the boot path of a deployed
service. A multi-instance service migrating on boot races (`RunMigrations` has no
advisory lock); a single run-to-completion Job removes the race entirely. The Job
connects over the same transaction pooler (port 6543) in **simple-query-protocol**
mode (`ConnectSimple`), which is both PgBouncer-safe AND supports the
multi-statement DDL in the migration files. One `DATABASE_URL` secret; no separate
direct-connection secret.

**The runtime pool is tuned for the Supabase transaction pooler**
(Supavisor / PgBouncer transaction mode): `QueryExecModeExec` (unnamed
extended-protocol statements) with both statement and description caches disabled,
so a server-side prepared statement is never reused across the wrong pooled
connection. `MinConns=0` for scale-to-zero; `MaxConns=DB_MAX_CONNS` bounded so
`Σ(instances × DB_MAX_CONNS)` stays under the pooler's client cap. (No-argument
`Exec` still falls back to the simple protocol inside pgx, so the all-role
boot-migrate keeps working through this pool.)

**Live imports dispatch via Cloud Tasks.** The api enqueues the job (fast DB
write) and creates a Cloud Task targeting
`<SCRAPER_URL>/internal/imports/{id}/process` with an OIDC token; the user's
request returns immediately. The scraper processes the scrape in-request (Cloud
Run gives CPU for the request lifetime) and returns 2xx only after the outcome
persists — a non-2xx/timeout makes Cloud Tasks retry. `ClaimByID` claims the one
job atomically (`SELECT … FOR UPDATE SKIP LOCKED`); a redelivery of an
already-claimed/terminal job is an idempotent no-op. Task-create failure does not
fail the enqueue: the **hourly `import-drain` Job** recovers undispatched or
stuck jobs (`DrainPending` reuses `ProcessNext`'s `RecoverStuck` + `ClaimNext`).

**Periodic work becomes scheduled triggers:** discover refresh → weekly
`discover-batch` Job (TTL is 720h ≫ 7d, so nothing expires between runs);
maintenance sweep → `POST /internal/maintenance` on api, hourly Cloud Scheduler.
The in-process tickers (product-import poller, discover sitemap, maintenance) and
the exchange-rate refresh ticker start **only in the all role**. Scrape-capable
roles still fire one async exchange-rate refresh on cold start (a sync fetch would
block cold start → block the triggering import; a failed conversion forces review
downstream, covering the gap).

**The api mints no tokens.** Cloud Tasks mints the OIDC token for the live-import
task; Cloud Scheduler mints it for the maintenance endpoint and to execute the
Jobs. OIDC audience = the target service URL.

**Storage is native GCS, not S3.** Uploaded images go to a bucket with uniform
bucket-level access and a public `allUsers:objectViewer` binding, served directly
from GCS — the `/storage/{key}` read proxy is deleted. Keys are unguessable
16-byte hex; that, not per-object ACLs, is the access control. The AWS SDK is
dropped.

## Context

Infra (GCP Cloud Run + Supabase) was provisioned ahead of the code. The API was a
single binary that started the product-import poller, the discover sitemap worker
(24h ticker), and the maintenance worker (1h ticker) in-process. On Cloud Run with
scale-to-zero those goroutines die when the instance idles out, so none of the
periodic work would run reliably. The runtime also used pgxpool defaults (prepared
statement caching on), which breaks under PgBouncer transaction mode. Storage was
AWS S3.

A review of the first plan raised five points, all folded in: the migration race
(→ migrate Job), a sync exchange-rate regression (→ kept async), the migrate
connection protocol (→ simple-mode over 6543, single secret), live-import
idempotency (→ atomic `ClaimByID`), and a stale "api mints ID tokens" claim
(→ api mints nothing).

## Consequences

- Two services + three Jobs to deploy instead of one container; deploy order is
  push images → run `wishiz-migrate` → deploy `wishiz-api` + `wishiz-scraper`
  (both with `RUN_DB_MIGRATIONS=false`).
- Disabling discover or the drain backstop is operational (stop the Scheduler),
  not a code change.
- Local dev is unchanged: `SERVICE_ROLE=all` via docker-compose keeps the
  monolith, the in-process poller drains imports (no Cloud Tasks), and uploads are
  off by default (no GCS needed to run).
- A long-lived `scraper`/`api` instance does not refresh exchange rates on a timer;
  Cloud Run recycling refreshes them per cold start, and conversion failure forces
  human review, so a stale rate never silently mis-prices.
- Public GCS objects are world-readable by URL; acceptable because they are only
  wishlist/product imagery behind unguessable keys.
