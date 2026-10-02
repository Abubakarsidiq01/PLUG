-- Manual v4 Phase 2: the controlled skill vocabulary, provider capability on the same
-- account, provider matching and the single ask entry point. Expand-only: V4/V5 data stays
-- valid, and the vocabulary foreign keys are NOT VALID so they bind new rows only.

-- Generated from contracts/skills.yaml (the backend refuses to start if they disagree).
CREATE TABLE skill_vocabulary (
    tag TEXT PRIMARY KEY CHECK (tag ~ '^[a-z][a-z0-9_]{1,39}$'),
    display TEXT NOT NULL CHECK (length(display) BETWEEN 1 AND 80),
    parent TEXT NOT NULL,
    requires_licence BOOLEAN NOT NULL DEFAULT FALSE
);
INSERT INTO skill_vocabulary (tag, display, parent, requires_licence) VALUES
  ('barber', 'Barber', 'hair', FALSE),
  ('braids', 'Braids', 'hair', FALSE),
  ('wig_install', 'Wig install', 'hair', FALSE),
  ('hair_styling', 'Hair styling', 'hair', FALSE),
  ('nails', 'Nails', 'beauty', FALSE),
  ('lashes', 'Lashes', 'beauty', FALSE),
  ('makeup', 'Makeup', 'beauty', FALSE),
  ('brows', 'Brows', 'beauty', FALSE),
  ('laptop_repair', 'Laptop repair', 'tech', FALSE),
  ('phone_repair', 'Phone repair', 'tech', FALSE),
  ('shoe_repair', 'Shoe repair', 'repair', FALSE),
  ('tailoring', 'Tailoring', 'repair', FALSE),
  ('bike_repair', 'Bike repair', 'repair', FALSE),
  ('plumbing_minor', 'Minor plumbing', 'home', FALSE),
  ('electrical', 'Electrical work', 'home', TRUE),
  ('handyman', 'Handyman', 'home', FALSE),
  ('furniture_assembly', 'Furniture assembly', 'home', FALSE),
  ('tv_mounting', 'TV mounting', 'home', FALSE),
  ('house_cleaning', 'House cleaning', 'home', FALSE),
  ('moving_help', 'Moving help', 'home', FALSE),
  ('painting', 'Painting', 'home', FALSE),
  ('lawn_care', 'Lawn care', 'home', FALSE),
  ('locksmith', 'Locksmith', 'home', TRUE),
  ('auto_repair', 'Auto repair', 'vehicle', FALSE),
  ('car_wash', 'Car wash', 'vehicle', FALSE),
  ('towing', 'Towing', 'vehicle', FALSE),
  ('tutoring', 'Tutoring', 'lessons', FALSE),
  ('music_lessons', 'Music lessons', 'lessons', FALSE),
  ('photography', 'Photography', 'creative', FALSE),
  ('personal_training', 'Personal training', 'lessons', FALSE),
  ('pet_grooming', 'Pet grooming', 'pets', FALSE),
  ('dog_walking', 'Dog walking', 'pets', FALSE),
  ('pet_sitting', 'Pet sitting', 'pets', FALSE),
  ('errands', 'Errands', 'errands', FALSE),
  ('massage', 'Massage', 'wellness', TRUE);

-- Earlier free-form categories, onto the vocabulary where one exists.
UPDATE places SET category = 'nails' WHERE category = 'beauty';
UPDATE request_constraints SET category = CASE category
    WHEN 'beauty' THEN 'nails' WHEN 'plumber' THEN 'plumbing_minor' WHEN 'electrician' THEN 'electrical'
    WHEN 'movers' THEN 'moving_help' WHEN 'tailor' THEN 'tailoring' WHEN 'tutor' THEN 'tutoring'
    WHEN 'computer_repair' THEN 'laptop_repair' ELSE category END
    WHERE category IS NOT NULL;
ALTER TABLE request_constraints
    ADD COLUMN skill_tags TEXT[] NOT NULL DEFAULT '{}' CHECK (cardinality(skill_tags) <= 5),
    ADD COLUMN licence_required BOOLEAN NOT NULL DEFAULT FALSE;
UPDATE request_constraints SET skill_tags = ARRAY[category] WHERE category IS NOT NULL;
ALTER TABLE request_constraints ADD CONSTRAINT request_constraints_category_vocabulary
    FOREIGN KEY (category) REFERENCES skill_vocabulary(tag) NOT VALID;
ALTER TABLE places ADD CONSTRAINT places_category_vocabulary
    FOREIGN KEY (category) REFERENCES skill_vocabulary(tag) NOT VALID;

