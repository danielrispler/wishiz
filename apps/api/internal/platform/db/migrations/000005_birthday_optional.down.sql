-- Convention-only (down migrations are not embedded/run). Re-imposing NOT NULL
-- will FAIL if any app_users row has a NULL birthday — backfill before running.

ALTER TABLE app_users ALTER COLUMN birthday SET NOT NULL;
