# ZenRows paid backstop: a last-resort second pass for blocked imports

## Status

accepted

## Decision

When the own scrape pipeline cannot reach `auto_complete`, the product-import path makes ONE
paid ZenRows Universal Scraper API fetch (residential proxy + headless render) as a last
resort, folds its rendered HTML through the existing extractor → consensus → verdict pipeline,
and re-reconciles. Specifics:

- **Transport, not a source.** ZenRows returns rendered HTML through the same `FetchResult` →
  `Engine.Extract` path as every other fetcher. Candidates keep their natural source names
  (`json_ld`, `open_graph`, …). No new `SourceName`, no `price_source` migration, no drift /
  trust-matrix change.
- **Fire-on-miss, second pass.** It runs only when the own pipeline's pre-conversion verdict is
  not `auto_complete` (covers both `needs_review` and `failed`). Running ZenRows concurrently
  on every scrape would bill every import; a fallback only pays when the cheap pipeline misses.
- **Import path only.** Exposed as `Service.ScrapeImport`, called solely by the async import
  worker. `Scrape` (discover, synchronous `/scrape` route) and `ScrapeWithProgress` never fire
  the backstop. One `Service` instance is shared, so the global headless-render semaphore still
  bounds memory across all callers.
- **Presence-gated.** Active iff `ZENROWS_API_KEY` is set (mirrors the conditional Shopify
  probe). Unset → `backstop == nil` → behaviour identical to before.
- **Full power.** `js_render=true` + `premium_proxy=true` (ZenRows 25× credit cost) — justified
  because it only fires as a last resort.
- **Verdict-floor guard.** The re-reconcile result replaces the own product only when
  `verdictRank(new) >= verdictRank(own)` (`auto_complete > needs_review > failed`). The backstop
  can only RAISE or HOLD the verdict, never lower it.
- **ccTLD proxy-country pin.** The residential exit is pinned to the site's ccTLD
  (`inferProxyCountry`: `.de`→`de`, `.co.uk`→`gb`, …); generic `.com`/`.net`/`.org` and
  multi-country `.eu` are left unpinned.
- **Separate timeout.** `ZENROWS_TIMEOUT` (default 30s) is applied ON TOP of `SCRAPE_BUDGET`,
  derived from the inbound context (not the budget context), so a 30s scrape + 30s backstop is
  a ~60s worst case per job. Safe because the import worker passes an undeadlined root context.
- **Soft-fail, no retry.** Any ZenRows error (402 no-credits / 429 concurrency / 422 / 5xx /
  timeout) is logged and the own-pipeline product is returned unchanged. A settled job re-enters
  the queue only via user Retry (ADR-0001).

## Context

The static fetcher's full Chrome fingerprint defeats naive + fingerprint anti-bot, but not
JS-challenge / datacenter-IP-reputation blocks (Cloudflare challenge, DataDome, Akamai,
PerimeterX). CLAUDE.md had named this gap explicitly — aritzia / crate&barrel "still need a
residential proxy / paid backstop — deferred." This ADR realizes that backstop.

A code review of the first draft flagged a geo-pricing risk: a residential exit serves
localized currency, which could conflict with the own price. The draft assumed re-reconcile
"can only improve." Two facts make degradation impossible in practice and the guard a cheap
guarantee regardless: (1) candidates are **append-only** — the backstop only adds evidence;
(2) a consensus **conflict keeps the field value**, flagging only confidence. So `isReviewable`
can never flip true→false by adding data: a `needs_review` can become `auto_complete` or stay
`needs_review`, but never drop to `failed`. The verdict-floor guard encodes this as an explicit
invariant that holds even if consensus later changes to drop conflicted values; the ccTLD pin
biases the exit toward the own pipeline's locale so the second pass resolves rather than
conflicts (fewer wasted 25× fetches).

## Considered options

- **Pin proxy geo only / accept-and-test / guard only.** Chosen: guard (correctness invariant)
  + ccTLD pin (fewer wasted credits) together — guard guarantees no regression, pin improves
  hit rate. Restricting backstop folding to MISSING/LOW fields was rejected: it breaks the clean
  "feed through the same extractors" reuse and special-cases consensus.
- **Fire only on `failed`** (skip `needs_review`). Rejected for v1: firing on `needs_review` can
  turn a reviewable into an `auto_complete` and save human review time. The lever remains if
  cost bites — at 25× credits per non-`auto_complete` job, switching to failed-only is the
  cheapest dial.
- **Second `Service` instance for discover (no backstop).** Rejected: each `NewService` builds
  its own render semaphore, so two instances would double the global headless-render cap (a
  memory-bound regression). An explicit `ScrapeImport` opt-in on one shared `Service` is cleaner.
- **9th positional `NewService` Fetcher param.** Rejected: the backstop + its timeout live in
  `ServiceConfig` (the signature already has two bare positional `Fetcher`s — no third).

## Consequences

- Imports of JS-challenge/datacenter-blocked stores can now reach `auto_complete` / `needs_review`
  instead of `failed`, at the cost of one 25× ZenRows call per non-`auto_complete` import job.
- Worst-case import latency rises to ~60s/job (budget + backstop), acceptable on the async queue.
- ZenRows account-level concurrency (5 simultaneous = worker count) can 429; that soft-fails and
  is logged as a rescue-miss so the miss rate is observable. No fleet cap pre-launch.
- The backstop cannot fix a missing ECB rate: currency-conversion review still happens downstream
  in `applyConversion`, after the second pass.
