-- Expand-only P3.S12 schema: an explicit decline (contract 0.7.1 declineMatch, MatchDecline).
-- A decline is a reply (it sets replied_at at the same instant) and is never scored; silence is
-- a match with no reply by respond_by, derived from notified_at, so it needs no column.
ALTER TABLE request_matches ADD COLUMN declined_at TIMESTAMPTZ,
    ADD COLUMN decline_reason TEXT CHECK (decline_reason IN ('busy','too_far','price','not_my_skill','other')),
    ADD CONSTRAINT request_matches_decline_check CHECK (declined_at IS NOT NULL OR decline_reason IS NULL),
    ADD CONSTRAINT request_matches_decline_reply_check CHECK (declined_at IS NULL OR replied_at = declined_at);
