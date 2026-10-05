import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { root, validateSchema, vocabulary } from './validate.mjs';

// Manual v4 §27.3, Person Two: the labelled classification dataset for POST /v1/asks.
// This checks the labels themselves. It does not run the classifier; asks-live.mjs does.
const cases = readFileSync(new URL('fixtures/intents/asks.jsonl', root), 'utf8').trim().split('\n').map(JSON.parse);
const kinds = ['service_request', 'place_question', 'ambiguous', 'restricted'];
const reasons = ['illegal_goods_or_services', 'private_person', 'disguised_surveillance', 'regulated_profession'];

test('ask dataset has unique ids and covers every kind of ask and every refusal reason', () => {
  assert.equal(new Set(cases.map(item => item.id)).size, cases.length);
  for (const kind of kinds) {
    assert.ok(cases.filter(item => item.kind === kind).length >= 8, `Too few ${kind} cases`);
  }
  for (const reason of reasons) {
    assert.ok(cases.filter(item => item.expected.reason === reason).length >= 5, `Too few ${reason} cases`);
  }
  assert.ok(cases.some(item => item.id.startsWith('near-miss-')), 'Missing harmless look-alike cases');
});

for (const item of cases) {
  test(`ask vector ${item.id} has a valid input and a complete label`, () => {
    assert.match(item.id, /^[a-z0-9-]+$/);
    assert.ok(kinds.includes(item.kind));
    validateSchema('AskBody', item.input);
    const expected = item.expected;
    if (item.kind === 'restricted') {
      assert.equal(expected.status, 422);
      assert.equal(expected.error_code, 'restricted_intent');
      assert.ok(reasons.includes(expected.reason));
      assert.equal(expected.outreach, false);
      assert.equal(expected.audit_required, true);
      return;
    }
    assert.equal(expected.status, 201);
    if (item.kind === 'service_request') {
      assert.equal(expected.ask_type, 'service_request');
      assert.ok(expected.skill_tags_any_of.length > 0);
      for (const tag of expected.skill_tags_any_of) {
        assert.ok(vocabulary.has(tag), `Expected skill outside skills.yaml: ${tag}`);
      }
      if (Object.hasOwn(expected, 'budget_cents')) assert.ok(Number.isInteger(expected.budget_cents) && expected.budget_cents > 0);
    } else if (item.kind === 'place_question') {
      assert.equal(expected.ask_type, 'place_question');
      assert.equal(typeof expected.place_named, 'boolean');
    } else {
      assert.equal(expected.ask_type, null);
      assert.equal(expected.clarification_field, 'ask');
    }
  });
}