-- A provider IS a user (manual v4 §2.3): keyed on user_id, so a second account is impossible.
CREATE TABLE provider_profiles (
    user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    travel_radius_m INTEGER NOT NULL CHECK (travel_radius_m BETWEEN 500 AND 80000),
    base_location GEOGRAPHY(POINT, 4326) NOT NULL,
    location_precision TEXT NOT NULL CHECK (location_precision IN ('coarse','fine')),
    time_zone TEXT NOT NULL CHECK (length(time_zone) BETWEEN 1 AND 64),
    accepting BOOLEAN NOT NULL DEFAULT TRUE,
    licence_ref TEXT CHECK (licence_ref IS NULL OR length(licence_ref) BETWEEN 3 AND 64),
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX provider_location_idx ON provider_profiles USING GIST (base_location);
CREATE TABLE provider_skills (
    user_id TEXT NOT NULL REFERENCES provider_profiles(user_id) ON DELETE CASCADE,
    skill_tag TEXT NOT NULL REFERENCES skill_vocabulary(tag),
    PRIMARY KEY (user_id, skill_tag)
);
CREATE INDEX provider_skills_tag_idx ON provider_skills (skill_tag);
-- Weekly windows in the provider's own time zone; matching checks them against the ask.
CREATE TABLE provider_availability (
    user_id TEXT NOT NULL REFERENCES provider_profiles(user_id) ON DELETE CASCADE,
    days TEXT NOT NULL CHECK (days IN ('weekdays','weekends','every_day')),
    from_minute INTEGER NOT NULL CHECK (from_minute BETWEEN 0 AND 1439),
    to_minute INTEGER NOT NULL CHECK (to_minute BETWEEN 1 AND 1440),
    position SMALLINT NOT NULL,
    PRIMARY KEY (user_id, position),
    CHECK (to_minute > from_minute)
);
-- Filled by completed work from Phase 3 and 5. Empty means New, never a zero (§12C.3).
CREATE TABLE provider_scores (
    user_id TEXT PRIMARY KEY REFERENCES provider_profiles(user_id) ON DELETE CASCADE,
    completed_jobs INTEGER NOT NULL DEFAULT 0 CHECK (completed_jobs >= 0),
    response_rate NUMERIC(4,3) CHECK (response_rate BETWEEN 0 AND 1),
    trust_score SMALLINT CHECK (trust_score BETWEEN 0 AND 100)
);
-- Who a request was matched to and notified about. Phase 3's inbox reads this table.
CREATE TABLE request_matches (
    request_id TEXT NOT NULL REFERENCES requests(id) ON DELETE CASCADE,
    provider_id TEXT NOT NULL REFERENCES provider_profiles(user_id) ON DELETE CASCADE,
    distance_m INTEGER NOT NULL CHECK (distance_m >= 0),
    rank_score NUMERIC(6,2) NOT NULL,
    notified_at TIMESTAMPTZ NOT NULL,
    replied_at TIMESTAMPTZ,
    PRIMARY KEY (request_id, provider_id)
);
CREATE INDEX request_matches_provider_idx ON request_matches (provider_id, notified_at DESC);

-- The single ask entry point (§12A). A service ask owns a request; a place question its row.
CREATE TABLE place_questions (
    id TEXT PRIMARY KEY CHECK (id ~ '^plq_[A-Za-z0-9-]+$'),
    user_id TEXT NOT NULL REFERENCES users(id),
    text TEXT NOT NULL CHECK (length(text) BETWEEN 1 AND 500),
    place_name TEXT CHECK (place_name IS NULL OR length(place_name) BETWEEN 1 AND 120),
    status TEXT NOT NULL CHECK (status IN ('asking','answered','unknown')),
    notified INTEGER NOT NULL DEFAULT 0 CHECK (notified >= 0),
    opened INTEGER NOT NULL DEFAULT 0 CHECK (opened >= 0),
    answered INTEGER NOT NULL DEFAULT 0 CHECK (answered >= 0),
    latitude DOUBLE PRECISION NOT NULL CHECK (latitude BETWEEN -90 AND 90),
    longitude DOUBLE PRECISION NOT NULL CHECK (longitude BETWEEN -180 AND 180),
    created_at TIMESTAMPTZ NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL CHECK (expires_at > created_at)
);
CREATE TABLE asks (
    id TEXT PRIMARY KEY CHECK (id ~ '^ask_[A-Za-z0-9-]+$'),
    user_id TEXT NOT NULL REFERENCES users(id),
    text TEXT NOT NULL CHECK (length(text) BETWEEN 1 AND 500),
    ask_type TEXT CHECK (ask_type IN ('service_request','place_question')),
    request_id TEXT UNIQUE REFERENCES requests(id),
    place_question_id TEXT UNIQUE REFERENCES place_questions(id),
    clarification_id TEXT UNIQUE,
    clarification_options JSONB CHECK (clarification_options IS NULL OR jsonb_typeof(clarification_options) = 'array'),
    latitude DOUBLE PRECISION NOT NULL CHECK (latitude BETWEEN -90 AND 90),
    longitude DOUBLE PRECISION NOT NULL CHECK (longitude BETWEEN -180 AND 180),
    location_precision TEXT NOT NULL CHECK (location_precision IN ('coarse','fine')),
    time_zone TEXT,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    -- A resolved ask points at exactly the record its type implies.
    CHECK (ask_type IS NULL OR (ask_type = 'service_request') = (request_id IS NOT NULL)),
    CHECK (ask_type IS NULL OR (ask_type = 'place_question') = (place_question_id IS NOT NULL))
);
CREATE INDEX asks_owner_created_idx ON asks (user_id, created_at DESC);
-- Unmatched plain-words terms from providers: how the vocabulary grows from real demand.
CREATE TABLE vocabulary_gaps (
    term TEXT PRIMARY KEY CHECK (length(term) BETWEEN 1 AND 60),
    seen_count INTEGER NOT NULL DEFAULT 1,
    first_seen TIMESTAMPTZ NOT NULL,
    last_seen TIMESTAMPTZ NOT NULL
);
