-- Revert the price_source CHECK to the 000001 value set (without zenrows_autoparse).
ALTER TABLE product_import_jobs DROP CONSTRAINT product_import_jobs_price_source_check;
ALTER TABLE product_import_jobs ADD CONSTRAINT product_import_jobs_price_source_check
    CHECK (price_source IS NULL OR price_source IN (
        'json_ld', 'shopify', 'open_graph', 'microdata', 'js_state', 'merchant',
        'title', 'h1', 'generic_dom', 'canonical', 'final_url', 'inferred'
    ));
