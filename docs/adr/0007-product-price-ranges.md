# Store and display product price ranges

## Status

accepted

## Decision

A configurable product whose price is a **range** (e.g. West Elm "Cozy Swivel Chair", $579 – $1,598) is imported, stored, and displayed as a range instead of dead-ending in `needs_review` or being flattened to a misleading single "$579".

- **The low bound votes; the high bound rides along.** Consensus must stay single-valued — feeding it two trusted-tier amounts that disagree deadlocks price into `price_conflict` → `needs_review` (the exact failure this fixes). So `aggregatePriceRange` emits ONE price candidate (the low/"starting" bound) and carries the high bound out-of-band on that candidate's new `Candidate.AmountMax`. The engine copies the winning candidate's `AmountMax` onto `Product.PriceAmountMax` AFTER reconcile. A range therefore appears only when the *winning* price is itself a range — correct by construction, no new `SourceName`, no trust-matrix change.
- **Both bounds are converted, together.** `applyConversion` converts the low and the high with the same from/to currencies. If only the high fails to convert, the high is dropped (show the converted low as a single price) rather than failing the item; a low-bound failure keeps the existing force-review behavior.
- **Structured numeric contract, label is the fallback.** The job DTO and the item DTO expose `priceAmount` + `priceAmountMax` + `priceCurrencyCode`; the mobile client formats and converts from those numbers. `price_label` stays as a `"<CUR> <low> – <high>"` display fallback for older clients / web. New nullable columns `wishlist_items.price_amount_max` and `product_import_jobs.{price_amount, price_amount_max, price_currency_code}` (migration `000004`).
- **Editing collapses a range to a fixed price.** Editing the price label of a range item **clears** `price_amount` and `price_amount_max` (keeping `price_currency_code`). This intentionally relaxes the prior rule that structured price is an immutable import-time snapshot (`UpdateItemParams` previously omitted the amount columns). The entered label is no longer the import-time range, so the item falls back to the scalar label path.
- **Mobile consumes structured numbers only when a high bound is present.** Single-price items keep the existing `price_label` path untouched (lowest regression risk); only a range (`priceAmountMax != null`) reads the structured fields, for display, sorting, and totals.

## Context

The Williams-Sonoma family (West Elm, Pottery Barn, williams-sonoma, PBteen/PBkids, Rejuvenation, Mark&Graham) ships no Product JSON-LD and no `og:price`; the price lives only in `window.__INITIAL_STATE__.…aggregatePrice.{low,high}SellingPrice` as a range. A prior fix taught `aggregatePriceRange` to read these and emit the low bound so the item auto-completes — but it discarded the high bound, and the whole stack treated price as one opaque string, so a $579 – $1,598 chair imported as a bare "$579" with no signal it was a range.

The product wanted: import with zero friction (still auto-completes), show the honest range converted to the viewing user's currency on both bounds, and let the user one-tap edit to their chosen variant.

## Considered options

- **Encode the range in the `price_label` string** (`"$579 – $1,598"`) and parse it on the client. Rejected: every consumer (sort, totals, currency conversion) would need range-aware string parsing; the existing sort already mis-parses a range label by concatenating its digits (5791598). Numbers are unambiguous.
- **Emit both bounds into price consensus.** Rejected: two trusted-tier amounts that disagree deadlock into `price_conflict` → `needs_review`, which is the failure being fixed.
- **Keep the import-time-snapshot rule and never let edits touch structured price.** Rejected: an edited range item would keep a stale `price_amount_max` and keep rendering a range with a label the user changed.

## Consequences

- Range-priced items from no-JSON-LD commerce sites reach `auto_complete` AND display honestly.
- The schema + DTO contract gains three nullable columns and three response fields; additive and backward compatible (old rows / old clients see `null` max → single price).
- The "structured price is import-time-only" invariant is relaxed: a human price edit clears the structured amounts. Documented here because it is hard to reverse and surprising without context.
- Only the low/"starting at" amount is the canonical single value; a true range *display* on the editor or in analytics beyond the queue tile / list is out of scope. Discover-card ranges and JSON-LD `AggregateOffer.highPrice` max capture are left as follow-ups.
