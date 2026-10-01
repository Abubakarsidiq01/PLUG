-- Expand-only Phase 2 schema. requests_v2 remains off until explicitly enabled.
CREATE TABLE requests (
    id TEXT PRIMARY KEY CHECK (id ~ '^req_[A-Za-z0-9-]+$'),
    user_id TEXT NOT NULL REFERENCES users(id),
    text TEXT NOT NULL CHECK (length(text) BETWEEN 1 AND 500),
    status TEXT NOT NULL CHECK (status IN ('draft','submitted','routed','awaiting_responses','ranked',
        'user_selected','confirmed','completed','expired','canceled','blocked')),
    clarification_id TEXT UNIQUE,
    no_result_reason TEXT CHECK (no_result_reason IN ('no_coverage','no_offers','clarification_unanswered')),
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL CHECK (expires_at > created_at)
);
CREATE INDEX requests_owner_created_idx ON requests(user_id, created_at DESC);
CREATE INDEX requests_work_idx ON requests(status, updated_at)
    WHERE status IN ('draft','submitted','routed','awaiting_responses','ranked');
CREATE INDEX requests_expiry_idx ON requests(expires_at);
CREATE TABLE request_constraints (
    request_id TEXT PRIMARY KEY REFERENCES requests(id) ON DELETE CASCADE,
    category TEXT CHECK (category IN ('barber','beauty')),
    budget_cents INTEGER CHECK (budget_cents BETWEEN 500 AND 50000),
    currency TEXT NOT NULL CHECK (currency = 'USD'),
    needed_by TIMESTAMPTZ,
    max_distance_m INTEGER NOT NULL CHECK (max_distance_m BETWEEN 100 AND 50000),
    latitude DOUBLE PRECISION NOT NULL CHECK (latitude BETWEEN -90 AND 90),
    longitude DOUBLE PRECISION NOT NULL CHECK (longitude BETWEEN -180 AND 180),
    precision TEXT NOT NULL CHECK (precision IN ('coarse','fine'))
);
CREATE TABLE places (
    id TEXT PRIMARY KEY CHECK (id ~ '^plc_[A-Za-z0-9-]+$'),
    name TEXT NOT NULL CHECK (length(name) BETWEEN 1 AND 120),
    address TEXT NOT NULL CHECK (length(address) BETWEEN 1 AND 200),
    category TEXT NOT NULL CHECK (category IN ('barber','beauty')),
    location GEOGRAPHY(POINT,4326) NOT NULL,
    is_seed BOOLEAN NOT NULL DEFAULT TRUE CHECK (is_seed)
);
CREATE INDEX places_location_idx ON places USING GIST(location);
CREATE INDEX places_category_idx ON places(category);
-- These are synthetic demo schedules, never claims about real business availability.
CREATE TABLE supplier_seeds (
    place_id TEXT PRIMARY KEY REFERENCES places(id),
    service_name TEXT NOT NULL CHECK (length(service_name) BETWEEN 1 AND 80),
    price_cents INTEGER NOT NULL CHECK (price_cents BETWEEN 500 AND 50000),
    available_after_minutes INTEGER NOT NULL CHECK (available_after_minutes BETWEEN 1 AND 1440),
    valid_for_minutes INTEGER NOT NULL CHECK (valid_for_minutes BETWEEN 1 AND 1440),
    enabled BOOLEAN NOT NULL DEFAULT TRUE
);
INSERT INTO places VALUES
 ('plc_seed-barber-one','Demo Barber One','Synthetic listing — Ruston demo zone','barber',ST_SetSRID(ST_MakePoint(-92.714,32.528),4326)::geography,TRUE),
 ('plc_seed-barber-two','Demo Barber Two','Synthetic listing — Ruston demo zone','barber',ST_SetSRID(ST_MakePoint(-92.718,32.530),4326)::geography,TRUE),
 ('plc_seed-beauty-one','Demo Beauty One','Synthetic listing — Ruston demo zone','beauty',ST_SetSRID(ST_MakePoint(-92.712,32.529),4326)::geography,TRUE);
INSERT INTO supplier_seeds VALUES
 ('plc_seed-barber-one','Demo haircut',3000,20,60,TRUE),
 ('plc_seed-barber-two','Demo haircut',3500,25,60,TRUE),
 ('plc_seed-beauty-one','Demo manicure',3500,20,60,TRUE);
CREATE TABLE request_seed_work (
    request_id TEXT NOT NULL REFERENCES requests(id) ON DELETE CASCADE,
    place_id TEXT NOT NULL REFERENCES supplier_seeds(place_id),
    distance_m INTEGER NOT NULL CHECK (distance_m BETWEEN 0 AND 50000),
    replied_at TIMESTAMPTZ,
    PRIMARY KEY(request_id,place_id)
);
CREATE TABLE request_offers (
    id TEXT PRIMARY KEY CHECK (id ~ '^off_[A-Za-z0-9-]+$'),
    request_id TEXT NOT NULL REFERENCES requests(id) ON DELETE CASCADE,
    place_id TEXT NOT NULL REFERENCES places(id),
    service_name TEXT NOT NULL CHECK (length(service_name) BETWEEN 1 AND 80),
    price_cents INTEGER NOT NULL CHECK (price_cents BETWEEN 500 AND 50000),
    currency TEXT NOT NULL CHECK (currency = 'USD'),
    available_at TIMESTAMPTZ NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    observed_at TIMESTAMPTZ NOT NULL,
    truth_label TEXT NOT NULL CHECK (truth_label = 'estimated'),
    source TEXT NOT NULL CHECK (source = 'seed'),
    UNIQUE(request_id,place_id),
    CHECK(expires_at > available_at), CHECK(available_at >= observed_at)
);
CREATE INDEX request_offers_request_expiry_idx ON request_offers(request_id,expires_at);
CREATE TABLE request_idempotency (
    user_id TEXT NOT NULL REFERENCES users(id),
    operation TEXT NOT NULL,
    key_hash TEXT NOT NULL,
    body_hash TEXT NOT NULL,
    response JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY(user_id,operation,key_hash)
);
CREATE INDEX request_idempotency_retention_idx ON request_idempotency(created_at);
