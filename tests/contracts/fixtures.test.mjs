import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import test from 'node:test';
import {
  contract, nextActions, readJSON, responseSchema, root, vocabulary,
  validateOffers, validateResource, validateSchema,
} from './validate.mjs';

const manifest = readJSON('tests/contracts/fixture-manifest.json');
const rows = manifest.responses;
const readFixture = (operation, outcome) => readJSON(`fixtures/requests.${operation}/${outcome}.json`);

test('every request fixture is registered exactly once and every documented response has coverage', () => {
  assert.equal(manifest.contract_version, contract.info.version);
  const files = readdirSync(new URL('fixtures/', root))
    .filter(name => /^(requests|asks|providers|admin|staff)\./.test(name))
    .flatMap(folder => readdirSync(new URL(`fixtures/${folder}/`, root))
      .filter(name => name.endsWith('.json')).map(name => `fixtures/${folder}/${name}`));
  assert.equal(new Set(rows.map(row => row.file)).size, rows.length);
  assert.deepEqual(rows.map(row => row.file).sort(), files.sort());
  for (const [path, item] of Object.entries(contract.paths)) {
    if (!/^\/v1\/(requests|asks|providers|admin|staff)/.test(path)) continue;
    for (const method of ['get', 'post']) {
      if (!item[method]) continue;
      for (const status of Object.keys(item[method].responses)) {
        // A bodyless response (204) has nothing to fixture.
        const response = item[method].responses[status];
        if (!response.$ref && !response.content) continue;
        assert.ok(rows.some(row => row.path === path && row.method === method && String(row.status) === status),
          `Missing coverage: ${method} ${path} ${status}`);
      }
    }
  }
});

for (const row of rows) {
  test(`${row.file} matches ${row.status} and the contract's semantic rules`, () => {
    const body = readJSON(row.file);
    const schema = responseSchema(row.path, row.method, row.status);
    validateSchema(schema, body);
    if (row.example) assert.deepEqual(body, readJSON(`contracts/examples/${row.example}`));
    if (schema === 'RequestResource') validateResource(body);
    if (schema === 'OfferList') validateOffers(body, manifest.clock);
    if (schema === 'Error') {
      const codes = { 400: 'validation_failed', 401: 'unauthenticated', 403: 'forbidden',
        404: 'not_found', 409: 'conflict', 413: 'validation_failed', 415: 'validation_failed',
        422: 'restricted_intent', 429: 'rate_limited', 500: 'internal_error', 503: 'dependency_unavailable' };
      assert.equal(body.error.code, codes[row.status], 'Wrong error for HTTP status');
      assert.equal(body.error.code, row.error_code);
      if (row.details) assert.deepEqual(body.error.details, row.details);
      if (row.status === 429) assert.ok(Number.isInteger(body.error.retry_after_seconds) && body.error.retry_after_seconds > 0);
      if (row.status === 422) assert.deepEqual(Object.keys(body.error).sort(), ['code', 'message', 'request_id']);
    }
  });
}

test('schema enums, fixture states and no-result outcomes cannot silently drift', () => {
  assert.deepEqual(Object.keys(nextActions).sort(), contract.components.schemas.RequestStatus.enum.filter(s => s !== 'blocked').sort());
  assert.deepEqual([...new Set(Object.values(nextActions))].sort(), [...contract.components.schemas.NextAction.enum].sort());
  const resources = rows.map(row => readJSON(row.file)).filter(body => body.status);
  assert.deepEqual([...new Set(resources.map(body => body.status))].sort(),
    ['awaiting_responses', 'canceled', 'draft', 'expired', 'ranked', 'routed', 'submitted']);
  assert.deepEqual([...new Set(resources.map(body => body.no_result_reason).filter(Boolean))].sort(),
    [...contract.components.schemas.NoResultReason.enum].sort());
});

test('clarification preserves the draft identity and fills only the answered category', () => {
  const draft = readFixture('create', 'ambiguous');
  const answered = readFixture('clarify', 'success');
  assert.equal(answered.request_id, draft.request_id);
  assert.equal(answered.text, draft.text);
  assert.equal(answered.created_at, draft.created_at);
  assert.deepEqual(answered.constraints,
    { ...draft.constraints, category: 'barber', service_name: 'Barber', skill_tags: ['barber'], licence_required: false });
  assert.equal(answered.status, 'submitted');
  assert.equal(answered.clarification, undefined);
  for (const body of [readFixture('cancel', 'draft-canceled'), readFixture('get', 'clarification-unanswered')]) {
    assert.equal(body.request_id, draft.request_id);
    assert.deepEqual(body.constraints, draft.constraints);
    assert.equal(body.clarification, undefined);
  }
});

test('ownership denial and missing/malformed resources have indistinguishable envelopes', () => {
  for (const operation of ['get', 'clarify', 'offers', 'cancel']) {
    for (const outcome of ['ownership-denied', 'malformed-id']) {
      assert.deepEqual(readFixture(operation, outcome), readFixture(operation, 'not-found'));
    }
  }
});

