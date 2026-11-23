-- Expand-only P3.S13 and P3.S14 schema: trust score v1 and provider standing (contract 0.7.0
-- ProviderScoreBreakdown, ProviderStanding, setProviderStanding; manual v4 §12C, §19A.5).

-- Suspended means never matched or notified and no offers, declines or reservation answers.
-- standing_changed_at is null until the first change, so standing counts from created_at.
ALTER TABLE provider_profiles
    ADD COLUMN standing TEXT NOT NULL DEFAULT 'active' CHECK (standing IN ('active','suspended')),
    ADD COLUMN standing_changed_at TIMESTAMPTZ;

-- When provider_scores was last recomputed.
ALTER TABLE provider_scores ADD COLUMN updated_at TIMESTAMPTZ;

-- Every score change with its cause, so "why did my score drop" has an answer (§19A.5).
-- value is the v1 weighted value; it is shown to askers only from the third completed job.
CREATE TABLE score_history (
    id BIGSERIAL PRIMARY KEY,
    provider_id TEXT NOT NULL REFERENCES provider_profiles(user_id) ON DELETE CASCADE,
    old_value SMALLINT CHECK (old_value BETWEEN 0 AND 100),
    new_value SMALLINT NOT NULL CHECK (new_value BETWEEN 0 AND 100),
    completed_jobs INTEGER NOT NULL CHECK (completed_jobs >= 0),
    components JSONB NOT NULL CHECK (jsonb_typeof(components) = 'object'),
    cause TEXT NOT NULL CHECK (cause IN ('job_completed','reservation_confirmed','reservation_released',
        'reservation_timed_out','reservation_canceled','offer_sent','match_declined','silence_detected','standing_changed')),
    at TIMESTAMPTZ NOT NULL
);
CREATE INDEX score_history_provider_idx ON score_history (provider_id, id DESC);

-- Silence is scored once, when the worker first finds a match past respond_by with no reply.
-- Existing unanswered matches start unchecked, so the worker scores them on its first passes.
ALTER TABLE request_matches ADD COLUMN silence_checked_at TIMESTAMPTZ;
CREATE INDEX request_matches_silence_idx ON request_matches (notified_at)
    WHERE replied_at IS NULL AND silence_checked_at IS NULL;

-- Completion counts a provider's bookings on every recompute.
CREATE INDEX request_reservations_provider_idx ON request_reservations (provider_id) WHERE provider_id IS NOT NULL;
