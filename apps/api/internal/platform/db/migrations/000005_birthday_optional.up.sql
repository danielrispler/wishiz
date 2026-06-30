-- Apple App Review 5.1.1(v): birthday must not be required at registration. It
-- stays a real column (still powers gifting Reminders) but becomes nullable so
-- signup no longer forces it. Existing rows keep their value; new users may omit.
--
-- DROP NOT NULL is a no-op when the column is already nullable, so this is safe to
-- re-run and safe on a DB that already applied it.

ALTER TABLE app_users ALTER COLUMN birthday DROP NOT NULL;
