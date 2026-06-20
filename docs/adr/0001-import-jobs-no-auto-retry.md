# Import jobs do not auto-retry; needs_review/failed are user-gated terminal states

## Status

accepted

## Decision

The product-import worker auto-claims `pending` jobs only. Once a job settles into
`needs_review` or `failed`, it is terminal: the worker never re-scrapes it on its own. The
only path back into the queue is an explicit user **Retry**, which returns the job to
`pending`. (Crash recovery is separate — it re-queues only jobs that died mid-scrape, i.e.
still `processing` past their lease.)

## Context

The worker previously also re-claimed `needs_review` and `failed` jobs that were
`retryable`, after a backoff, up to a max attempt count. This silently re-scraped
"waiting to approve" (`needs_review`) items behind the user's back: it mutated the data
under them, burned scrape budget, and surfaced as "importing a new item re-scrapes the old
ones" (the mobile client only polls while jobs are active, so the background re-scrape
became visible the moment a new import woke the poller). It also contradicted
`domain.IsTerminalStatus`, which already classified these statuses as terminal.

## Considered options

- **Keep auto-retry.** Rejected: re-scraping user-gated items is the reported bug.
- **Auto-retry `failed` only** (keep `needs_review` user-gated). Rejected for simplicity and
  predictability — one rule ("worker scrapes pending only") is easier to reason about, and
  `failed` items already surface a Retry affordance.

## Consequences

- A transient scrape failure (e.g. a timeout) now stays `failed` until the user retries —
  there is no automatic self-heal. Accepted as the cost of never mutating settled,
  user-gated items and not spending scrape budget without user intent.
- The `Retryable` flag now only drives whether a Retry is *offered* (UI + the `Retry` SQL
  guard); it no longer triggers automatic re-claiming.
