#!/usr/bin/env node
// Runs fixtures/intents/asks.jsonl against POST /v1/asks on a disposable loopback backend.
// Every row runs even after a mismatch, so one run shows every disagreement at once.
// The report holds case ids and outcomes only: no tokens, prompts or coordinates.
import { randomUUID } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { setTimeout as sleep } from 'node:timers/promises';
import { root, validateSchema, vocabulary } from './validate.mjs';

const base = new URL(process.env.PHASE2_BASE_URL || 'http://127.0.0.1:18082');
if (!['127.0.0.1', '[::1]', 'localhost'].includes(base.hostname) || base.protocol !== 'http:' || base.pathname !== '/') {
  throw new Error('PHASE2_BASE_URL must be a plain loopback HTTP origin.');
}
if (process.env.PHASE2_DISPOSABLE !== '1') throw new Error('Set PHASE2_DISPOSABLE=1 only for a fresh disposable database/backend.');

const cases = readFileSync(new URL('fixtures/intents/asks.jsonl', root), 'utf8').trim().split('\n').map(JSON.parse);
const sessions = [];
const results = [];

async function guest() {
  const response = await fetch(new URL('/v1/auth/guest', base), {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ consent_version: process.env.PHASE2_CONSENT_VERSION || '2026-09-01' }),
    signal: AbortSignal.timeout(15000),
  });
  if (response.status !== 201) throw new Error(`Guest sign-in failed with HTTP ${response.status}.`);
  const token = (await response.json()).access_token;
  sessions.push(token);
  return token;
}

// What the server did, reduced to the fields the labels talk about.
function observe(status, body) {
  if (status !== 201) return { status, error_code: body?.error?.code ?? null };
  return {
    status,
    ask_type: body.ask_type,
    skill_tags: body.request?.constraints?.skill_tags ?? null,
    budget_cents: body.request?.constraints?.budget_cents ?? null,
    place_named: body.place_question ? body.place_question.place_name !== null : null,
    clarification_field: body.clarification?.field ?? null,
  };
}

function differences(item, status, body) {
  const expected = item.expected;
  const actual = observe(status, body);
  const found = [];
  if (actual.status !== expected.status) found.push(`status ${actual.status}, expected ${expected.status}`);
  if (expected.status === 422) {
    if (actual.status === 422 && actual.error_code !== expected.error_code) found.push(`error ${actual.error_code}`);
    return found;
  }
  if (actual.status !== 201) return found;
  try { validateSchema('AskResult', body); } catch { found.push('response does not match AskResult'); }
  if (actual.ask_type !== expected.ask_type) found.push(`ask_type ${actual.ask_type}, expected ${expected.ask_type}`);
  if (expected.skill_tags_any_of && actual.skill_tags) {
    if (!actual.skill_tags.every(tag => vocabulary.has(tag) || tag.startsWith('custom_'))) found.push('skill tag outside the vocabulary');
    if (!expected.skill_tags_any_of.some(tag => actual.skill_tags.includes(tag))) found.push(`skill_tags ${JSON.stringify(actual.skill_tags)}`);
  }
  const unwanted = (expected.skill_tags_none_of ?? []).filter(tag => actual.skill_tags?.includes(tag));
  if (unwanted.length) found.push(`unwanted skill ${unwanted.join(', ')}`);
  if (Object.hasOwn(expected, 'budget_cents') && actual.budget_cents !== expected.budget_cents) found.push(`budget_cents ${actual.budget_cents}`);
  if (expected.place_named !== undefined && actual.place_named !== null && actual.place_named !== expected.place_named) found.push(`place_named ${actual.place_named}`);
  if (expected.clarification_field && actual.clarification_field !== expected.clarification_field) found.push(`clarification ${actual.clarification_field}`);
  return found;
}

let token;
for (const [index, item] of cases.entries()) {
  // Stay under the documented limits: ten creations per account and thirty per address a minute.
  if (index % 8 === 0) token = await guest();
  await sleep(2300);
  const correlation = `qa_${randomUUID()}`;
  const response = await fetch(new URL('/v1/asks', base), {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}`, 'Idempotency-Key': `qa-${randomUUID()}`, 'X-Request-Id': correlation },
    body: JSON.stringify(item.input),
    signal: AbortSignal.timeout(15000),
  });
  let body = null;
  try { body = await response.json(); } catch { /* reported as a status difference below */ }
  const found = differences(item, response.status, body);
  results.push({ id: item.id, kind: item.kind, reason: item.expected.reason ?? null, expected: item.expected.status === 422 ? '422 restricted_intent' : `201 ${item.expected.ask_type}`, observed: observe(response.status, body), correlation_id: correlation, agrees: found.length === 0, differences: found });
  console.log(`${found.length === 0 ? 'agrees   ' : 'DIFFERS  '} ${item.id}${found.length ? `: ${found.join('; ')}` : ''}`);
}

for (const session of sessions) {
  try { await fetch(new URL('/v1/auth/logout', base), { method: 'POST', headers: { Authorization: `Bearer ${session}` }, signal: AbortSignal.timeout(5000) }); } catch { /* the disposable runtime is torn down anyway */ }
}

const differing = results.filter(result => !result.agrees);
const byKind = {};
for (const result of results) {
  byKind[result.kind] ??= { cases: 0, agree: 0 };
  byKind[result.kind].cases += 1;
  if (result.agrees) byKind[result.kind].agree += 1;
}
const report = { suite: 'asks-live', environment: 'isolated-local', finished_at: new Date().toISOString(), cases: results.length, agree: results.length - differing.length, differ: differing.length, by_kind: byKind, results };
if (process.env.PHASE2_REPORT) writeFileSync(process.env.PHASE2_REPORT, JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify({ suite: report.suite, cases: report.cases, agree: report.agree, differ: report.differ, by_kind: byKind }));
process.exit(differing.length === 0 ? 0 : 1);
