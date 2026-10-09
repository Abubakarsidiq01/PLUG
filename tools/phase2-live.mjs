#!/usr/bin/env node
// Opt-in, destructive-to-test-data acceptance suite for a disposable loopback runtime.
// Never accepts tokens, emits response bodies, or uses an external model/provider.
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { setTimeout as sleep } from 'node:timers/promises';
import { responseSchema, validateSchema, validateResource, validateOffers, vocabulary } from '../tests/contracts/validate.mjs';

const base = new URL(process.env.PHASE2_BASE_URL || 'http://127.0.0.1:18082');
if (!['127.0.0.1', '[::1]', 'localhost'].includes(base.hostname) || base.protocol !== 'http:' || base.username || base.password || base.pathname !== '/' || base.search || base.hash) {
  throw new Error('PHASE2_BASE_URL must be a plain loopback HTTP origin.');
}
if (process.env.PHASE2_DISPOSABLE !== '1') throw new Error('Set PHASE2_DISPOSABLE=1 only for a fresh disposable database/backend.');
const report = { suite: 'phase2-live', environment: 'isolated-local', started_at: new Date().toISOString(), checks: [], exchanges: [], limitations: ['No independent two-person checkpoint or physical-device signoff.', 'Provider-fault injection, terminal-clock transitions, scope/consent mutation, audit rows and no-outreach persistence require separate backend database-test evidence.'] };
const output = process.env.PHASE2_REPORT;
// Prevent an interrupted rerun from leaving an older success report at the same path.
if (output) writeFileSync(output, JSON.stringify({ suite: report.suite, started_at: report.started_at, passed: false, status: 'running' }, null, 2) + '\n');
const location = { latitude: 32.528, longitude: -92.714, precision: 'coarse' };
const input = (fields = {}) => ({ text: 'Barber under $35 in 30 minutes', location, ...fields });
const key = () => `qa-${randomUUID()}`;
// The backend's rate window plus a second of margin. A disposable local backend may run a
// shorter window (PLUG_RATE_WINDOW_SECONDS); this must match it, or the limits never fire.
const windowMs = (Number(process.env.PHASE2_RATE_WINDOW_SECONDS) || 60) * 1000 + 1000;
let calls = [];
let resourceCalls = [];
const perAccount = new Map();
const created = [];
const sessions = [];

