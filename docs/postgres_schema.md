# PostgreSQL Schema

This is the fresh Wishiz schema. The database is expected to be wiped before applying it; no historical migrations or compatibility tables are preserved.

## Extensions

- `pgcrypto` for `gen_random_uuid()`
- `citext` for case-insensitive email columns

## Tables

### `schema_migrations`

- `version TEXT PRIMARY KEY`
- `applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`

### `app_users`

- `id UUID PRIMARY KEY DEFAULT gen_random_uuid()`
- `email CITEXT NOT NULL UNIQUE`
- `full_name TEXT NOT NULL`
- `birthday DATE NOT NULL`
- `password_hash TEXT NOT NULL`
- `preferred_currency_code TEXT NOT NULL DEFAULT 'USD' CHECK (preferred_currency_code ~ '^[A-Z]{3}$')`
- `notifications_enabled BOOLEAN NOT NULL DEFAULT TRUE`
- `reminder_days INTEGER NOT NULL DEFAULT 14 CHECK (reminder_days BETWEEN 0 AND 365)`
- `created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`
- `updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`

### `app_sessions`

- `id UUID PRIMARY KEY DEFAULT gen_random_uuid()`
- `user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE`
- `token_hash TEXT NOT NULL UNIQUE`
- `expires_at TIMESTAMPTZ NOT NULL`
- `last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`
- `created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`

### `wishlists`

- `id UUID PRIMARY KEY DEFAULT gen_random_uuid()`
- `owner_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE`
- `title TEXT NOT NULL`
- `description TEXT NOT NULL DEFAULT ''`
- `year INTEGER NOT NULL CHECK (year BETWEEN 2000 AND 2100)`
- `cover_image_url TEXT`
- `is_archived BOOLEAN NOT NULL DEFAULT FALSE`
- `created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`
- `updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`

Owners are not duplicated in `wishlist_members`.

### `wishlist_items`

- `id UUID PRIMARY KEY DEFAULT gen_random_uuid()`
- `wishlist_id UUID NOT NULL REFERENCES wishlists(id) ON DELETE CASCADE`
- `title TEXT NOT NULL`
- `rank INTEGER NOT NULL CHECK (rank > 0)`
- `notes TEXT`
- `price_label TEXT`
- `priority TEXT NOT NULL DEFAULT 'medium' CHECK (priority IN ('low', 'medium', 'high'))`
- `status TEXT NOT NULL DEFAULT 'saved' CHECK (status IN ('saved', 'considering', 'purchased'))`
- `image_url TEXT`
- `product_url TEXT`
- `purchased_at TIMESTAMPTZ`
- `created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`
- `updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`
- `UNIQUE (wishlist_id, rank) DEFERRABLE INITIALLY IMMEDIATE`

### `wishlist_members`

- `wishlist_id UUID NOT NULL REFERENCES wishlists(id) ON DELETE CASCADE`
- `user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE`
- `role TEXT NOT NULL CHECK (role IN ('viewer', 'editor'))`
- `created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`
- `updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`
- `PRIMARY KEY (wishlist_id, user_id)`

### `wishlist_invites`

- `id UUID PRIMARY KEY DEFAULT gen_random_uuid()`
- `wishlist_id UUID NOT NULL REFERENCES wishlists(id) ON DELETE CASCADE`
- `email CITEXT NOT NULL`
- `role TEXT NOT NULL CHECK (role IN ('viewer', 'editor'))`
- `invited_by_user_id UUID REFERENCES app_users(id) ON DELETE SET NULL`
- `token_hash TEXT NOT NULL UNIQUE`
- `accepted_at TIMESTAMPTZ`
- `expires_at TIMESTAMPTZ NOT NULL`
- `created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`
- `updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`
- `UNIQUE (wishlist_id, email)`

## Updated Timestamps

One `set_updated_at()` trigger function is attached to every table with an `updated_at` column: `app_users`, `wishlists`, `wishlist_items`, `wishlist_members`, and `wishlist_invites`.
