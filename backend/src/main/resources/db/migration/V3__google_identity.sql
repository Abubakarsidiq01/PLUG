-- Expand identity providers without modifying already-applied migrations.
ALTER TABLE users DROP CONSTRAINT users_account_type_check;
ALTER TABLE users ADD CONSTRAINT users_account_type_check
    CHECK (account_type IN ('guest', 'phone', 'apple', 'google'));
ALTER TABLE identities DROP CONSTRAINT identities_provider_check;
ALTER TABLE identities ADD CONSTRAINT identities_provider_check
    CHECK (provider IN ('apple', 'phone', 'google'));
CREATE TABLE google_token_uses (
    token_hash TEXT PRIMARY KEY,
    expires_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX google_token_uses_expiry_idx ON google_token_uses (expires_at);
