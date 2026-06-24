-- Add the 'zenrows_autoparse' price_source value (ADR-0006).
--
-- 000001's CHECK was edited in place for fresh DBs, but a DB that already
-- recorded 000001 in schema_migrations never re-runs it. This migration carries
-- the constraint change to such DBs (prod). DROP + re-ADD is harmless on a fresh
-- DB whose 000001 already lists the value (identical constraint re-created).
ALTER TABLE product_import_jobs DROP CONSTRAINT product_import_jobs_price_source_check;
ALTER TABLE product_import_jobs ADD CONSTRAINT product_import_jobs_price_source_check
    CHECK (price_source IS NULL OR price_source IN (
        'json_ld', 'shopify', 'open_graph', 'microdata', 'js_state', 'merchant',
        'title', 'h1', 'generic_dom', 'canonical', 'final_url', 'inferred',
        'zenrows_autoparse'
    ));