function route(path) { return path.replace(/\/requests\/[^/]+/, '/requests/{request_id}').replace(/\/asks\/[^/]+/, '/asks/{ask_id}').replace(/\/admin\/staff\/usr_[^/]+/, '/admin/staff/{user_id}'); }
function check(name, fn) {
  try { fn(); report.checks.push({ name, passed: true }); }
  catch { report.checks.push({ name, passed: false }); throw new Error(`Check failed: ${name}`); }
}
async function pace(token) {
  const now = Date.now();
  calls = calls.filter(t => now - t < windowMs);
  const account = (perAccount.get(token) || []).filter(t => now - t < windowMs);
  const waits = [calls.length >= 29 ? calls[0] + windowMs - now : 0, account.length >= 9 ? account[0] + windowMs - now : 0];
  if (Math.max(...waits) > 0) {
    console.log('Waiting for the documented creation limit window.');
    await sleep(Math.max(...waits));
    return pace(token);
  }
  calls.push(Date.now()); account.push(Date.now()); perAccount.set(token, account);
}
async function http(name, path, { method = 'GET', token, body, raw, idempotency, expected, error, detail, paced = true, contentType = 'application/json', headers = {} } = {}) {
  // POST /v1/asks shares the creation budget with POST /v1/requests (manual v4 §12A).
  if (method === 'POST' && (path === '/v1/requests' || path === '/v1/asks') && paced) await pace(token);
  // Every v2 resource route, providers included, draws on one per-address budget.
  if (/^\/v1\/(requests\/|asks\/|providers\/|admin\/)/.test(path) && paced) {
    resourceCalls = resourceCalls.filter(t => Date.now() - t < windowMs);
    if (resourceCalls.length >= 55) {
      console.log('Waiting for the resource-route limit window.');
      await sleep(resourceCalls[0] + windowMs - Date.now());
      resourceCalls = resourceCalls.filter(t => Date.now() - t < windowMs);
    }
    resourceCalls.push(Date.now());
  }
  const correlation = `qa_${randomUUID()}`;
  const h = { 'X-Request-Id': correlation, ...headers };
  if (token) h.Authorization = `Bearer ${token}`;
  if (idempotency !== undefined) h['Idempotency-Key'] = idempotency;
  if (body !== undefined || raw !== undefined) h['Content-Type'] = contentType;
  let response;
  try { response = await fetch(new URL(path, base), { method, headers: h, body: raw ?? (body === undefined ? undefined : JSON.stringify(body)), signal: AbortSignal.timeout(15000), redirect: 'error' }); }
  catch { throw new Error(`Transport failed: ${name}; runtime is unavailable (never a skipped pass).`); }
  const id = response.headers.get('x-request-id');
  report.exchanges.push({ case: name, method, route: route(path), status: response.status, correlation_id: /^[A-Za-z0-9_-]{1,80}$/.test(id || '') ? id : null });
  let data;
  try { data = await response.json(); } catch { throw new Error(`Non-JSON response: ${name}`); }
  check(`${name}: HTTP ${expected}`, () => assert.equal(response.status, expected));
  check(`${name}: correlation`, () => assert.equal(id, correlation));
  if (/^\/v1\/(requests|asks|providers|admin|staff)/.test(path)) {
    check(`${name}: contract`, () => {
      const schema = responseSchema(route(path), method.toLowerCase(), expected);
      validateSchema(schema, data);
      if (schema === 'RequestResource') validateResource(data);
      if (schema === 'OfferList') validateOffers(data, new Date().toISOString());
    });
  }
  if (error) check(`${name}: error`, () => {
    assert.equal(data.error.code, error);
    assert.equal(data.error.request_id, correlation);
    if (detail) assert.ok(data.error.details?.some(item => item.code === detail));
  });
  if (expected === 429) check(`${name}: retry guidance`, () => {
    assert.ok(Number.isInteger(data.error.retry_after_seconds) && data.error.retry_after_seconds > 0);
    assert.equal(Number(response.headers.get('retry-after')), data.error.retry_after_seconds);
  });
  if (method === 'POST' && path === '/v1/requests' && response.status === 201) created.push({ token, id: data.request_id });
  return data;
}
async function guest(name) {
  const data = await http(name, '/v1/auth/guest', { method: 'POST', body: { consent_version: process.env.PHASE2_CONSENT_VERSION || '2026-09-01' }, expected: 201 });
  check(`${name}: session`, () => validateSchema('Session', data));
  sessions.push(data.access_token);
  return data.access_token;
}
const create = (name, token, body = input(), options = {}) => http(name, '/v1/requests', { method: 'POST', token, body, idempotency: key(), expected: 201, ...options });
const get = (name, token, id, suffix = '', options = {}) => http(name, `/v1/requests/${id}${suffix}`, { token, expected: 200, ...options });
const cancel = (name, token, id, options = {}) => get(name, token, id, '/cancel', { method: 'POST', ...options });
const answer = (name, token, draft, body, options = {}) => get(name, token, draft.request_id, '/clarifications', { method: 'POST', idempotency: key(), body, ...options });

