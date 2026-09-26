-- Users, identities, sessions and consents: the one identity model every later phase
-- authorises against. Expand only. Nothing here alters a table that already exists, so
-- this migration can ship ahead of the code that reads it and a rollback needs no
-- reverse migration (manual.docx 19.10).
--
-- Identifiers are application-generated, prefixed text (usr_, ses_, cha_). The prefix
-- makes a value self-describing in a log line or a support conversation, and an
-- accidental swap between two identifier columns fails a check rather than silently
-- reading the wrong row.

CREATE TABLE users (
    id            TEXT PRIMARY KEY CHECK (id LIKE 'usr\_%'),
    account_type  TEXT NOT NULL CHECK (account_type IN ('guest', 'phone', 'apple')),
    status        TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'deleted')),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at    TIMESTAMPTZ,
    -- A deleted account keeps its row so its audit history stays readable, but it must
    -- carry the timestamp that says when, and an active one must not.
    CONSTRAINT users_deletion_is_consistent
        CHECK ((status = 'deleted') = (deleted_at IS NOT NULL))
);

-- What a person proved. The subject is stored as a salted hash: an Apple subject and a
-- phone number are both Sensitive (manual.docx 25.1), and this table never needs to read
-- either back, only to recognise the same one again.
CREATE TABLE identities (
    id            TEXT PRIMARY KEY CHECK (id LIKE 'idn\_%'),
    user_id       TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    provider      TEXT NOT NULL CHECK (provider IN ('apple', 'phone')),
    subject_hash  TEXT NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- One Apple ID or phone number belongs to exactly one account. The database enforces
    -- it, so two concurrent upgrades cannot both win and split one person into two.
    CONSTRAINT identities_one_account_per_subject UNIQUE (provider, subject_hash),
    CONSTRAINT identities_one_subject_per_provider UNIQUE (user_id, provider)
);

-- Refresh material lives here, hashed, so revocation is a row update rather than a wait
-- for an expiry. chain_id is constant across every rotation of one sign-in, which is what
-- makes "revoke the whole chain on replay" a single statement.
CREATE TABLE sessions (
    id                  TEXT PRIMARY KEY CHECK (id LIKE 'ses\_%'),
    user_id             TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    chain_id            TEXT NOT NULL,
    access_token_hash   TEXT NOT NULL UNIQUE,
    refresh_token_hash  TEXT NOT NULL UNIQUE,
    access_expires_at   TIMESTAMPTZ NOT NULL,
    refresh_expires_at  TIMESTAMPTZ NOT NULL,
    mfa_verified        BOOLEAN NOT NULL DEFAULT FALSE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_used_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    revoked_at          TIMESTAMPTZ,
    revoked_reason      TEXT CHECK (revoked_reason IN
                            ('logout', 'rotated', 'replay_detected', 'revoked_by_user',
                             'account_deleted', 'security_change')),
    CONSTRAINT sessions_refresh_outlives_access CHECK (refresh_expires_at >= access_expires_at),
    CONSTRAINT sessions_revocation_is_consistent
        CHECK ((revoked_at IS NULL) = (revoked_reason IS NULL))
);

-- Supports the two hot reads: authenticate this access token, and list my live sessions.
CREATE UNIQUE INDEX sessions_live_access_idx
    ON sessions (access_token_hash) WHERE revoked_at IS NULL;
CREATE INDEX sessions_owner_live_idx
    ON sessions (user_id, created_at DESC) WHERE revoked_at IS NULL;
CREATE INDEX sessions_chain_idx ON sessions (chain_id);

-- Which published Terms and Privacy Policy this account agreed to, and when. Append-only
-- in practice: a new version is a new row, so the history of what someone agreed to is
-- still answerable a year later.
CREATE TABLE consents (
    id           BIGSERIAL PRIMARY KEY,
    user_id      TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    version      TEXT NOT NULL CHECK (version ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'),
    accepted_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    request_id   TEXT,
    CONSTRAINT consents_one_row_per_version UNIQUE (user_id, version)
);

-- One-time codes. The code itself is stored only as a hash, so a database read does not
-- hand someone a working code, and attempts_used is on the row rather than in memory so
-- the attempt limit survives a restart.
CREATE TABLE phone_challenges (
    id             TEXT PRIMARY KEY CHECK (id LIKE 'cha\_%'),
    phone_hash     TEXT NOT NULL,
    code_hash      TEXT NOT NULL,
    attempts_used  INTEGER NOT NULL DEFAULT 0 CHECK (attempts_used >= 0),
    expires_at     TIMESTAMPTZ NOT NULL,
    consumed_at    TIMESTAMPTZ,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX phone_challenges_sweep_idx ON phone_challenges (expires_at);

-- An Apple identity token is a bearer credential until it expires. Recording the ones
-- already exchanged is what turns a captured token into a single-use one: the second
-- presentation collides on the primary key and is refused.
CREATE TABLE apple_token_uses (
    token_hash  TEXT PRIMARY KEY,
    used_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at  TIMESTAMPTZ NOT NULL
);
CREATE INDEX apple_token_uses_sweep_idx ON apple_token_uses (expires_at);

-- Append-only. The rules mean an UPDATE or DELETE silently does nothing rather than
-- succeeding, because "we agreed not to edit it" is not a control (manual.docx 19.10).
CREATE TABLE audit_events (
    id           BIGSERIAL PRIMARY KEY,
    occurred_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    actor_id     TEXT NOT NULL,
    actor_role   TEXT NOT NULL,
    action       TEXT NOT NULL,
    resource     TEXT NOT NULL,
    resource_id  TEXT NOT NULL,
    reason       TEXT,
    request_id   TEXT
);
CREATE INDEX audit_events_actor_idx ON audit_events (actor_id, occurred_at DESC);
CREATE INDEX audit_events_resource_idx ON audit_events (resource, resource_id, occurred_at DESC);
CREATE RULE audit_events_no_update AS ON UPDATE TO audit_events DO INSTEAD NOTHING;
CREATE RULE audit_events_no_delete AS ON DELETE TO audit_events DO INSTEAD NOTHING;
