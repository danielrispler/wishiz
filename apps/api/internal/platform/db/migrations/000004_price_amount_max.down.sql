-- Rollback for 000004 (documentation / manual use only; .down.sql is never run by
-- the embedded runner).
ALTER TABLE product_import_jobs DROP CONSTRAINT IF EXISTS product_import_jobs_price_currency_code_check;
ALTER TABLE product_import_jobs
    DROP COLUMN IF EXISTS price_amount,
    DROP COLUMN IF EXISTS price_amount_max,
    DROP COLUMN IF EXISTS price_currency_code;

ALTER TABLE wishlist_items
    DROP COLUMN IF EXISTS price_amount_max;