async function functional() {
  const owner = await guest('owner guest');
  const other = await guest('other guest');
  const idempotency = key();
  const request = await create('supported create', owner, input(), { idempotency });
  check('extraction and initial progress', () => {
    assert.equal(request.status, 'submitted');
    assert.equal(request.constraints.category, 'barber');
    assert.equal(request.constraints.budget_cents, 3500);
    assert.ok(Math.abs(Date.parse(request.constraints.needed_by) - Date.now() - 1800000) < 15000);
    assert.deepEqual(request.progress, { contacted: 0, replied: 0, offers_ready: 0 });
  });
  const replay = await create('create replay', owner, input(), { idempotency });
  check('replay is byte-equivalent canonical body', () => assert.deepEqual(replay, request));
  await create('create key conflict', owner, input({ text: 'Beauty' }), { idempotency, expected: 409, error: 'conflict', detail: 'idempotency_key_reused' });
  for (const [suffix, method, body] of [['', 'GET'], ['/offers', 'GET'], ['/cancel', 'POST'], ['/clarifications', 'POST', { clarification_id: 'cla_unknown', value: 'barber' }]]) {
    for (const [actor, token, id] of [['foreign', other, request.request_id], ['missing', owner, 'req_missing'], ['malformed', owner, 'invalid']]) {
      await get(`${actor} ${method} ${suffix || 'resource'}`, token, id, suffix, { method, body, idempotency: method === 'POST' && suffix === '/clarifications' ? key() : undefined, expected: 404, error: 'not_found' });
    }
    await get(`anonymous ${method} ${suffix || 'resource'}`, undefined, request.request_id, suffix, { method, body, idempotency: key(), expected: 401, error: 'unauthenticated' });
  }
  await create('anonymous create', undefined, input(), { expected: 401, error: 'unauthenticated' });
  let current = request;
  let lastProgress = request.progress;
  const deadline = Date.now() + 45000;
  while (current.next_action === 'wait_for_offers' && Date.now() < deadline) {
    await sleep(current.poll_after_seconds * 1000);
    current = await get('poll seeded work', owner, request.request_id);
    check('progress counts never go backwards', () => {
      for (const field of Object.keys(lastProgress)) assert.ok(current.progress[field] >= lastProgress[field]);
    });
    lastProgress = current.progress;
  }
  check('seeded result becomes actionable', () => { assert.equal(current.status, 'ranked'); assert.ok(current.progress.contacted > 0); assert.ok(current.progress.offers_ready > 0); });
  const offers = await get('seeded offers', owner, request.request_id, '/offers');
  check('seed offers remain honest and within constraints', () => {
    assert.ok(offers.offers.length > 0);
    for (const offer of offers.offers) {
      assert.equal(offer.source, 'seed');
      assert.ok(['estimated', 'unknown'].includes(offer.truth_label));
      assert.ok(offer.price_cents <= current.constraints.budget_cents);
      assert.ok(offer.place.distance_m <= current.constraints.max_distance_m);
      assert.ok(Date.parse(offer.available_at) <= Date.parse(current.constraints.needed_by));
    }
  });
  const draft = await create('ambiguous create', owner, input({ text: 'Something nearby under $35' }));
  check('one blocking category question', () => { assert.equal(draft.status, 'draft'); assert.equal(draft.clarification.field, 'category'); });
  const empty = await get('draft offers empty', owner, draft.request_id, '/offers');
  check('no offers before clarification', () => assert.deepEqual(empty.offers, []));
  const body = { clarification_id: draft.clarification.clarification_id, value: 'barber' };
  await answer('missing clarification idempotency', owner, draft, body, { idempotency: undefined, expected: 400, error: 'validation_failed' });
  await answer('invalid option', owner, draft, { ...body, value: 'astronaut' }, { expected: 400, error: 'validation_failed', detail: 'not_an_option' });
  await answer('wrong clarification identifier', owner, draft, { ...body, clarification_id: 'cla_wrong' }, { expected: 409, error: 'conflict', detail: 'not_awaiting_clarification' });
  const answerKey = key();
  const answered = await answer('answer category', owner, draft, body, { idempotency: answerKey });
  check('answer preserves identity and removes question', () => { assert.equal(answered.request_id, draft.request_id); assert.equal(answered.status, 'submitted'); assert.equal(answered.clarification, undefined); assert.equal(answered.constraints.category, 'barber'); });
  const answeredReplay = await answer('answer replay', owner, draft, body, { idempotency: answerKey });
  check('answer replay unchanged', () => assert.deepEqual(answeredReplay, answered));
  await answer('different answer same key', owner, draft, { ...body, value: 'beauty' }, { idempotency: answerKey, expected: 409, error: 'conflict', detail: 'idempotency_key_reused' });
  await answer('no second clarification', owner, draft, body, { expected: 409, error: 'conflict', detail: 'not_awaiting_clarification' });
  const canceled = await cancel('cancel ranked', owner, request.request_id);
  check('canceled next action', () => { assert.equal(canceled.status, 'canceled'); assert.equal(canceled.next_action, 'none'); });
  const repeated = await cancel('cancel repeat', owner, request.request_id);
  check('cancel is idempotent without key', () => assert.deepEqual(repeated, canceled));
  const pending = await create('draft cancellation create', owner, input({ text: 'Something nearby' }));
  const canceledDraft = await cancel('cancel unanswered draft', owner, pending.request_id);
  check('cancel retains missing category', () => { assert.equal(canceledDraft.constraints.category, null); assert.equal(canceledDraft.clarification, undefined); });
  await answer('oversized clarification body', owner, pending, undefined, { raw: JSON.stringify({ clarification_id: pending.clarification.clarification_id, value: 'x'.repeat(17000) }), expected: 413, error: 'validation_failed' });
  await answer('clarification media type', owner, pending, undefined, { raw: '{}', contentType: 'text/plain', expected: 415, error: 'validation_failed' });
  await cancel('oversized cancellation body', owner, pending.request_id, { raw: 'x'.repeat(17000), expected: 413, error: 'validation_failed' });
  await answer('answer after cancel', owner, pending, { clarification_id: pending.clarification.clarification_id, value: 'barber' }, { expected: 409, error: 'conflict', detail: 'not_awaiting_clarification' });
  const midflight = await create('midflight create', other);
  const canceledFlight = await cancel('midflight cancel', other, midflight.request_id);
  await sleep(2500);
  const stable = await get('cancellation survives worker', other, midflight.request_id);
  check('worker cannot resurrect canceled request', () => assert.deepEqual(stable, canceledFlight));
  const raceKey = key();
  await pace(other);
  await pace(other);
  const race = await Promise.all([0, 1].map(async index => {
    // Concurrent duplicates may replay 201 or receive the documented in-progress 409.
    const response = await fetch(new URL('/v1/requests', base), { method: 'POST', headers: { Authorization: `Bearer ${other}`, 'Content-Type': 'application/json', 'Idempotency-Key': raceKey, 'X-Request-Id': `qa_${randomUUID()}` }, body: JSON.stringify(input()), signal: AbortSignal.timeout(15000) });
    const data = await response.json();
    report.exchanges.push({ case: `concurrent duplicate ${index}`, method: 'POST', route: '/v1/requests', status: response.status, correlation_id: response.headers.get('x-request-id') });
    check(`concurrent duplicate ${index}: documented contract`, () => { assert.ok([201, 409].includes(response.status)); validateSchema(response.status === 201 ? 'RequestResource' : 'Error', data); if (response.status === 409) assert.ok(data.error.details.some(d => d.code === 'request_in_progress')); });
    if (response.status === 201) created.push({ token: other, id: data.request_id });
    return data;
  }));
  check('concurrent duplicates create exactly one visible resource', () => { const successes = race.filter(r => r.request_id); assert.ok(successes.length > 0); assert.equal(new Set(successes.map(r => r.request_id)).size, 1); });
  const emptyRequests = [
    ['no coverage', await create('out-of-zone create', other, input({ location: { latitude: 0, longitude: 0, precision: 'coarse' } })), 'no_coverage'],
    ['no eligible offers', await create('no affordable offers create', other, input({ budget_cents: 500, currency: 'USD' })), 'no_offers'],
  ];
  for (const [name, resource, reason] of emptyRequests) {
    let state = resource;
    const timeout = Date.now() + 45000;
    while (state.next_action === 'wait_for_offers' && Date.now() < timeout) {
      await sleep(state.poll_after_seconds * 1000);
      state = await get(`${name} poll`, other, resource.request_id);
    }
    check(`${name}: honest terminal reason`, () => { assert.equal(state.status, 'expired'); assert.equal(state.no_result_reason, reason); });
    const emptyOffers = await get(`${name} offers`, other, resource.request_id, '/offers');
    check(`${name}: no fabricated offers`, () => assert.deepEqual(emptyOffers.offers, []));
    await cancel(`${name} cannot cancel expired`, other, resource.request_id, { expected: 409, error: 'conflict', detail: 'not_cancelable' });
  }
  await pace(other);
  const expiring = await create('expiring unanswered draft', other, input({ text: 'Something nearby', needed_by: new Date(Date.now() + 2000).toISOString() }), { paced: false });
  await sleep(2200);
  const expired = await get('unanswered draft expiration', other, expiring.request_id);
  check('unanswered draft retains null category', () => { assert.equal(expired.status, 'expired'); assert.equal(expired.no_result_reason, 'clarification_unanswered'); assert.equal(expired.constraints.category, null); });
  await answer('answer expired question', other, expiring, { clarification_id: expiring.clarification.clarification_id, value: 'barber' }, { expected: 409, error: 'conflict', detail: 'not_awaiting_clarification' });
  return owner;
}

