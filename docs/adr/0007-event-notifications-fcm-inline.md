# Event-driven notifications: durable inbox + request-path FCM push

## Status

accepted (relates to [ADR-0003](0003-split-request-driven-services-and-jobs.md))

## Decision

Replace the client-only "reminder" notion of notifications with a real, event-driven
notification system: a durable inbox row (source of truth) plus a best-effort OS push (FCM),
sent **from the request path** — no Cloud Tasks. Specifics:

- **Events only, four types.** `list_member_joined`, `item_added`, `item_purchased`,
  `import_settled`. Each is emitted synchronously during the originating HTTP request (the
  server is awake then), via a single `NotifyService` attached to the wishlists + productimports
  services through a nil-safe `WithNotifier` (structural local `Notifier` interfaces — no import
  cycle). The old time-based aging reminder is **retained as a separate, client-computed
  surface** (it does not persist rows and does not drive the badge).

- **Durable row is the source of truth; push is advisory.** `emit` resolves gating (master
  toggle + per-list mute) → drops master-OFF recipients (no row) → batch-inserts rows
  (muted recipients get `read_at = created_at`) → pushes the unmuted recipients' tokens. The
  badge is the count of rows with `read_at IS NULL`. A dropped/delayed push never corrupts the
  inbox or badge.

- **Push sent from the request path, no Cloud Tasks.** In the user-facing `api`/`all` roles the
  push runs on a **detached goroutine** (`context.WithoutCancel` + timeout — mirrors
  `importdispatch`); in the background `scraper`/`weekly-batch` roles it runs **inline** (no
  human is waiting, and a detached goroutine could be frozen after the 2xx under scale-to-zero).
  Cloud Tasks would be overkill for an advisory nudge whose durable row already guarantees
  correctness.

- **Void-and-swallow failure isolation.** `Notifier`/`Pusher` methods are void. `NotifyService`
  logs and swallows every insert/push error; a notification failure can never roll back or fail
  the user's AddItem/PatchItem/Join/processClaimed. Cost: one batched INSERT round-trip on the
  request critical path (accepted).

- **Master toggle reuses `app_users.notifications_enabled`, with asymmetric semantics.**
  Master OFF ⇒ **no row at all** for that recipient ("the feature is dark"). Per-list **Mute** ⇒
  a row IS written but already-read (silent-but-visible: in inbox history, never badges/pushes).
  Mute is skipped for `import_settled` (the importer's own action).

- **Standalone `notification_mutes` table.** Mute is per-(user, wishlist) and cannot live on the
  membership row, because the **owner has no `wishlist_members` row** (ownership lives only on
  `wishlists.owner_id`).

- **`item_purchased` notifies the owner too — deliberate.** Wishiz lists are collaborative, not
  surprise-gift lists. Hiding purchases from the owner to "preserve the gift surprise" is
  explicitly out of scope (documented so it is not re-flagged as a spoiler bug).

- **Schema arrives in its own migration.** `notifications`, `device_tokens`,
  `notification_mutes` are added in `000003_notifications.up.sql` (not edited into the launched
  `000001`), because the app now has real users: an applied migration never re-runs. The
  4-value `type` CHECK is drift-tested against `domain.AllTypes()` (mirrors the `price_source`
  drift test).

## Context

The previous "notifications" feature was a misnomer: `home_screen.dart` computed a count of
aging saved items client-side, painted it on the bell, and showed a SnackBar. There was no list
of what triggered it, no read-state, no way to clear it, and no OS push. The backend had unused
`notifications_enabled`/`reminder_days` columns and zero notification/event/device-token
infrastructure.

The goal was a real notification system — persisted inbox + OS push, with read-state, a
clearable unread badge, and per-list control — while keeping the aging reminder as a secondary
surface. Under scale-to-zero (ADR-0003) background goroutines die when an instance is reaped, so
all *periodic* work is externally triggered; but these events are *request-driven* (a user just
acted), so emitting inline is safe. Only the push itself is best-effort post-response — hence
the durable row as source of truth.

## Consequences

- The inbox/badge are always exact; the OS banner is the only best-effort part.
- **Upgrade lever for push reliability:** run the `api` service with CPU-always-allocated
  (`--no-cpu-throttling`) or `min-instances=1` so the post-response detached push reliably gets
  CPU. `import_settled` (inline in the scraper) is already reliable.
- `NotificationsEnabled` is read directly from `app_users` by the notifications repo to keep the
  module self-contained (a deliberate cross-feature table read, not a port dependency).
- FCM delivery (the `Pusher` adapter, config, and SA IAM) is a follow-up phase; with `Pusher`
  nil the inbox/badge/mute all work end-to-end without Firebase.
- Known debt: notification title/body are composed server-side in English — fine while the app
  is English-only; revisit (client-side templating from type+payload, or `Accept-Language`) when
  localizing.
