-- Staff accounts (owner decision 2026-10-05, ADR-013): separate accounts for the people who
-- run PLUG, created by invitation, signed in with an email, a password and a six-digit code
-- emailed on every sign-in. Expand only; nothing here changes a row that already exists.
--
-- A staff account is a users row with account_type 'staff', so sessions, revocation and the
-- audit trail work exactly as they do for everyone else. It is never a customer account:
-- the type grants the admin scope and nothing a guest or member can do.

ALTER TABLE users DROP CONSTRAINT users_account_type_check;
ALTER TABLE users ADD CONSTRAINT users_account_type_check
    CHECK (account_type IN ('guest', 'phone', 'apple', 'google', 'staff'));

-- The email is stored readable because PLUG has to send codes to it. Passwords are stored
-- only as BCrypt hashes. An owner may invite and disable staff; staff may only read.
CREATE TABLE staff_accounts (
    user_id        TEXT PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
    email          TEXT NOT NULL CHECK (email = lower(email) AND length(email) BETWEEN 6 AND 254),
    password_hash  TEXT NOT NULL,
    role           TEXT NOT NULL CHECK (role IN ('owner', 'staff')),
    status         TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'disabled')),
    invited_by     TEXT REFERENCES users (id),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    disabled_at    TIMESTAMPTZ,
    CONSTRAINT staff_accounts_disabling_is_consistent CHECK ((status = 'disabled') = (disabled_at IS NOT NULL))
);
CREATE UNIQUE INDEX staff_accounts_email_idx ON staff_accounts (email);

-- An invitation is a single-use link sent by email. Only the token's hash is stored, so a
-- database read cannot be turned into an account. invited_by is null only for the first
-- owner, whose invitation comes from the server's own configuration.
CREATE TABLE staff_invites (
    id           TEXT PRIMARY KEY CHECK (id LIKE 'inv\_%'),
    email        TEXT NOT NULL CHECK (email = lower(email) AND length(email) BETWEEN 6 AND 254),
    role         TEXT NOT NULL CHECK (role IN ('owner', 'staff')),
    token_hash   TEXT NOT NULL UNIQUE,
    invited_by   TEXT REFERENCES users (id),
    expires_at   TIMESTAMPTZ NOT NULL,
    accepted_at  TIMESTAMPTZ,
    revoked_at   TIMESTAMPTZ,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX staff_invites_open_idx ON staff_invites (email) WHERE accepted_at IS NULL AND revoked_at IS NULL;

-- The emailed second factor, shaped like phone_challenges: the code is a peppered hash and
-- the attempt count lives on the row so the limit survives a restart.
CREATE TABLE staff_login_challenges (
    id             TEXT PRIMARY KEY CHECK (id LIKE 'slc\_%'),
    user_id        TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    code_hash      TEXT NOT NULL,
    attempts_used  INTEGER NOT NULL DEFAULT 0 CHECK (attempts_used >= 0),
    expires_at     TIMESTAMPTZ NOT NULL,
    consumed_at    TIMESTAMPTZ,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX staff_login_challenges_sweep_idx ON staff_login_challenges (expires_at);