async function dataset() {
  let owner;
  let index = 0;
  const rows = readFileSync(new URL('../fixtures/intents/p2.jsonl', import.meta.url), 'utf8').trim().split('\n').map(JSON.parse).filter(row => row.provider === 'normal');
  for (const row of rows) {
    if (index++ % 8 === 0) owner = await guest(`dataset guest batch ${Math.ceil(index / 8)}`);
    await pace(owner);
    const body = structuredClone(row.input);
    const shift = Date.now() - Date.parse(row.now);
    if (body.needed_by && /(?:Z|[+-]\d\d:\d\d)$/.test(body.needed_by) && Number.isFinite(Date.parse(body.needed_by))) body.needed_by = new Date(Date.parse(body.needed_by) + shift).toISOString();
    const expected = row.expected;
    const response = await create(`dataset ${row.id}`, owner, body, { paced: false, expected: expected.status || 201, error: expected.error_code, detail: expected.detail_code });
    if (expected.outcome !== 'rejected') check(`dataset ${row.id}: canonical extraction`, () => {
      assert.equal(response.status, expected.outcome);
      for (const field of ['category', 'budget_cents']) if (Object.hasOwn(expected, field)) assert.equal(response.constraints[field], expected[field]);
      if (Object.hasOwn(expected, 'needed_by')) {
        if (expected.needed_by === null) assert.equal(response.constraints.needed_by, null);
        else assert.ok(Math.abs(Date.parse(response.constraints.needed_by) - Date.parse(expected.needed_by) - shift) < 15000);
      }
      if (expected.clarification_field) assert.equal(response.clarification.field, expected.clarification_field);
    });
  }
  report.dataset = { normal_provider_cases: rows.length, injected_provider_cases: 'Backend deterministic adapter tests; not simulated by this HTTP suite.' };
}

