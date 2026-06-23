# Consolidate scheduled Jobs into one weekly batch; drop import-drain and the maintenance endpoint

## Status

accepted (supersedes the Jobs topology + maintenance-endpoint parts of ADR-0003)

## Decision

Pre-launch (0 users), the six-role split from ADR-0003 is collapsed to **four
production roles** plus `all` for local/test. The two hourly cadences and the
`POST /internal/maintenance` endpoint are removed; their work moves into a single
weekly Cloud Run Job.

**Roles** (one binary, five wirings):

| Role | Host | Chromium | Work |
|------|------|----------|------|
| `all` | local / tests | yes | every route + all 3 in-process loops + boot-migrate |
| `api` | `wishiz-api` service | no | applinks, health, auth, wishlists, uploads, discover read routes, import enqueue (+ Cloud Tasks dispatch). **No maintenance endpoint.** |
| `scraper` | `wishiz-scraper` service | yes | health, scrape engine + `GET /scrape`, `POST /internal/imports/{id}/process` (live import), `POST /internal/discover/products` (seed) |
| `migrate` | `wishiz-migrate` Job | no | connect (simple protocol) → `RunMigrations` → exit |
| `weekly-batch` | `wishiz-weekly-batch` Job | yes | maintenance `Sweep` → `SitemapWorker.Refresh` (crawl) → `Service.DrainPending` (import recovery) → exit |

`weekly-batch` reuses the Chromium `Dockerfile.scraper` image; `migrate` reuses the
slim `Dockerfile.api` image. Two images, unchanged from ADR-0003.

**The weekly Job runs three independent steps in sequence** (`runWeeklyBatch`). They
do not gate each other — a maintenance failure must not skip the crawl or the
drain. The Job aggregates the steps' errors (`errors.Join`) and **exits non-zero if
any reporting step failed**, so a bad run is visible as a failed Cloud Run Job
execution. The crawl step uses `Scrape` (never the paid ZenRows backstop); the
drain step uses `ScrapeImport` (backstop wired when `ZENROWS_API_KEY` is present)
and converts currency, so the Job **warms the ECB rate cache synchronously** at
startup before draining.

**Import recovery is now weekly, not hourly.** Cloud Tasks' own retries plus
`ReleaseToPending` (a settle-failure reverts the row to `pending` for the next
prompt retry) cover the common transient cases sooner; only a job whose Cloud Task
was never created or exhausted its retries waits for the weekly drain.

**Maintenance has no HTTP surface.** The sweep runs in-process (all-role ticker) and
as the weekly Job's first step. `Worker.Sweep` still returns an error so the Job can
fold it into its exit code.

## Context

ADR-0003 provisioned a request-driven split sized for production traffic: separate
`discover-batch` (weekly) and `import-drain` (hourly) Jobs, plus an hourly
`POST /internal/maintenance` endpoint driven by Cloud Scheduler. None of it had
been deployed. With no users yet, three scheduled triggers + a dedicated import
recovery Job is more operational surface than the stage warrants. Consolidating to
one weekly Job cuts the Cloud Scheduler triggers from three to one and removes a
role, an endpoint, and a Job from the deploy.

## Consequences

- Deploy is two services + two Jobs (`migrate`, `weekly-batch`) and **one** weekly
  Cloud Scheduler trigger, down from three Jobs + three triggers.
- **Reduced import durability**: a job whose Cloud Task never created (e.g. Tasks
  API hiccup at enqueue) or exhausted Cloud Tasks retries is not recovered until the
  next weekly run — up to ~7 days. Accepted pre-launch; revisit (re-add an
  hourly/short-interval drain) when import volume justifies it.
- Local dev is unchanged: `SERVICE_ROLE=all` keeps the monolith with all in-process
  loops; the in-process poller still drains imports immediately.
- ADR-0003 remains the record for the service split, Supabase pooler tuning, Cloud
  Tasks live dispatch, migrate-as-Job, and native GCS — only its scheduled-Jobs
  topology and maintenance endpoint are superseded here.
