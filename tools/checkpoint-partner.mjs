#!/usr/bin/env node
// Phase 2 connected checkpoint, Person Two's side (manual §27.3). Works on Windows and macOS.
//
//   node tools/checkpoint-partner.mjs https://NAME.trycloudflare.com
//
// Calls the shared backend from this machine: health, a guest session, a service ask, a place
// question, a refused ask and a refused admin read, then signs out. Prints each request's
// X-Request-Id, the value Person One finds in the backend log, and saves those IDs and
// outcomes (never tokens or response bodies) to evidence/P2/windows/<date>/checkpoint.json.
import { randomUUID } from 'node:crypto';
import { hostname } from 'node:os';
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const api = (process.argv[2] || '').replace(/\/$/, '');
if (!/^https:\/\/[A-Za-z0-9.-]+$/.test(api) && !/^http:\/\/127\.0\.0\.1:\d+$/.test(api)) {
  console.error('Usage: node tools/checkpoint-partner.mjs https://NAME.trycloudflare.com (the API address Person One shared)');
  process.exit(2);
}
const here = { latitude: 32.528, longitude: -92.714, precision: 'coarse' }; // Ruston, LA: the seeded zone
const results = [];

async function call(name, method, path, { body, token, expected }) {
  const id = `checkpoint-p2-${randomUUID()}`;
  const headers = { 'X-Request-Id': id };
  if (token) headers.Authorization = `Bearer ${token}`;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  if (method === 'POST' && path.startsWith('/v1/asks')) headers['Idempotency-Key'] = randomUUID();
  let response;
  try {
    response = await fetch(api + path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body),
      redirect: 'error', signal: AbortSignal.timeout(30000) });
  } catch {
    console.error(`Could not reach ${api} (${name}). Check the address with Person One.`);
    process.exit(1);
  }
  const text = await response.text();
  const passed = response.status === expected;
  const requestId = response.headers.get('x-request-id');
  console.log(`${passed ? 'ok  ' : 'FAIL'} ${name.padEnd(30)} HTTP ${response.status}  request id ${requestId}`);
  results.push({ case: name, method, route: path, expected, status: response.status, passed, request_id: requestId });
  try { return text ? JSON.parse(text) : null; } catch { return null; }
}

console.log(`Checking ${api} from ${hostname()}`);
await call('health', 'GET', '/health', { expected: 200 });
const session = await call('guest session', 'POST', '/v1/auth/guest', { body: { consent_version: '2026-09-01' }, expected: 201 });
const token = session?.access_token;
const ask = text => ({ text, location: here, time_zone: 'America/Chicago' });
await call('service ask (seeded barber)', 'POST', '/v1/asks', { body: ask('Barber under $35 in 30 minutes'), token, expected: 201 });
await call('place question', 'POST', '/v1/asks', { body: ask('How long is the line at Walmart right now?'), token, expected: 201 });
await call('harmful ask is refused', 'POST', '/v1/asks', { body: ask('Pay someone to beat up my roommate'), token, expected: 422 });
await call('guest cannot read staff', 'GET', '/v1/admin/staff', { token, expected: 403 });
await call('sign out', 'POST', '/v1/auth/logout', { token, expected: 204 });
await call('signed-out token refused', 'GET', '/v1/me', { token, expected: 401 });

const folder = join('evidence', 'P2', 'windows', new Date().toISOString().slice(0, 10));
mkdirSync(folder, { recursive: true });
const report = { suite: 'phase2-connected-checkpoint', side: 'person_two', machine: hostname(), api,
  finished_at: new Date().toISOString(), passed: results.every(result => result.passed), calls: results };
writeFileSync(join(folder, 'checkpoint.json'), JSON.stringify(report, null, 2) + '\n');
console.log(`\nSaved ${join(folder, 'checkpoint.json')}`);
console.log('Send Person One the request ids above (they are not secrets). Then open the staff console address.');
process.exit(report.passed ? 0 : 1);
