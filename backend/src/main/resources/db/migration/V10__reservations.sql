-- Expand-only P3.S6 schema: a chosen offer waits for its provider (contract 0.7.0 Reservation).
-- Only a provider event confirms it; release, timeout and cancel end it (manual v4 19.6).
CREATE TABLE request_reservations (
    id TEXT PRIMARY KEY CHECK (id ~ '^rsv_[A-Za-z0-9-]+$' AND length(id) <= 64),
    request_id TEXT NOT NULL REFERENCES requests(id) ON DELETE CASCADE,
    offer_id TEXT REFERENCES request_offers(id) ON DELETE SET NULL,
    -- The offer's provider when it was chosen; seed offers have none.
    provider_id TEXT,
    status TEXT NOT NULL CHECK (status IN ('pending','confirmed','released','timed_out','canceled')),
    booking_ref TEXT NOT NULL CHECK (booking_ref ~ '^[2-9A-HJ-NP-Z]{4}$'),
    confirm_by TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    confirmed_at TIMESTAMPTZ,
    ended_at TIMESTAMPTZ,
    CHECK ((status = 'confirmed') = (confirmed_at IS NOT NULL)),
    CHECK ((status IN ('released','timed_out','canceled')) = (ended_at IS NOT NULL))
);
-- At most one live reservation per request: the selection race has one winner.
CREATE UNIQUE INDEX request_reservations_live_idx ON request_reservations(request_id)
    WHERE status IN ('pending','confirmed');
CREATE INDEX request_reservations_request_idx ON request_reservations(request_id, created_at DESC);
CREATE INDEX request_reservations_due_idx ON request_reservations(status, confirm_by);

-- The provider-facing match identifier (contract MatchId).
ALTER TABLE request_matches ADD COLUMN match_id TEXT;
UPDATE request_matches SET match_id = 'mat_' || gen_random_uuid() WHERE match_id IS NULL;
ALTER TABLE request_matches ALTER COLUMN match_id SET DEFAULT 'mat_' || gen_random_uuid(),
    ALTER COLUMN match_id SET NOT NULL,
    ADD CONSTRAINT request_matches_match_id_check CHECK (match_id ~ '^mat_[A-Za-z0-9-]+$' AND length(match_id) <= 64),
    ADD CONSTRAINT request_matches_match_id_key UNIQUE (match_id);

-- A released or timed-out offer is no longer listed or selectable.
ALTER TABLE request_offers ADD COLUMN withdrawn_at TIMESTAMPTZ;

ALTER TABLE requests DROP CONSTRAINT requests_no_result_reason_check;
ALTER TABLE requests ADD CONSTRAINT requests_no_result_reason_check
    CHECK (no_result_reason IN ('no_coverage','no_offers','clarification_unanswered','not_confirmed'));
