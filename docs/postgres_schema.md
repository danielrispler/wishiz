# PostgreSQL Schema

Source of truth: `apps/api/internal/platform/db/migrations/000001_init_wishlists.up.sql`.
Pre-launch convention is to edit that migration in place and drop & recreate the local DB
(`docker compose down -v && docker compose up --build`). This doc mirrors that file.

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
- `birthday DATE NOT NULL`
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
- `price_label TEXT` — display string (e.g. `"USD 129.00"`)
- `price_amount NUMERIC(12,2)` — structured amount captured at import time
- `price_currency_code TEXT` — CHECK `IS NULL OR ~ '^[A-Z]{3}$'`
- `priority TEXT NOT NULL DEFAULT 'medium'` — CHECK `IN ('low','medium','high')`
- `status TEXT NOT NULL DEFAULT 'saved'` — CHECK `IN ('saved','considering','purchased')`
- `image_url TEXT`
- `product_url TEXT`
- `purchased_at TIMESTAMPTZ`
- `created_at` / `updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`
- `UNIQUE (wishlist_id, rank) DEFERRABLE INITIALLY IMMEDIATE`
- Index: `(wishlist_id)`

`price_amount` / `price_currency_code` are written from the importer's structured scrape result
and preserved on item edits (item edits manage `price_label` only).

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

## Updated Timestamps

One `set_updated_at()` trigger function is attached to every table that carries an `updated_at`
column: `app_users`, `wishlists`, `wishlist_items`, `product_import_jobs`, `wishlist_members`,
`wishlist_invites`, `discover_products`, and `starter_packs`. (`app_sessions`,
`discover_product_saves`, and `starter_pack_items` have no `updated_at` and no trigger.)