// Manual v4 P2.S10 to P2.S17: one ask field for both ask types, the restricted-intent policy,
// public places only, one clarifying question, and provider capability on the same account.
async function asks() {
  const owner = await guest('ask owner');
  const other = await guest('ask other');
  const ask = (name, token, text, options = {}) => http(name, '/v1/asks', { method: 'POST', token, body: { text, location, time_zone: 'America/Chicago' }, idempotency: key(), expected: 201, ...options });
  const askKey = key();
  const service = await ask('ask service request', owner, 'Someone to do knotless braids, $120 max', { idempotency: askKey });
  check('service ask is classified and extracted from the vocabulary', () => {
    assert.equal(service.ask_type, 'service_request');
    assert.ok(service.request.constraints.skill_tags.includes('braids'));
    assert.ok(service.request.constraints.skill_tags.every(tag => vocabulary.has(tag)));
    assert.equal(service.request.constraints.budget_cents, 12000);
  });
  const replay = await ask('ask replay', owner, 'Someone to do knotless braids, $120 max', { idempotency: askKey });
  check('ask replay is the same canonical body', () => assert.deepEqual(replay, service));
  await ask('ask key conflict', owner, 'Fix a leaking sink today', { idempotency: askKey, expected: 409, error: 'conflict', detail: 'idempotency_key_reused' });
  const place = await ask('ask place question', owner, 'How long is the line at Walmart on Ben White?');
  check('place question is classified, public, and never promotes the web', () => {
    assert.equal(place.ask_type, 'place_question');
    assert.ok(place.place_question.place_name);
    assert.ok(['asking', 'unknown'].includes(place.place_question.status));
    assert.equal(place.place_question.answer ?? null, null);
    if (place.place_question.web_answer) assert.equal(place.place_question.web_answer.truth_label, 'not_verified');
  });
  await ask('restricted ask refused', owner, "Track my ex girlfriend's phone", { expected: 422, error: 'restricted_intent' });
  await ask('private place refused', owner, 'How busy is it at her apartment right now?', { expected: 422, error: 'restricted_intent' });
  await ask('anonymous ask', undefined, 'Barber', { expected: 401, error: 'unauthenticated' });
  await http('read own ask', `/v1/asks/${service.ask_id}`, { token: owner, expected: 200 });
  await http('foreign ask', `/v1/asks/${service.ask_id}`, { token: other, expected: 404, error: 'not_found' });
  await http('anonymous ask read', `/v1/asks/${service.ask_id}`, { expected: 401, error: 'unauthenticated' });
  const unclear = await ask('unclear ask', owner, 'Something');
  // Without a model reading the ask, a service nobody lists or offers gets the one question:
  // the rules cannot tell a new trade from a harmful ask in new words (0.6.1).
  const own = await ask('unlisted service without a model', owner, 'Someone to regrout my bathroom tiles under $80');
  check('unlisted service without a model asks the one question', () => {
    assert.equal(own.ask_type, null);
    assert.equal(own.clarification.field, 'ask');
    assert.equal(own.request, undefined);
  });
  for (const text of ['Pay someone to beat up my roommate', 'Need painkillers, the strong kind, no doctor involved',
    'Install a hidden camera in my roommate\'s room', 'Someone to watch my two kids while I\'m at work']) {
    await ask(`reworded refusal: ${text}`, owner, text, { expected: 422, error: 'restricted_intent' });
  }
  check('unclear ask gets exactly one question', () => {
    assert.equal(unclear.ask_type, null);
    assert.equal(unclear.clarification.field, 'ask');
    assert.ok(unclear.clarification.options.every(option => option.value === 'place_question' || vocabulary.has(option.value)));
  });
  const clarify = (name, token, value, options = {}) => http(name, `/v1/asks/${unclear.ask_id}/clarifications`, { method: 'POST', token, body: { clarification_id: unclear.clarification.clarification_id, value }, idempotency: key(), expected: 200, ...options });
  await clarify('foreign clarification', other, 'barber', { expected: 404, error: 'not_found' });
  await clarify('clarification outside the options', owner, 'wizardry', { expected: 400, error: 'validation_failed' });
  const resolved = await clarify('answer the one question', owner, 'barber');
  check('answer resolves the same ask', () => { assert.equal(resolved.ask_id, unclear.ask_id); assert.equal(resolved.ask_type, 'service_request'); assert.deepEqual(resolved.request.constraints.skill_tags, ['barber']); });
  await clarify('no second question', owner, 'barber', { expected: 409, error: 'conflict' });

  await http('not a provider yet', '/v1/providers/me', { token: other, expected: 404, error: 'not_found' });
  const proposal = await http('propose skills', '/v1/providers/skills/propose', { method: 'POST', token: other, body: { description: 'I do knotless braids and wig installs, also crochet locs and chimney sweeping' }, expected: 200 });
  check('proposal uses only vocabulary tags and reports the rest', () => {
    assert.deepEqual(proposal.skills.map(skill => skill.tag).sort(), ['braids', 'locs', 'wig_install']);
    assert.ok(proposal.unmatched.includes('chimney sweeping'));
  });
  await http('restricted skill description', '/v1/providers/skills/propose', { method: 'POST', token: other, body: { description: 'I sell stolen phones' }, expected: 422, error: 'restricted_intent' });
  const setup = { skill_tags: ['braids', 'wig_install'], travel_radius_m: 4828, base_location: location, availability: [{ days: 'every_day', from: '08:00', to: '21:00' }], time_zone: 'America/Chicago' };
  await http('licensed skill without licence', '/v1/providers/skills', { method: 'POST', token: other, body: { ...setup, skill_tags: ['electrical'] }, expected: 400, error: 'validation_failed', detail: 'licence_required' });
  await http('invented skill tag', '/v1/providers/skills', { method: 'POST', token: other, body: { ...setup, skill_tags: ['wizardry'] }, expected: 400, error: 'validation_failed', detail: 'unknown_skill' });
  const profile = await http('become a provider', '/v1/providers/skills', { method: 'POST', token: other, body: setup, expected: 200 });
  check('same account, new provider is never scored zero', () => {
    assert.equal(profile.score.state, 'new');
    assert.notEqual(profile.score.value, 0);
    assert.ok(profile.accepting);
  });
  const me = await http('read own provider profile', '/v1/providers/me', { token: other, expected: 200 });
  check('provider profile reads back', () => assert.deepEqual(me, profile));
  // Optional public business details (provider-supplied, never verified, links opened only on a tap).
  const business = { name: 'Studio B', about: 'Knotless braids and wig installs.', links: [{ label: 'Website', url: 'https://example.com/studio-b' }] };
  await http('business link must be https', '/v1/providers/skills', { method: 'POST', token: other, body: { ...setup, business: { ...business, links: [{ label: 'Website', url: 'http://example.com' }] } }, expected: 400, error: 'validation_failed' });
  const withBusiness = await http('save business details', '/v1/providers/skills', { method: 'POST', token: other, body: { ...setup, business }, expected: 200 });
  check('business details read back as sent', () => assert.deepEqual(withBusiness.business, business));
  const kept = await http('omitting business keeps it', '/v1/providers/skills', { method: 'POST', token: other, body: setup, expected: 200 });
  check('omitted business is preserved', () => assert.deepEqual(kept.business, business));
  const cleared = await http('empty business removes it', '/v1/providers/skills', { method: 'POST', token: other, body: { ...setup, business: {} }, expected: 200 });
  check('empty business removes every public detail', () => assert.ok(!cleared.business || Object.keys(cleared.business).length === 0));
  // Staff inspection (P2-TWO.S12) is closed to every identity this phase issues.
  for (const route of ['/v1/admin/skills', '/v1/admin/skills/gaps', '/v1/admin/classifications', '/v1/admin/refusals']) {
    await http(`anonymous ${route}`, route, { expected: 401, error: 'unauthenticated' });
    await http(`guest ${route}`, route, { token: other, expected: 403, error: 'forbidden' });
  }
  // Staff accounts (ADR-013): customer sessions never manage staff, and a server without
  // staff email refuses sign-in rather than pretending a code was sent.
  await http('anonymous staff list', '/v1/admin/staff', { expected: 401, error: 'unauthenticated' });
  await http('guest staff list', '/v1/admin/staff', { token: other, expected: 403, error: 'forbidden' });
  await http('guest staff invite', '/v1/admin/staff/invites', { method: 'POST', token: other, body: { email: 'x@example.com', role: 'owner' }, expected: 403, error: 'forbidden' });
  await http('guest staff disable', `/v1/admin/staff/usr_${randomUUID()}/disable`, { method: 'POST', token: other, expected: 403, error: 'forbidden' });
  await http('staff login without mail', '/v1/staff/login', { method: 'POST', body: { email: 'nobody@example.com', password: 'not a real password' }, expected: 503, error: 'dependency_unavailable' });
  await http('staff login malformed', '/v1/staff/login', { method: 'POST', body: {}, expected: 400, error: 'validation_failed' });
  await http('staff unknown challenge', '/v1/staff/login/verify', { method: 'POST', body: { challenge_id: `slc_${randomUUID()}`, code: '123456' }, expected: 400, error: 'validation_failed', detail: 'expired' });
  await http('staff unknown invitation', '/v1/staff/invites/accept', { method: 'POST', body: { invite_token: 'sti_not-a-real-invitation', password: 'a long and unusual phrase' }, expected: 400, error: 'validation_failed', detail: 'expired' });
  // Skills in the provider's own words (ADR-011), found by an ask's keywords; listed skills always win.
  const ownWords = { ...setup, skill_tags: [], custom_skills: ['chimney sweeping'] };
  await http('direct licensed skill still requires a licence', '/v1/providers/skills', { method: 'POST', token: other, body: { ...ownWords, custom_skills: ['electrician work'] }, expected: 400, error: 'validation_failed', detail: 'licence_required' });
  const direct = await http('direct listed skill resolves to vocabulary', '/v1/providers/skills', { method: 'POST', token: other, body: { ...ownWords, custom_skills: ['Wig install'] }, expected: 200 });
  check('direct skill uses canonical matching', () => {
    assert.deepEqual(direct.skills.map(skill => skill.tag), ['wig_install']);
    assert.deepEqual(direct.custom_skills, []);
  });
  await http('unsafe custom skill refused', '/v1/providers/skills', { method: 'POST', token: other, body: { ...ownWords, custom_skills: ['selling stolen phones'] }, expected: 422, error: 'restricted_intent' });
  const sweeper = await http('save a skill in own words', '/v1/providers/skills', { method: 'POST', token: other, body: ownWords, expected: 200 });
  check('own-words skill reads back', () => { assert.deepEqual(sweeper.custom_skills, ['Chimney sweeping']); assert.equal(sweeper.skills.length, 0); });
  const chimney = await ask('ask finds an own-words skill', owner, 'Can someone sweep my chimney tomorrow?');
  check('ask routed to the provider-described skill', () => {
    assert.equal(chimney.ask_type, 'service_request');
    assert.equal(chimney.request.constraints.category, 'custom_chimney_sweep');
    assert.equal(chimney.request.constraints.service_name, 'Chimney sweeping');
  });
}