test('cancel replay is stable and offer fixtures correlate with their request', () => {
  assert.deepEqual(readFixture('cancel', 'success'), readFixture('cancel', 'already-canceled'));
  const request = readFixture('get', 'success');
  const offers = readFixture('offers', 'success');
  assert.equal(offers.request_id, request.request_id);
  assert.equal(offers.offers.length, request.progress.offers_ready);
  for (const offer of offers.offers) {
    assert.ok(offer.price_cents <= request.constraints.budget_cents);
    assert.ok(offer.place.distance_m <= request.constraints.max_distance_m);
    assert.ok(Date.parse(offer.available_at) <= Date.parse(request.constraints.needed_by));
  }
});

// These mutations prove the QA checks actually reject the dangerous cases; a
// green fixture-only run must not be possible with a broken assertion helper.
for (const [name, operation, mutate, pattern] of [
  ['invented progress', 'get', b => { b.progress.replied = b.progress.contacted + 1; }, /Replies exceed/],
  ['extra offers', 'get', b => { b.progress.offers_ready = b.progress.replied + 1; }, /Offers exceed/],
  ['wrong next action', 'get', b => { b.next_action = 'none'; }, /mismatch/],
  ['spurious polling', 'get', b => { b.poll_after_seconds = 2; }, /presence/],
  ['unrounded location', 'get', b => { b.constraints.location.latitude = 32.52819; }, /Unrounded/],
  ['null ranked category', 'get', b => { b.constraints.category = null; }, /Null category/],
  ['invalid date', 'get', b => { b.created_at = '2026-02-30T20:00:00Z'; }, /date-time/],
  ['fake confirmation', 'offers', b => { b.offers[0].truth_label = 'confirmed'; }, /cannot be verified/],
  ['expired offer', 'offers', b => { b.offers[0].expires_at = manifest.clock; b.offers[0].available_at = '2026-10-01T20:00:00Z'; }, /Expired/],
  ['backwards slot', 'offers', b => { b.offers[0].expires_at = b.offers[0].available_at; }, /before its slot/],
  ['duplicate offer', 'offers', b => { b.offers.push(structuredClone(b.offers[0])); }, /Duplicate/],
]) {
  test(`rejects ${name}`, () => {
    const body = readFixture(operation, 'success');
    mutate(body);
    assert.throws(() => operation === 'offers' ? validateOffers(body, manifest.clock) : validateResource(body), pattern);
  });
}

const cases = readFileSync(new URL('fixtures/intents/p2.jsonl', root), 'utf8').trim().split('\n').map(JSON.parse);
test('intent dataset has unique labels and covers the required parser and abuse cases', () => {
  assert.equal(new Set(cases.map(item => item.id)).size, cases.length);
  for (const id of ['barber-budget-relative-time', 'ambiguous-category', 'missing-category',
    'restricted-intent', 'open-plumber', 'shoe-repair-tomorrow', 'explicit-category-wins', 'explicit-budget-wins',
    'overlong-text', 'invalid-latitude', 'invalid-longitude', 'absurd-budget', 'malformed-timestamp',
    'offset-missing', 'past-time', 'beyond-horizon', 'fallback-timeout', 'fallback-invalid-json',
    'fallback-unknown-model-field', 'fallback-invalid-model-budget', 'fallback-invalid-model-category']) {
    assert.ok(cases.some(item => item.id === id), `Missing intent case: ${id}`);
  }
});
for (const item of cases) {
  test(`intent vector ${item.id} has a valid label and the expected input schema result`, () => {
    assert.equal(typeof item.schema_valid, 'boolean');
    if (item.schema_valid) validateSchema('CreateRequestBody', item.input);
    else assert.throws(() => validateSchema('CreateRequestBody', item.input));
    assert.ok(['normal', 'timeout', 'invalid_json', 'unknown_field', 'out_of_range_budget', 'invalid_category'].includes(item.provider));
    assert.ok(['submitted', 'draft', 'rejected'].includes(item.expected.outcome));
    assert.match(item.now, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/);
    if (item.expected.outcome === 'draft') {
      assert.equal(item.expected.category, null);
      assert.equal(item.expected.clarification_field, 'category');
    } else if (item.expected.outcome === 'submitted') {
      assert.ok(vocabulary.has(item.expected.category), `Expected category outside skills.yaml: ${item.expected.category}`);
    } else {
      assert.ok([400, 422].includes(item.expected.status));
      assert.equal(item.expected.error_code, item.expected.status === 422 ? 'restricted_intent' : 'validation_failed');
      if (item.expected.status === 422) {
        assert.equal(item.expected.outreach, false);
        assert.equal(item.expected.audit_required, true);
      }
    }
    if (item.provider !== 'normal') assert.equal(item.expected.fallback_required, true);
    assert.ok(item.schema_valid || item.expected.outcome === 'rejected');
  });
}
