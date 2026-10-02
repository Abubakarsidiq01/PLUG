-- Optional public provider identity. Existing providers and demo offers need no media.
ALTER TABLE provider_profiles ADD COLUMN business JSONB NOT NULL DEFAULT '{}'::jsonb
    CHECK (jsonb_typeof(business) = 'object' AND octet_length(business::text) <= 75000);
-- Explicit identity association, never inferred from a business name or proximity.
ALTER TABLE request_offers ADD COLUMN provider_id TEXT REFERENCES provider_profiles(user_id) ON DELETE SET NULL;
