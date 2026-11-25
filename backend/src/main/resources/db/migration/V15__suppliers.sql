-- P3.S2 SMS suppliers with recorded consent (contract 0.7.7). Expand only.
-- A supplier's place is a plc_ Place shared with Phase 4 (one place model), so places is no
-- longer seed-only. Existing seed rows keep is_seed = TRUE.
ALTER TABLE places DROP CONSTRAINT places_is_seed_check;

-- The number is never stored in the clear: phone_hash is a domain-separated HMAC keyed with
-- the identity pepper, phone_ciphertext is AES-256-GCM (12-byte nonce first) for sending.
CREATE TABLE suppliers (
    id TEXT PRIMARY KEY CHECK (id ~ '^sup_[A-Za-z0-9-]+$' AND length(id) <= 64),
    business_name TEXT NOT NULL CHECK (char_length(business_name) BETWEEN 2 AND 120),
    phone_hash TEXT NOT NULL UNIQUE,
    phone_ciphertext BYTEA NOT NULL,
    phone_last2 TEXT NOT NULL CHECK (phone_last2 ~ '^[0-9]{2}$'),
    verification_status TEXT NOT NULL DEFAULT 'pending_verification'
        CHECK (verification_status IN ('pending_verification','verified','rejected','suspended')),
    verification_decided_at TIMESTAMPTZ,
    verification_reason TEXT CHECK (char_length(verification_reason) <= 300),
    consent_state TEXT NOT NULL CHECK (consent_state IN ('pending_confirmation','granted','paused','revoked')),
    consent_version TEXT NOT NULL CHECK (consent_version ~ '^sms-[0-9]{4}-[0-9]{2}-[0-9]{2}$'),
    consent_changed_at TIMESTAMPTZ NOT NULL,
    paused_until TIMESTAMPTZ,
    skill_tags TEXT[] NOT NULL DEFAULT '{}' CHECK (cardinality(skill_tags) <= 10),
    place_id TEXT REFERENCES places(id),
    service_radius_m INTEGER CHECK (service_radius_m BETWEEN 500 AND 50000),
    hours JSONB,
    time_zone TEXT CHECK (char_length(time_zone) BETWEEN 1 AND 64),
    licence_ref TEXT CHECK (char_length(licence_ref) BETWEEN 3 AND 64),
    contact_name TEXT CHECK (char_length(contact_name) BETWEEN 1 AND 80),
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    -- Contract SupplierConsent: paused_until is present if and only if the state is paused.
    CHECK ((consent_state = 'paused') = (paused_until IS NOT NULL))
);
CREATE INDEX suppliers_created_idx ON suppliers(created_at DESC, id DESC);
CREATE INDEX suppliers_consent_idx ON suppliers(consent_state, consent_changed_at DESC);

-- Append-only consent trail, like audit_events: no update, no delete, and so no foreign key (a
-- cascade or RI check cannot pass the no-delete rule). No phone number and no message body, ever.
CREATE TABLE supplier_consent_events (
    id BIGSERIAL PRIMARY KEY,
    supplier_id TEXT NOT NULL CHECK (supplier_id ~ '^sup_[A-Za-z0-9-]+$'),
    state TEXT NOT NULL CHECK (state IN ('pending_confirmation','granted','paused','revoked')),
    source TEXT NOT NULL CHECK (source IN ('web_form','staff_entry','sms_keyword','carrier','pause_elapsed')),
    version TEXT NOT NULL CHECK (version ~ '^sms-[0-9]{4}-[0-9]{2}-[0-9]{2}$'),
    occurred_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX supplier_consent_events_supplier_idx ON supplier_consent_events(supplier_id, id DESC);
CREATE RULE supplier_consent_events_no_update AS ON UPDATE TO supplier_consent_events DO INSTEAD NOTHING;
CREATE RULE supplier_consent_events_no_delete AS ON DELETE TO supplier_consent_events DO INSTEAD NOTHING;

-- P3.S2 only queues; sending, attempts and provider ids arrive with P3.S9.
CREATE TABLE sms_outbox (
    id TEXT PRIMARY KEY CHECK (id ~ '^msg_[A-Za-z0-9-]+$' AND length(id) <= 64),
    supplier_id TEXT NOT NULL REFERENCES suppliers(id),
    template TEXT NOT NULL CHECK (template IN ('optin_confirm')),
    status TEXT NOT NULL CHECK (status IN ('queued','sent','delivered','undelivered','failed','suppressed','dead_lettered')),
    created_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX sms_outbox_status_idx ON sms_outbox(status, created_at);

-- Idempotency for the account-less opt-in and for staff create. Scoped per route (and staff
-- member for create) and key; the body hash is keyed (HMAC), because the body holds a phone.
CREATE TABLE supplier_idempotency (
    scope TEXT NOT NULL,
    key_hash TEXT NOT NULL,
    body_hash TEXT NOT NULL,
    response JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY(scope, key_hash)
);
CREATE INDEX supplier_idempotency_retention_idx ON supplier_idempotency(created_at);