async function abuse() {
  let owner = await guest('abuse schema guest');
  const bad = [
    ['numeric text', { text: 123 }], ['null text', { text: null }], ['null location', { location: null }],
    ['unknown nested field', { location: { ...location, altitude: 1 } }], ['string coordinate', { location: { ...location, latitude: '32.528' } }],
    ['fractional radius', { max_distance_m: 100.5 }], ['invalid precision', { location: { ...location, precision: 'exact' } }],
    ['missing category remains untrusted', { category: null }], ['boolean budget', { budget_cents: true, currency: 'USD' }],
  ];
  for (const [name, fields] of bad) await create(`abuse ${name}`, owner, input(fields), { expected: 400, error: 'validation_failed' });
  owner = await guest('abuse grammar guest');
  for (const [name, text] of [
    ['fractional-cent text', 'Barber under $35.999'], ['negative text budget', 'Barber under $-5'],
    ['malformed comma text budget', 'Barber under $1,00'], ['conflicting text budgets', 'Barber under $35 or $40'],
    ['fractional relative time', 'Barber in 1.5 minutes'], ['negative relative time', 'Barber in -1 hours'],
    ['zero relative time', 'Barber in 0 minutes'], ['oversized relative time', 'Barber in 9999999 hours'],
    ['conflicting relative times', 'Barber in 20 minutes or in 30 minutes'],
  ]) await create(`abuse ${name}`, owner, input({ text }), { expected: 400, error: 'validation_failed' });
  owner = await guest('abuse overrides guest');
  const override = await create('authoritative budget overrides invalid extraction', owner, input({ text: 'Barber under $999', budget_cents: 3500, currency: 'USD' }));
  check('explicit budget is authoritative', () => assert.equal(override.constraints.budget_cents, 3500));
  await pace(owner);
  const explicitTime = new Date(Date.now() + 1800000).toISOString();
  const timeOverride = await create('authoritative deadline overrides invalid extraction', owner, input({ text: 'Barber in -3 minutes', needed_by: explicitTime }), { paced: false });
  check('explicit deadline is authoritative', () => assert.equal(Date.parse(timeOverride.constraints.needed_by), Date.parse(explicitTime)));
  owner = await guest('abuse transport guest');
  await create('missing idempotency', owner, input(), { idempotency: undefined, expected: 400, error: 'validation_failed' });
  for (const [name, idempotency] of [['space', 'bad key'], ['short', 'short'], ['long', 'a'.repeat(129)], ['punctuation', 'bad-key-with-dot.']]) await create(`malformed idempotency ${name}`, owner, input(), { idempotency, expected: 400, error: 'validation_failed' });
  await create('oversized body', owner, undefined, { raw: JSON.stringify(input({ text: 'x'.repeat(17000) })), expected: 413, error: 'validation_failed' });
  await create('malformed JSON', owner, undefined, { raw: '{', expected: 400, error: 'validation_failed' });
  await create('duplicate JSON property', owner, undefined, { raw: '{"text":"Barber","text":"Beauty","location":' + JSON.stringify(location) + '}', expected: 400, error: 'validation_failed' });
  await create('wrong media type', owner, undefined, { raw: '{}', contentType: 'text/plain', expected: 415, error: 'validation_failed' });
}

