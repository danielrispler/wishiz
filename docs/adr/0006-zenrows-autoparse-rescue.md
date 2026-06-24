# ZenRows autoparse rescue: structured-product JSON for Amazon imports

## Status

accepted (supersedes-in-part [ADR-0002](0002-zenrows-paid-backstop.md))

## Decision

The paid ZenRows backstop gains a second mode. For **Amazon** hosts it fetches ZenRows'
**autoparse** structured-product JSON and maps it directly to candidates; every other host
keeps the rendered-HTML pass from ADR-0002. Specifics:

- **Autoparse IS a source.** Unlike the HTML backstop (a transport whose HTML is re-run through
  the existing extractors), autoparse JSON is mapped by a dedicated extractor
  (`extractors.MapAutoparseProduct`) into candidates that carry a NEW `SourceName`,
  `zenrows_autoparse`. It is `tierAuthoritative` for name/price/image. The `price_source` CHECK
  in `000001_init_wishlists.up.sql` is widened to include it (drift test enforces).
- **Amazon-only gate, including shorteners.** The autoparse pass fires when the page host is a
  known Amazon host — a marketplace domain (`amazon.<tld>`, with `www.`/`smile.` subdomains) or
  a shortener (`a.co`, `amzn.to`, `amzn.eu`, `amzn.asia`, `amzn.com`). `extractors.IsAmazonHost`.
  The shortener arm is essential: the Amazon **app** share sheet emits `a.co/d/…` links, and
  `NormalizeProductURL` does not resolve them, so the pre-fetch host is `a.co`, not the real
  marketplace.
- **Currency from the RESOLVED final-URL host.** Autoparse returns a bare `"$179.00"`-style
  price with no currency code; a bare `$` is intentionally unresolvable (the SAFE currency
  policy). We assign an EXPLICIT currency from the ZenRows final URL host (`Zr-Final-Url`, e.g.
  `amazon.de`→EUR) via `AmazonMarketplaceCurrency`. An unknown/non-marketplace resolved host
  yields **no** currency → the import falls to `needs_review` rather than guessing.
- **Price-sanity guard.** Autoparse's `price` field is observed to sometimes report a
  bundled/accessory price rather than the buy-box price (see Context). The mapper drops the
  price candidate (→ `needs_review`, name+image still prefilled) when the price has no parseable
  amount, or when it is below **half** of autoparse's own `price_without_discount` (a >50% cut —
  the discount text is too messy to parse reliably). This converts the dangerous case (a silent
  wrong price auto-completing) into a safe one (the user confirms).
- **HTML fallback.** When autoparse errors or maps no candidates (schema drift), the backstop
  falls through to the rendered-HTML pass from ADR-0002 under the same backstop-timeout budget.
- **Verdict-floor guard preserved.** The autoparse re-reconcile replaces the own product only
  when it does not lower the verdict (ADR-0002's invariant, unchanged).
- **Import path only, presence-gated, soft-fail.** All of ADR-0002 still holds: autoparse fires
  only via `Service.ScrapeImport`, only when `ZENROWS_API_KEY` is set, and any error soft-fails
  (logged, never retried — ADR-0001).

## Context

Sharing an item from the **Amazon app** produced a `needs_review` import with a junk title and
no price/image. Proven (prod logs + ZenRows MCP replay) the cause is not the share link, the
shortener, anti-bot, or app-vs-website: the app shares an `a.co/d/…` link that resolves to the
*same* product page as a website share. The HTML backstop already fetches Amazon fine (HTTP
200) but Amazon serves **no JSON-LD and no `og:` tags** and ~38 ambiguous `.a-offscreen`
prices, so our generic extractors find no trusted price → `needs_review` with a junk `<title>`.
The same ZenRows call with `autoparse=true` returns clean structured product JSON we were
already paying for and discarding.

Autoparse's `price` is the weak link. Replaying two prod ASINs: Redken reported `$23.80`
(correct, buy-box) but Bose reported `$26.99` while the real buy-box was ~$179 — autoparse's own
`price_without_discount=$269` + `discount=-33%` imply ~$180, so its `price` field was internally
inconsistent (it had latched a bundled/accessory price). Auto-completing that would silently
write a wrong price to the user's wishlist. Hence the price-sanity guard: the price must be safe
to auto-complete or it falls to human review.

`a.co` hides the marketplace until fetch time, which forces the split: the **gate** keys on the
shortener set (pre-fetch), the **currency** keys on the resolved final-URL host (post-fetch).

## Considered options

- **Amazon buy-box `css_extractor` for price instead of autoparse.** Rejected for v1: autoparse
  gives title + image + price in one document with no per-site selector maintenance; the
  price-sanity guard makes its unreliable price safe (drops to review rather than mis-completing).
  The `css_extractor` remains the lever if too many Amazon items land in review.
- **Resolve `a.co` in `NormalizeProductURL` so the existing HTML path handles it.** Rejected:
  resolving the shortener does not help — the resolved Amazon HTML still has no JSON-LD/og, so
  the HTML path still fails. The problem is Amazon's markup, not the link.
- **Treat autoparse as a transport (no new SourceName), like the HTML backstop.** Rejected:
  autoparse output is structured JSON, not HTML; there is nothing for the HTML extractors to run
  over. A dedicated mapper + source name is the honest model and keeps the trust matrix explicit.
- **Guess USD for unknown hosts.** Rejected: matches the SAFE currency policy — never fabricate a
  currency; fall to review.
- **Infer the discount threshold from `discount`.** Rejected: the discount string is inconsistent
  and locale-formatted; the `price_without_discount` ratio is a simpler, robust sanity bound
  (mirrors `SCRAPE_MAX_PRICE`).

## Consequences

- Amazon imports (website and app `a.co` shares) reach `auto_complete` with a real
  title/price/currency/image when the price is plausible, and `needs_review` (title+image
  prefilled) when it is suspicious — instead of always landing in junk `needs_review`.
- One new `price_source` value, `zenrows_autoparse`, now appears on Amazon import rows.
- Worst case an Amazon import makes two paid ZenRows calls (autoparse then HTML fallback) when
  autoparse errors or maps nothing — rare; the HTML pass rarely rescues Amazon but is the
  documented safety net.
- **Open item:** confirm whether `autoparse=true` adds any surcharge over
  `js_render`+`premium_proxy` by reading `X-Request-Cost` on a live autoparse call
  (`TestZenRowsAutoparseLive` logs it). If it does, weigh it against the rescue value.
