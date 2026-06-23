CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;

-- NOTE: the schema_migrations ledger is created by the migration runner
-- (internal/platform/db/migrations.go) before any migration file is applied,
-- so it intentionally does not live here.

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
    gender TEXT,
    password_hash TEXT NOT NULL,
    preferred_currency_code TEXT NOT NULL DEFAULT 'USD',
    notifications_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    reminder_days INTEGER NOT NULL DEFAULT 14,
    preferred_brands TEXT[] NOT NULL DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT app_users_gender_check CHECK (gender IS NULL OR gender IN ('man', 'woman')),
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
    price_amount NUMERIC(12,2),
    price_currency_code TEXT,
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
    CONSTRAINT wishlist_items_price_currency_code_check
        CHECK (price_currency_code IS NULL OR price_currency_code ~ '^[A-Z]{3}$'),
    CONSTRAINT wishlist_items_wishlist_rank_unique UNIQUE (wishlist_id, rank) DEFERRABLE INITIALLY IMMEDIATE
);

CREATE INDEX IF NOT EXISTS wishlist_items_wishlist_id_idx
    ON wishlist_items (wishlist_id);

CREATE TRIGGER wishlist_items_set_updated_at
    BEFORE UPDATE ON wishlist_items
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS product_import_jobs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    wishlist_id UUID NULL REFERENCES wishlists(id) ON DELETE SET NULL,
    client_request_id TEXT NOT NULL,
    normalized_url TEXT NOT NULL,
    domain TEXT NOT NULL,
    target_currency_code TEXT NOT NULL DEFAULT 'USD',
    status TEXT NOT NULL DEFAULT 'pending',
    attempt_count INTEGER NOT NULL DEFAULT 0,
    last_attempted_at TIMESTAMPTZ,
    last_error TEXT,
    error_code TEXT, -- intentionally free-form: error vocabulary grows over time
    retryable BOOLEAN NOT NULL DEFAULT FALSE,
    title TEXT,
    price_label TEXT,
    price_confidence TEXT,
    price_source TEXT,
    price_warnings TEXT[] NOT NULL DEFAULT '{}',
    image_url TEXT,
    completeness INTEGER NOT NULL DEFAULT 0,
    progress_stage TEXT, -- intentionally free-form: scrape pipeline stage labels evolve
    progress_percent INTEGER NOT NULL DEFAULT 0,
    created_item_id UUID REFERENCES wishlist_items(id) ON DELETE SET NULL,
    acknowledged_at TIMESTAMPTZ,
    locked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT product_import_jobs_status_check CHECK (
        status IN ('pending', 'processing', 'completed', 'needs_review', 'failed')
    ),
    CONSTRAINT product_import_jobs_attempt_count_check CHECK (attempt_count >= 0),
    CONSTRAINT product_import_jobs_completeness_check CHECK (completeness BETWEEN 0 AND 3),
    CONSTRAINT product_import_jobs_progress_percent_check CHECK (progress_percent BETWEEN 0 AND 100),
    CONSTRAINT product_import_jobs_target_currency_code_check CHECK (target_currency_code ~ '^[A-Z]{3}$'),
    CONSTRAINT product_import_jobs_price_confidence_check
        CHECK (price_confidence IS NULL OR price_confidence IN ('high', 'medium', 'low', 'suspicious')),
    -- Allowed values mirror extractors.AllSourceNames() exactly; the drift test
    -- in extractors/sourcenames_test.go reads this list and fails the build if a
    -- SourceName is added without widening the CHECK (or vice-versa).
    CONSTRAINT product_import_jobs_price_source_check
        CHECK (price_source IS NULL OR price_source IN (
            'json_ld', 'shopify', 'open_graph', 'microdata', 'js_state', 'merchant',
            'title', 'h1', 'generic_dom', 'canonical', 'final_url', 'inferred'
        )),
    CONSTRAINT product_import_jobs_client_request_unique UNIQUE (user_id, client_request_id)
);

CREATE INDEX IF NOT EXISTS product_import_jobs_user_status_updated_idx
    ON product_import_jobs (user_id, status, updated_at DESC);

-- Backs List(): WHERE user_id = $1 ... ORDER BY created_at DESC.
CREATE INDEX IF NOT EXISTS product_import_jobs_user_created_idx
    ON product_import_jobs (user_id, created_at DESC);

