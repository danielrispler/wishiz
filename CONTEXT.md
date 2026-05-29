# Wishiz — Domain Glossary

## External Share
A product URL shared into the app from another app (e.g. Safari, Chrome) via the iOS/Android share sheet. Always a product URL — wishlist invite deep links are handled separately and are not considered an External Share. The native share queue may hold multiple items simultaneously; they are consumed one at a time.

**Avoid:** "shared text", "pending text" (implementation terms — use "External Share" in domain discussion)

---

## Import Job
An async job that scrapes a product URL and produces a `ProductImportJob` with extracted title, price, and image. Import Jobs are queued, polled, and may require user review (`needs_review` status) before the item is saved to a wishlist.

---

## Shared Product Draft
A transient value object produced by the scraper representing partially or fully extracted product data (title, price, image URL, product URL). A Draft is **complete** when it has both a title and a price. Image is optional — a Draft without an image is still saveable.

**Note:** As of the resolution of Bug 2, `hasCompleteRequiredFields` requires title + price only. Image is explicitly optional.

---

## My Lists
Wishlists owned by the current user. Includes lists the user has shared with collaborators. Displayed in the "My Lists" tab.

---

## Shared Lists
Wishlists owned by another user that have been shared with the current user. The current user is a member but not the owner. Displayed in the "Shared Lists" tab. A list the user no longer has membership in does not appear anywhere.

**Key distinction:** A list the user owns and has shared with others is a "My List", not a "Shared List".

---

## Sort Criteria
An ordered sequence of `SortCriterion` values applied to wishlist items. Each criterion has a field (Rank, Price, Date Added) and a direction (ascending/descending). Items are sorted by the first criterion; ties are broken by the second, and so on. The default is `[Rank ascending]`.

**UI contract:** Tapping a selected sort chip toggles its direction. Long-pressing a selected sort chip removes it from the sequence. Tapping an unselected chip appends it to the end of the sequence.

---

## Rank
An integer sort order field on a WishlistItem representing the user's priority ordering. Lower rank value = higher priority (rank 1 = top of list). Distinct from "rating" — there is no rating concept in this domain.

---

## Job Outcome
The terminal result of processing an Import Job. Carries a ProductSnapshot (extracted title, price, image, completeness) plus a terminal status (completed, needs_review, or failed). For error statuses, also carries a LastError message, ErrorCode, and Retryable flag. For completed status, may carry a CreatedItemID if a wishlist item was auto-created.
