# Wishiz — Domain Glossary

## External Share
A product URL shared into the app from another app (e.g. Safari, Chrome) via the iOS/Android share sheet. Always a product URL — wishlist invite deep links are handled separately and are not considered an External Share. The native share queue may hold multiple items simultaneously; they are consumed one at a time.

**Avoid:** "shared text", "pending text" (implementation terms — use "External Share" in domain discussion)

---

## Import Job
An async job that scrapes a product URL and produces a `ProductImportJob` with extracted title, price, and image. Import Jobs are queued, polled, and may require user review (`needs_review` status) before the item is saved to a wishlist.

The worker only picks up jobs that are waiting to be scraped (`pending`). An Import Job that has settled into `needs_review` or `failed` is **terminal** — the worker never re-scrapes it on its own. It re-enters the queue solely through an explicit user **Retry**, which returns it to `pending`. See [ADR-0001](docs/adr/0001-import-jobs-no-auto-retry.md).

**Retry:** A user-initiated action on a settled (`needs_review`/`failed`) Import Job that re-queues it for scraping. The only path back into the queue once a job has settled. Distinct from crash recovery, which only re-queues jobs that never finished (the worker died mid-scrape).

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

"Terminal" means the job stays put until the user acts — completed jobs await assignment to a list, and needs_review/failed jobs await an explicit user Retry. The `Retryable` flag gates *whether the user is offered* a Retry; it never triggers automatic re-scraping.

When a Job Outcome reaches a terminal status it also fires an **Import Settled Notification** to the importer (see Notification).

---

## Notification
A durable, event-driven inbox entry plus a best-effort OS push. It **supersedes the old "Reminder"** as the meaning of "notification": Reminders still exist (see below) but are a separate, client-computed surface and no longer drive the bell badge.

Four event types, each emitted synchronously during the originating HTTP request:
- **List Member Joined** — an invite was accepted → notify the list owner.
- **Item Added** — an item was added to a shared list → notify owner + members **except the actor**.
- **Item Purchased** — an item was marked purchased on a shared list → notify owner + members **except the actor**.
- **Import Settled** — an Import Job reached a terminal status → notify the importer only.

The persisted row is the **source of truth** for the in-app inbox and the unread badge (badge = count of rows with no `read_at`). The OS push (FCM) is **advisory**: under Cloud Run CPU throttling after the response, a detached push may be delayed or dropped, but the durable row keeps the inbox and badge exact.

Two confirmed product rules:
1. **Item Purchased notifies the owner too.** Wishiz lists are collaborative, not surprise-gift lists; hiding purchases from the owner "to preserve the gift surprise" is explicitly **out of scope**. (Documented so it is not re-flagged as a spoiler bug.)
2. **Master toggle OFF ⇒ no row at all** for that recipient (no inbox entry, no badge, no push — "the feature is dark"); **per-list Mute ⇒ a row is still written but already-read** (`read_at = created_at`): visible in inbox history, but it never badges and never pushes.

The master toggle reuses `app_users.notifications_enabled`; it governs both Notifications and Reminders.

**Avoid:** calling the time-based Reminder a "notification" — they are distinct surfaces.

---

## Reminder
A **client-computed**, ephemeral nudge about the user's own aging saved items (items waiting longer than `reminder_days`). Rendered in the Reminders section of the notifications screen and as an in-app prompt. Reminders are **not** persisted, have no read-state, and **do not** drive the bell badge (only Notifications do). Gated by the same master toggle (`notifications_enabled`) and by `reminder_days`.

---

## Notification Mute
A per-(user, wishlist) record that silences a list for one user. A muted list still produces Notification rows (so history stays complete), but those rows are inserted already-read — they never increment the badge and never push. Mute is **per-user**: it is stored standalone (not on the membership row) because the owner has no membership row. Mute does **not** apply to Import Settled (that notifies the importer about their own action).

---

## Device Token
An FCM registration token for one physical device, owned by a user. Registered after notification permission is granted (and on token refresh / authorized launch), de-registered on logout. A token that FCM reports as permanently invalid is pruned. Tokens are how an advisory OS push reaches a recipient; they are irrelevant to the durable inbox.