-- Backs ClaimNext(): claims status='pending' plus retryable 'failed'/'needs_review',
-- ordered by created_at. Key + predicate mirror that query (no 'processing': those
-- rows are in-flight and never claimed).
CREATE INDEX IF NOT EXISTS product_import_jobs_claim_idx
    ON product_import_jobs (status, created_at)
    WHERE status IN ('pending', 'failed', 'needs_review');

CREATE INDEX IF NOT EXISTS product_import_jobs_dedupe_idx
    ON product_import_jobs (user_id, wishlist_id, normalized_url, created_at DESC)
    WHERE wishlist_id IS NOT NULL;

-- Supports ON DELETE SET NULL back-reference when a wishlist_item is deleted.
CREATE INDEX IF NOT EXISTS product_import_jobs_created_item_id_idx
    ON product_import_jobs (created_item_id)
    WHERE created_item_id IS NOT NULL;

CREATE TRIGGER product_import_jobs_set_updated_at
    BEFORE UPDATE ON product_import_jobs
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
    email CITEXT,
    role TEXT NOT NULL,
    invited_by_user_id UUID REFERENCES app_users(id) ON DELETE SET NULL,
    token_hash TEXT NOT NULL UNIQUE,
    accepted_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT wishlist_invites_role_check CHECK (role IN ('viewer', 'editor'))
);

CREATE UNIQUE INDEX IF NOT EXISTS wishlist_invites_wishlist_id_email_uidx
    ON wishlist_invites (wishlist_id, email)
    WHERE email IS NOT NULL;

CREATE INDEX IF NOT EXISTS wishlist_invites_wishlist_id_idx
    ON wishlist_invites (wishlist_id);

CREATE INDEX IF NOT EXISTS wishlist_invites_email_idx
    ON wishlist_invites (email)
    WHERE email IS NOT NULL;

CREATE INDEX IF NOT EXISTS wishlist_invites_expires_at_idx
    ON wishlist_invites (expires_at);

CREATE TRIGGER wishlist_invites_set_updated_at
    BEFORE UPDATE ON wishlist_invites
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS discover_products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    brand TEXT NOT NULL,
    category TEXT NOT NULL,
    image_url TEXT NOT NULL,
    product_url TEXT NOT NULL,
    save_count   INTEGER NOT NULL DEFAULT 0, -- denormalized; reconcile via COUNT(*) on discover_product_saves if it drifts
    price_label  TEXT,
    gender       TEXT,
    product_type TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    -- Per-item TTL. The maintenance sweep deletes rows past expires_at; every
    -- successful re-scrape (upsert) pushes this forward, so only stale/delisted
    -- products age out. App-supplied on write; this DEFAULT is a safety net.
    expires_at TIMESTAMPTZ NOT NULL DEFAULT NOW() + INTERVAL '30 days',
    CONSTRAINT discover_products_category_check CHECK (
        category IN ('fashion','beauty','home','accessories','gifts','travel')
    ),
    -- Product target-audience gender (distinct from app_users.gender 'man'/'woman',
    -- which is the user's own gender). Ingestion normalizes to lowercase.
    CONSTRAINT discover_products_gender_check
        CHECK (gender IS NULL OR gender IN ('men', 'women'))
);

CREATE INDEX IF NOT EXISTS discover_products_category_idx ON discover_products (category);
CREATE INDEX IF NOT EXISTS discover_products_brand_idx ON discover_products (brand);
CREATE INDEX IF NOT EXISTS discover_products_trending_idx ON discover_products (save_count DESC, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS discover_products_product_url_uidx ON discover_products (product_url);
CREATE INDEX IF NOT EXISTS discover_products_expires_at_idx ON discover_products (expires_at);

CREATE TRIGGER discover_products_set_updated_at
    BEFORE UPDATE ON discover_products
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS discover_product_saves (
    user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES discover_products(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, product_id)
);

CREATE TABLE IF NOT EXISTS starter_packs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    subtitle TEXT NOT NULL DEFAULT '',
    cover_image_url TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER starter_packs_set_updated_at
    BEFORE UPDATE ON starter_packs
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS starter_pack_items (
    pack_id UUID NOT NULL REFERENCES starter_packs(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES discover_products(id) ON DELETE CASCADE,
    rank INTEGER NOT NULL,
    PRIMARY KEY (pack_id, product_id),
    CONSTRAINT starter_pack_items_rank_positive CHECK (rank > 0)
);
