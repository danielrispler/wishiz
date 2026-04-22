CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;

CREATE TABLE IF NOT EXISTS schema_migrations (
    version TEXT PRIMARY KEY,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TABLE IF NOT EXISTS app_users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email CITEXT NOT NULL UNIQUE,
    full_name TEXT NOT NULL,
    birthday DATE NOT NULL,
    password_hash TEXT NOT NULL,
    preferred_currency_code TEXT NOT NULL DEFAULT 'USD',
    notifications_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    reminder_days INTEGER NOT NULL DEFAULT 14,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT app_users_preferred_currency_code_check CHECK (preferred_currency_code ~ '^[A-Z]{3}$'),
    CONSTRAINT app_users_reminder_days_check CHECK (reminder_days BETWEEN 0 AND 365)
);

CREATE TRIGGER app_users_set_updated_at
    BEFORE UPDATE ON app_users
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS app_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    token_hash TEXT NOT NULL UNIQUE,
    expires_at TIMESTAMPTZ NOT NULL,
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS app_sessions_user_id_idx
    ON app_sessions (user_id);

CREATE INDEX IF NOT EXISTS app_sessions_expires_at_idx
    ON app_sessions (expires_at);

CREATE TABLE IF NOT EXISTS wishlists (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    year INTEGER NOT NULL,
    cover_image_url TEXT,
    share_token TEXT NOT NULL UNIQUE,
    is_archived BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT wishlists_year_check CHECK (year BETWEEN 2000 AND 2100)
);

CREATE INDEX IF NOT EXISTS wishlists_owner_id_idx
    ON wishlists (owner_id);

CREATE TRIGGER wishlists_set_updated_at
    BEFORE UPDATE ON wishlists
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS wishlist_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    wishlist_id UUID NOT NULL REFERENCES wishlists(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    rank INTEGER NOT NULL,
    notes TEXT,
    price_label TEXT,
    priority TEXT NOT NULL DEFAULT 'medium',
    status TEXT NOT NULL DEFAULT 'saved',
    image_url TEXT,
    product_url TEXT,
    purchased_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT wishlist_items_rank_positive CHECK (rank > 0),
    CONSTRAINT wishlist_items_priority_check CHECK (priority IN ('low', 'medium', 'high')),
    CONSTRAINT wishlist_items_status_check CHECK (status IN ('saved', 'considering', 'purchased')),
    CONSTRAINT wishlist_items_wishlist_rank_unique UNIQUE (wishlist_id, rank) DEFERRABLE INITIALLY IMMEDIATE
);

CREATE INDEX IF NOT EXISTS wishlist_items_wishlist_id_idx
    ON wishlist_items (wishlist_id);

CREATE TRIGGER wishlist_items_set_updated_at
    BEFORE UPDATE ON wishlist_items
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS wishlist_members (
    wishlist_id UUID NOT NULL REFERENCES wishlists(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    role TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (wishlist_id, user_id),
    CONSTRAINT wishlist_members_role_check CHECK (role IN ('viewer', 'editor'))
);

CREATE INDEX IF NOT EXISTS wishlist_members_user_id_idx
    ON wishlist_members (user_id);

CREATE TRIGGER wishlist_members_set_updated_at
    BEFORE UPDATE ON wishlist_members
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS wishlist_invites (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    wishlist_id UUID NOT NULL REFERENCES wishlists(id) ON DELETE CASCADE,
    email CITEXT NOT NULL,
    role TEXT NOT NULL,
    invited_by_user_id UUID REFERENCES app_users(id) ON DELETE SET NULL,
    token_hash TEXT NOT NULL UNIQUE,
    accepted_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (wishlist_id, email),
    CONSTRAINT wishlist_invites_role_check CHECK (role IN ('viewer', 'editor'))
);

CREATE INDEX IF NOT EXISTS wishlist_invites_wishlist_id_idx
    ON wishlist_invites (wishlist_id);

CREATE INDEX IF NOT EXISTS wishlist_invites_email_idx
    ON wishlist_invites (email);

CREATE INDEX IF NOT EXISTS wishlist_invites_expires_at_idx
    ON wishlist_invites (expires_at);

CREATE TRIGGER wishlist_invites_set_updated_at
    BEFORE UPDATE ON wishlist_invites
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();
