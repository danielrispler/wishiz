CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS schema_migrations (
    version TEXT PRIMARY KEY,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS wishlists (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    year INTEGER NOT NULL,
    cover_image_url TEXT,
    is_archived BOOLEAN NOT NULL DEFAULT FALSE,
    is_shared BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT wishlists_year_check CHECK (year BETWEEN 2000 AND 2100)
);

CREATE TABLE IF NOT EXISTS wishlist_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    wishlist_id UUID NOT NULL REFERENCES wishlists(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    rank INTEGER NOT NULL,
    notes TEXT,
    price_label TEXT,
    priority TEXT NOT NULL DEFAULT 'Medium',
    status TEXT NOT NULL DEFAULT 'Saved',
    image_url TEXT,
    product_url TEXT,
    purchased_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT wishlist_items_rank_positive CHECK (rank > 0),
    CONSTRAINT wishlist_items_priority_check CHECK (priority IN ('Low', 'Medium', 'High')),
    CONSTRAINT wishlist_items_status_check CHECK (status IN ('Saved', 'Considering', 'Purchased')),
    CONSTRAINT wishlist_items_wishlist_rank_unique UNIQUE (wishlist_id, rank) DEFERRABLE INITIALLY IMMEDIATE
);

CREATE INDEX IF NOT EXISTS wishlist_items_wishlist_id_idx
    ON wishlist_items (wishlist_id);