async function limits() {
  console.log('Waiting for a clean creation window before rate-limit assertions.');
  await sleep(windowMs);
  const tokens = await Promise.all(['rate A', 'rate B', 'rate C', 'rate D'].map(guest));
  for (let i = 0; i < 10; i++) await create(`account limit allowed ${i + 1}`, tokens[0], input(), { paced: false });
  await create('account creation limit', tokens[0], input(), { paced: false, expected: 429, error: 'rate_limited' });
  // Start a fresh window so account-denied requests cannot affect address accounting.
  console.log('Waiting for a clean address-rate window.');
  await sleep(windowMs);
  let readable;
  for (let i = 0; i < 30; i++) {
    const result = await create(`address limit allowed ${i + 1}`, tokens[Math.floor(i / 10)], input(), { paced: false });
    if (i === 0) readable = result.request_id;
  }
  await create('caller address creation limit', tokens[3], input(), { paced: false, expected: 429, error: 'rate_limited', headers: { 'X-Forwarded-For': '203.0.113.90', 'X-Real-IP': '203.0.113.91' } });
  for (let i = 0; i < 60; i++) await get(`read limit allowed ${i + 1}`, tokens[0], readable, '', { paced: false });
  await get('caller read limit', tokens[0], readable, '', { paced: false, expected: 429, error: 'rate_limited' });
  await get('offers read limit', tokens[0], readable, '/offers', { paced: false, expected: 429, error: 'rate_limited' });
  await cancel('cancel mutation limit', tokens[0], readable, { paced: false, expected: 429, error: 'rate_limited' });
  await get('clarification mutation limit', tokens[0], readable, '/clarifications', { method: 'POST', body: { clarification_id: 'cla_unknown', value: 'barber' }, idempotency: key(), paced: false, expected: 429, error: 'rate_limited' });
}

