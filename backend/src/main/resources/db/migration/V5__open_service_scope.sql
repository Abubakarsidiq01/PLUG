-- ADR-009: any lawful service, wider budgets. Expand-only; V4 rows stay valid.
ALTER TABLE request_constraints DROP CONSTRAINT request_constraints_category_check;
ALTER TABLE request_constraints ADD CONSTRAINT request_constraints_category_check
    CHECK (category ~ '^[a-z][a-z0-9_]{1,39}$');
ALTER TABLE request_constraints DROP CONSTRAINT request_constraints_budget_cents_check;
ALTER TABLE request_constraints ADD CONSTRAINT request_constraints_budget_cents_check
    CHECK (budget_cents BETWEEN 500 AND 500000);
ALTER TABLE request_constraints
    ADD COLUMN service_name TEXT CHECK (service_name IS NULL OR length(service_name) BETWEEN 1 AND 80),
    ADD COLUMN search_terms TEXT[] NOT NULL DEFAULT '{}' CHECK (cardinality(search_terms) <= 5);
-- The one question a draft asks, chosen per request (validated server copy, never model reasoning).
ALTER TABLE requests ADD COLUMN clarification_options JSONB
    CHECK (clarification_options IS NULL OR jsonb_typeof(clarification_options) = 'array');
ALTER TABLE places DROP CONSTRAINT places_category_check;
ALTER TABLE places ADD CONSTRAINT places_category_check CHECK (category ~ '^[a-z][a-z0-9_]{1,39}$');
-- Existing V4 requests could only be barber or beauty.
UPDATE request_constraints SET service_name = CASE category WHEN 'barber' THEN 'Barber' ELSE 'Beauty' END,
    search_terms = ARRAY[category] WHERE category IS NOT NULL;
UPDATE requests SET clarification_options = '[{"value":"barber","label":"Barber"},{"value":"beauty","label":"Beauty"}]'
    WHERE status = 'draft';
