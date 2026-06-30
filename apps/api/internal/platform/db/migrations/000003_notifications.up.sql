-- Event-driven notifications: durable inbox, FCM device tokens, per-list mutes.
--
-- Added as a standalone migration (not edited into 000001) because the app now
-- has real users: existing/prod DBs have already recorded 000001 and never
-- re-run it, so new schema must arrive in its own migration. All statements are
-- idempotent (IF NOT EXISTS), so this is a harmless no-op on a DB that somehow
-- already has the objects.

-- Notification inbox. Rows are the durable source of truth for the in-app inbox
-- and unread badge; the FCM push derived from a row is best-effort/advisory.
-- read_at NULL means unread (drives the badge); a per-list-muted row is inserted
-- with read_at = created_at so it is visible in history but never badges/pushes.
CREATE TABLE IF NOT EXISTS notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    type TEXT NOT NULL,
    title TEXT NOT NULL,
    body TEXT NOT NULL DEFAULT '',
    wishlist_id UUID REFERENCES wishlists(id) ON DELETE SET NULL,
    item_id UUID REFERENCES wishlist_items(id) ON DELETE SET NULL,
    import_job_id UUID REFERENCES product_import_jobs(id) ON DELETE SET NULL,
    read_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    -- Allowed values mirror notifications domain.AllTypes() exactly; the drift test
    -- in notifications/application/typedrift_test.go reads this list and fails the
    -- build if a Type is added without widening the CHECK (or vice-versa).
    CONSTRAINT notifications_type_check CHECK (type IN (
        'list_member_joined', 'item_added', 'item_purchased', 'import_settled'
    ))
);

-- Backs ListByUser(): WHERE user_id = $1 ORDER BY created_at DESC.
CREATE INDEX IF NOT EXISTS notifications_user_created_idx
    ON notifications (user_id, created_at DESC);

-- Backs CountUnread(): partial index over only the unread rows.
CREATE INDEX IF NOT EXISTS notifications_user_unread_idx
    ON notifications (user_id)
    WHERE read_at IS NULL;

-- FCM device registrations. ON CONFLICT (token) re-points a device that moves
-- between accounts to the new user (see UpsertDeviceToken).
CREATE TABLE IF NOT EXISTS device_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    token TEXT NOT NULL UNIQUE,
    platform TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT device_tokens_platform_check CHECK (platform IN ('ios', 'android'))
);

CREATE INDEX IF NOT EXISTS device_tokens_user_id_idx
    ON device_tokens (user_id);

-- Per-list notification mutes. Standalone (not a wishlist_members column) because
-- the owner has no wishlist_members row — ownership lives only on wishlists.owner_id.
CREATE TABLE IF NOT EXISTS notification_mutes (
    user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    wishlist_id UUID NOT NULL REFERENCES wishlists(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, wishlist_id)
);
