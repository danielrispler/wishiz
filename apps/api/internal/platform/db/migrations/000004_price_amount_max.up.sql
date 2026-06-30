-- Range prices (ADR-0007): store the HIGH bound of a "$low – $high" range so a
-- configurable product (e.g. West Elm "$579 – $1,598") imports as a range and is
-- displayed honestly. price_amount keeps the low/"starting at" bound.
--
-- Also backfills product_import_jobs with structured price columns (it previously
-- carried only the display price_label) so the deferred-assign path and the job
-- DTO carry numeric price/currency. All additive + nullable → safe online add on a
-- live DB; existing rows get NULL price_amount_max and render as a single price.

ALTER TABLE wishlist_items
    ADD COLUMN IF NOT EXISTS price_amount_max NUMERIC(12,2);

ALTER TABLE product_import_jobs
    ADD COLUMN IF NOT EXISTS price_amount NUMERIC(12,2),
    ADD COLUMN IF NOT EXISTS price_amount_max NUMERIC(12,2),
    ADD COLUMN IF NOT EXISTS price_currency_code TEXT;

-- DROP IF EXISTS + ADD keeps this idempotent: a re-run (or a fresh DB) re-creates
-- the identical constraint instead of erroring on a duplicate.
ALTER TABLE product_import_jobs DROP CONSTRAINT IF EXISTS product_import_jobs_price_currency_code_check;
ALTER TABLE product_import_jobs ADD CONSTRAINT product_import_jobs_price_currency_code_check
    CHECK (price_currency_code IS NULL OR price_currency_code ~ '^[A-Z]{3}$');
