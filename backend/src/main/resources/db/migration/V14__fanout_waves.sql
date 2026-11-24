-- Expand-only P3.S15 schema: the fan-out wave each contact belongs to (contract AdminMatch.wave).
-- 1 is the best six at t0, 2 and 3 the steps of four at t+120s and t+240s. Every earlier match
-- was the single Phase 2 notification, which is wave 1.
ALTER TABLE request_matches ADD COLUMN wave SMALLINT NOT NULL DEFAULT 1 CHECK (wave BETWEEN 1 AND 3);
