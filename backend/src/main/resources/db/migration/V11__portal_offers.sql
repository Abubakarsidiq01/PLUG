-- Expand-only P3.S11 schema: in-app provider offers (contract 0.7.1 sendProviderOffer).
-- A portal offer comes from a matched provider, carries no place (their home is never shown),
-- is labelled confirmed when made and may carry the provider's own note. Seed offers are unchanged.
ALTER TABLE request_offers DROP CONSTRAINT request_offers_truth_label_check,
    DROP CONSTRAINT request_offers_source_check,
    ALTER COLUMN place_id DROP NOT NULL,
    ADD COLUMN note TEXT CHECK (length(note) BETWEEN 1 AND 140),
    -- Rounded to 100 m when written; only portal offers set it (seed offers use request_seed_work).
    ADD COLUMN distance_m INTEGER CHECK (distance_m BETWEEN 0 AND 80000),
    ADD CONSTRAINT request_offers_source_check CHECK (source IN ('seed','portal')),
    ADD CONSTRAINT request_offers_truth_label_check CHECK (truth_label IN ('estimated','confirmed')),
    -- A seed offer is never confirmed (contract TruthLabel); a place exactly when not portal.
    ADD CONSTRAINT request_offers_seed_estimated_check CHECK (source <> 'seed' OR truth_label = 'estimated'),
    ADD CONSTRAINT request_offers_place_check CHECK ((source = 'portal') = (place_id IS NULL)),
    ADD CONSTRAINT request_offers_portal_check CHECK (source = 'portal' OR (note IS NULL AND distance_m IS NULL)),
    ADD CONSTRAINT request_offers_portal_distance_check CHECK (source <> 'portal' OR distance_m IS NOT NULL);
-- One in-app offer per provider per request (contract: enforced by the database). Portal only:
-- seed offers linked to a provider by hand (demo data, tests) may share one.
CREATE UNIQUE INDEX request_offers_provider_idx ON request_offers(request_id, provider_id) WHERE source = 'portal';
