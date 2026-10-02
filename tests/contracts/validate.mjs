// QA assertions only. Product code must consume canonical server values.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import Ajv2020 from 'ajv/dist/2020.js';
import addFormats from 'ajv-formats';
import { parse } from 'yaml';

export const root = new URL('../../', import.meta.url);
export const readJSON = path => JSON.parse(readFileSync(new URL(path, root), 'utf8'));
export const contract = parse(readFileSync(new URL('contracts/openapi.yaml', root), 'utf8'));
// Manual v4 §12B.3: the only skill tags that may ever appear.
export const vocabulary = new Set(parse(readFileSync(new URL('contracts/skills.yaml', root), 'utf8')).map(entry => entry.tag));
const ajv = new Ajv2020({ allErrors: true, strictSchema: false });
addFormats(ajv);
const validators = new Map();

export function validateSchema(name, body) {
  if (!validators.has(name)) {
    assert.ok(contract.components.schemas[name], `Unknown schema: ${name}`);
    validators.set(name, ajv.compile({
      $ref: `#/components/schemas/${name}`,
      components: contract.components,
    }));
  }
  const validate = validators.get(name);
  assert.ok(validate(body), `${name}: ${ajv.errorsText(validate.errors)}`);
}

export function responseSchema(path, method, status) {
  let response = contract.paths[path]?.[method]?.responses[String(status)];
  assert.ok(response, `Undocumented response: ${method} ${path} ${status}`);
  if (response.$ref) response = contract.components.responses[response.$ref.split('/').at(-1)];
  return response.content['application/json'].schema.$ref.split('/').at(-1);
}

export const nextActions = {
  draft: 'answer_clarification', submitted: 'wait_for_offers', routed: 'wait_for_offers',
  awaiting_responses: 'wait_for_offers', ranked: 'choose_offer',
  user_selected: 'await_supplier_confirmation', confirmed: 'show_result',
  completed: 'show_result', expired: 'show_no_result', canceled: 'none',
};

function utc(value) {
  assert.match(value, /Z$/, 'Response timestamps must be UTC');
  assert.ok(Number.isFinite(Date.parse(value)), 'Invalid timestamp');
  return Date.parse(value);
}

export function validateResource(body) {
  validateSchema('RequestResource', body);
  assert.notEqual(body.status, 'blocked', 'Blocked requests must not be returned');
  assert.equal(body.next_action, nextActions[body.status], 'status/next_action mismatch');
  for (const [field, action] of Object.entries({
    clarification: 'answer_clarification', no_result_reason: 'show_no_result',
    poll_after_seconds: 'wait_for_offers',
  })) assert.equal(Object.hasOwn(body, field), body.next_action === action, `${field} presence`);

  const { category, currency, location, needed_by: neededBy } = body.constraints;
  assert.equal(currency, 'USD');
  if (category === null) {
    assert.ok(body.status === 'draft' || body.status === 'canceled' ||
      (body.status === 'expired' && body.no_result_reason === 'clarification_unanswered'),
    'Null category only on an unanswered draft or its terminal outcome');
    assert.deepEqual(body.progress, { contacted: 0, replied: 0, offers_ready: 0 },
      'No work before category clarification');
  }
  if (body.status === 'draft' || body.no_result_reason === 'clarification_unanswered') {
    assert.equal(category, null, 'Unanswered category must remain null');
  }
  if (body.clarification) {
    const values = body.clarification.options.map(option => option.value);
    assert.equal(new Set(values).size, values.length, 'Duplicate clarification options');
    for (const value of values) assert.match(value, new RegExp(contract.components.schemas.Category.pattern));
  }
  // ADR-009: the display name and maps search terms exist exactly when the service is known.
  assert.equal(body.constraints.service_name === null, category === null, 'service_name tracks category');
  assert.equal(body.constraints.skill_tags.length === 0, category === null, 'skill_tags track category');
  if (category !== null) assert.equal(body.constraints.skill_tags[0], category, 'category is the first skill tag');
  for (const tag of body.constraints.skill_tags) assert.ok(vocabulary.has(tag), `Skill tag outside the vocabulary: ${tag}`);
  const digits = location.precision === 'coarse' ? 3 : 4;
  for (const axis of ['latitude', 'longitude']) {
    assert.equal(location[axis], Number(location[axis].toFixed(digits)), 'Unrounded location');
  }
  assert.ok(body.progress.replied <= body.progress.contacted, 'Replies exceed contacts');
  assert.ok(body.progress.offers_ready <= body.progress.replied, 'Offers exceed replies');
  assert.ok(utc(body.created_at) <= utc(body.updated_at), 'Update precedes creation');
  assert.ok(utc(body.created_at) < utc(body.expires_at), 'Expiry precedes creation');
  if (neededBy !== null) utc(neededBy);
}

export function validateOffers(body, clock) {
  validateSchema('OfferList', body);
  const ids = new Set();
  for (const offer of body.offers) {
    assert.ok(!ids.has(offer.offer_id), 'Duplicate offer identifier');
    ids.add(offer.offer_id);
    assert.equal(offer.currency, 'USD');
    // Manual v4 §12C.3: fewer than three completed jobs is New, never a number.
    assert.equal(offer.provider_score.state === 'scored', offer.provider_score.value !== undefined, 'Score value only when scored');
    if (offer.provider_score.completed_jobs < 3) assert.equal(offer.provider_score.state, 'new', 'New providers show New, never a zero');
    assert.notEqual(offer.truth_label, 'not_verified', 'An offer is never a web answer');
    if (offer.source === 'seed') {
      assert.ok(['estimated', 'unknown'].includes(offer.truth_label), 'Seed data cannot be verified');
    }
    assert.ok(utc(offer.expires_at) > utc(offer.available_at), 'Offer expires before its slot');
    assert.ok(utc(offer.expires_at) > utc(clock), 'Expired offer returned');
    assert.ok(utc(offer.observed_at) <= utc(clock), 'Future observation');
  }
}
