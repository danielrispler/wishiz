# PostgreSQL Schema

Source of truth: the migration files in `apps/api/internal/platform/db/migrations/` —
`000001_init_wishlists` (launch schema), `000002` (widened `price_source` CHECK), and
`000003_notifications` (the `notifications`/`device_tokens`/`notification_mutes` tables).
Migrations are **append-only** (the app has real users): add a new `NNN_<name>.up.sql` per
change, never edit an applied migration or drop/recreate the prod DB. This doc mirrors those
files; each table below notes the migration that introduced it where it is not `000001`.

## Extensions

- `pgcrypto` for `gen_random_uuid()`
- `citext` for case-insensitive email columns

## Tables

### `schema_migrations`

The applied-migration ledger. Created by the migration runner
(`internal/platform/db/migrations.go`) before any migration file is applied — it is **not**
defined inside the migration SQL.

- `version TEXT PRIMARY KEY`
- `applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`

### `app_users`

- `id UUID PRIMARY KEY DEFAULT gen_random_uuid()`
- `email CITEXT NOT NULL UNIQUE`
- `full_name TEXT NOT NULL`
- `birthday DATE` — nullable since migration `000005` (Apple 5.1.1(v): not required at registration; still powers gifting reminders)
- `gender TEXT` — CHECK `gender IS NULL OR gender IN ('man', 'woman')` (the user's own gender)
- `password_hash TEXT NOT NULL`
- `preferred_currency_code TEXT NOT NULL DEFAULT 'USD'` — CHECK `~ '^[A-Z]{3}$'`
- `notifications_enabled BOOLEAN NOT NULL DEFAULT TRUE`
- `reminder_days INTEGER NOT NULL DEFAULT 14` — CHECK `BETWEEN 0 AND 365`
- `preferred_brands TEXT[] NOT NULL DEFAULT '{}'`
- `created_at` / `updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`

### `app_sessions`

- `id UUID PRIMARY KEY DEFAULT gen_random_uuid()`
- `user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE`
- `token_hash TEXT NOT NULL UNIQUE`
- `expires_at TIMESTAMPTZ NOT NULL`
- `last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`
- `created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`
- Indexes: `(user_id)`, `(expires_at)`

Expired rows are swept periodically by the maintenance worker (`internal/platform/maintenance`).

### `wishlists`

- `id UUID PRIMARY KEY DEFAULT gen_random_uuid()`
- `owner_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE`
- `title TEXT NOT NULL`
- `description TEXT NOT NULL DEFAULT ''`
- `year INTEGER NOT NULL` — CHECK `BETWEEN 2000 AND 2100`
- `cover_image_url TEXT`
- `share_token TEXT NOT NULL UNIQUE`
- `is_archived BOOLEAN NOT NULL DEFAULT FALSE`
- `created_at` / `updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`
- Index: `(owner_id)`

Owners are not duplicated in `wishlist_members`.

### `wishlist_items`

- `id UUID PRIMARY KEY DEFAULT gen_random_uuid()`
- `wishlist_id UUID NOT NULL REFERENCES wishlists(id) ON DELETE CASCADE`
- `title TEXT NOT NULL`
- `rank INTEGER NOT NULL` — CHECK `rank > 0`
- `notes TEXT`
- `price_label TEXT` — display string (e.g. `"USD 129.00"`, or `"USD 579 – 1598"` for a range)
- `price_amount NUMERIC(12,2)` — structured amount captured at import time (the low/"starting" bound of a range)
- `price_amount_max NUMERIC(12,2)` — high bound of a price range (`000004`); NULL for a scalar price
- `price_currency_code TEXT` — CHECK `IS NULL OR ~ '^[A-Z]{3}$'`
- `priority TEXT NOT NULL DEFAULT 'medium'` — CHECK `IN ('low','medium','high')`
- `status TEXT NOT NULL DEFAULT 'saved'` — CHECK `IN ('saved','considering','purchased')`
- `image_url TEXT`
- `product_url TEXT`
- `purchased_at TIMESTAMPTZ`
- `created_at` / `updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`
- `UNIQUE (wishlist_id, rank) DEFERRABLE INITIALLY IMMEDIATE`
- Index: `(wishlist_id)`

`price_amount` / `price_amount_max` / `price_currency_code` are written from the importer's
structured scrape result. Editing an item's price **clears** `price_amount`/`price_amount_max`
(keeping `price_currency_code`), collapsing a range item to a fixed price — see
[ADR-0007](adr/0007-product-price-ranges.md).

### `product_import_jobs`

- `id UUID PRIMARY KEY DEFAULT gen_random_uuid()`
- `user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE`
- `wishlist_id UUID REFERENCES wishlists(id) ON DELETE SET NULL`
- `client_request_id TEXT NOT NULL`
- `normalized_url TEXT NOT NULL`
- `domain TEXT NOT NULL`
- `target_currency_code TEXT NOT NULL DEFAULT 'USD'` — CHECK `~ '^[A-Z]{3}$'`
- `status TEXT NOT NULL DEFAULT 'pending'` — CHECK `IN ('pending','processing','completed','needs_review','failed')`
- `attempt_count INTEGER NOT NULL DEFAULT 0` — CHECK `>= 0`
- `last_attempted_at TIMESTAMPTZ`, `last_error TEXT`, `error_code TEXT` (free-form)
- `retryable BOOLEAN NOT NULL DEFAULT FALSE`
- `title TEXT`, `price_label TEXT`
- `price_amount NUMERIC(12,2)`, `price_amount_max NUMERIC(12,2)` — structured price / range high bound (`000004`)
- `price_currency_code TEXT` — CHECK `IS NULL OR ~ '^[A-Z]{3}$'` (`000004`)
- `price_confidence TEXT` — CHECK `IS NULL OR IN ('high','medium','low','suspicious')`
- `price_source TEXT` — CHECK `IS NULL OR IN ('merchant_selector','json_ld','meta','selector','generic_dom')`
- `price_warnings TEXT[] NOT NULL DEFAULT '{}'`
- `image_url TEXT`
- `completeness INTEGER NOT NULL DEFAULT 0` — CHECK `BETWEEN 0 AND 3`
- `progress_stage TEXT` (free-form), `progress_percent INTEGER NOT NULL DEFAULT 0` — CHECK `BETWEEN 0 AND 100`
- `created_item_id UUID REFERENCES wishlist_items(id) ON DELETE SET NULL`
- `acknowledged_at`, `locked_at`, `created_at`, `updated_at TIMESTAMPTZ`
- `UNIQUE (user_id, client_request_id)`
- Indexes:
  - `(user_id, status, updated_at DESC)`
  - `(user_id, created_at DESC)` — backs `List`
  - `(status, created_at) WHERE status IN ('pending','failed','needs_review')` — backs `ClaimNext`
  - `(user_id, wishlist_id, normalized_url, created_at DESC) WHERE wishlist_id IS NOT NULL` — dedupe
  - `(created_item_id) WHERE created_item_id IS NOT NULL`

### `wishlist_members`

- `wishlist_id UUID NOT NULL REFERENCES wishlists(id) ON DELETE CASCADE`
- `user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE`
- `role TEXT NOT NULL` — CHECK `IN ('viewer','editor')`
- `created_at` / `updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`
- `PRIMARY KEY (wishlist_id, user_id)`
- Index: `(user_id)`

### `wishlist_invites`

- `id UUID PRIMARY KEY DEFAULT gen_random_uuid()`
- `wishlist_id UUID NOT NULL REFERENCES wishlists(id) ON DELETE CASCADE`
- `email CITEXT` — **nullable**
- `role TEXT NOT NULL` — CHECK `IN ('viewer','editor')`
- `invited_by_user_id UUID REFERENCES app_users(id) ON DELETE SET NULL`
- `token_hash TEXT NOT NULL UNIQUE`
- `accepted_at TIMESTAMPTZ`, `expires_at TIMESTAMPTZ NOT NULL`
- `created_at` / `updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`
- Indexes:
  - partial UNIQUE `(wishlist_id, email) WHERE email IS NOT NULL`
  - `(wishlist_id)`
  - `(email) WHERE email IS NOT NULL`
  - `(expires_at)`

Expired, unaccepted rows are swept periodically by the maintenance worker.

### `discover_products`

- `id UUID PRIMARY KEY DEFAULT gen_random_uuid()`
- `title TEXT NOT NULL`, `brand TEXT NOT NULL`
- `category TEXT NOT NULL` — CHECK `IN ('fashion','beauty','home','accessories','gifts','travel')`
- `image_url TEXT NOT NULL`, `product_url TEXT NOT NULL`
- `save_count INTEGER NOT NULL DEFAULT 0` — denormalized; reconcile via `COUNT(*)` on saves if it drifts
- `price_label TEXT`
- `gender TEXT` — CHECK `IS NULL OR IN ('men','women')` (product target audience; ingestion lowercases)
- `product_type TEXT`
- `created_at` / `updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`
- `expires_at TIMESTAMPTZ NOT NULL DEFAULT NOW() + INTERVAL '30 days'` — per-item TTL; app-supplied on write and extended on every re-scrape (upsert). The maintenance worker deletes rows past `expires_at` and evicts over the `DISCOVER_MAX_PRODUCTS` cap (least-saved/oldest first).
- Indexes: `(category)`, `(brand)`, `(save_count DESC, created_at DESC)`, `(expires_at)`, UNIQUE `(product_url)`

### `discover_product_saves`

- `user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE`
- `product_id UUID NOT NULL REFERENCES discover_products(id) ON DELETE CASCADE`
- `created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`
- `PRIMARY KEY (user_id, product_id)`

### `starter_packs`

- `id UUID PRIMARY KEY DEFAULT gen_random_uuid()`
- `title TEXT NOT NULL`, `subtitle TEXT NOT NULL DEFAULT ''`, `cover_image_url TEXT NOT NULL`
- `created_at` / `updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`

### `starter_pack_items`

- `pack_id UUID NOT NULL REFERENCES starter_packs(id) ON DELETE CASCADE`
- `product_id UUID NOT NULL REFERENCES discover_products(id) ON DELETE CASCADE`
- `rank INTEGER NOT NULL` — CHECK `rank > 0`
- `PRIMARY KEY (pack_id, product_id)`

### `notifications`

Added in migration `000003_notifications`. Durable inbox rows — the source of truth for the
in-app inbox and unread badge; any FCM push derived from a row is best-effort/advisory. No
`updated_at` trigger: only `read_at` ever mutates.

- `id UUID PRIMARY KEY DEFAULT gen_random_uuid()`
- `user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE`
- `type TEXT NOT NULL` — CHECK `IN ('list_member_joined','item_added','item_purchased','import_settled')` (drift-tested against `domain.AllTypes()`)
- `title TEXT NOT NULL`, `body TEXT NOT NULL DEFAULT ''`
- `wishlist_id UUID REFERENCES wishlists(id) ON DELETE SET NULL` — nullable deep-link target
- `item_id UUID REFERENCES wishlist_items(id) ON DELETE SET NULL`
- `import_job_id UUID REFERENCES product_import_jobs(id) ON DELETE SET NULL`
- `read_at TIMESTAMPTZ` — **NULL = unread** (drives the badge); a per-list-muted row is inserted with `read_at = created_at` (silent-but-visible, never badges/pushes)
- `created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`
- Indexes:
  - `(user_id, created_at DESC)` — backs `ListByUser`
  - partial `(user_id) WHERE read_at IS NULL` — backs `CountUnread`

### `device_tokens`

Added in migration `000003_notifications`. FCM device registrations. No `updated_at` trigger;
`last_seen_at` is refreshed on upsert.

- `id UUID PRIMARY KEY DEFAULT gen_random_uuid()`
- `user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE`
- `token TEXT NOT NULL UNIQUE` — `ON CONFLICT (token)` re-points a device that moves between accounts to the new user
- `platform TEXT NOT NULL` — CHECK `IN ('ios','android')`
- `created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`, `last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`
- Index: `(user_id)`
- The user-facing deregister deletes scoped by `(token, user_id)` (IDOR guard); FCM-dead tokens are pruned by token only via a batch delete.

### `notification_mutes`

Added in migration `000003_notifications`. Per-list notification mutes. Standalone (not a
`wishlist_members` column) because the owner has no `wishlist_members` row — ownership lives only
on `wishlists.owner_id`. Insert/delete only, no `updated_at`.

- `user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE`
- `wishlist_id UUID NOT NULL REFERENCES wishlists(id) ON DELETE CASCADE`
- `created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`
- `PRIMARY KEY (user_id, wishlist_id)`

## Updated Timestamps

One `set_updated_at()` trigger function is attached to every table that carries an `updated_at`
column: `app_users`, `wishlists`, `wishlist_items`, `product_import_jobs`, `wishlist_members`,
`wishlist_invites`, `discover_products`, and `starter_packs`. (`app_sessions`,
`discover_product_saves`, `starter_pack_items`, and the `000003` notification tables —
`notifications`, `device_tokens`, `notification_mutes` — have no `updated_at` and no trigger.)