try {
  await functional();
  await asks();
  await dataset();
  await abuse();
  await limits();
} catch (error) {
  // Only our named checks are emitted; response content/AssertionError objects are never serialized.
  report.failure = /^(Check failed: |Transport failed: |Non-JSON response: )/.test(error.message) ? error.message : 'Unexpected runner failure (inspect locally; no sensitive payload emitted).';
  process.exitCode = 1;
} finally {
  for (const token of sessions) {
    try { await fetch(new URL('/v1/auth/logout', base), { method: 'POST', headers: { Authorization: `Bearer ${token}` }, signal: AbortSignal.timeout(5000) }); } catch { /* disposable runtime teardown remains the owner's responsibility */ }
  }
  report.finished_at = new Date().toISOString();
  report.passed = !report.failure && report.checks.every(c => c.passed);
  report.summary = { passed: report.checks.filter(c => c.passed).length, failed: report.checks.filter(c => !c.passed).length, exchanges: report.exchanges.length };
  if (output) writeFileSync(output, JSON.stringify(report, null, 2) + '\n');
  console.log(JSON.stringify({ suite: report.suite, passed: report.passed, checks_passed: report.summary.passed, checks_failed: report.summary.failed, exchanges: report.summary.exchanges, ...(report.failure ? { failure: report.failure } : {}) }));
}
