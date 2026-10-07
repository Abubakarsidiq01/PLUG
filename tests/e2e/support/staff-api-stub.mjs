#!/usr/bin/env node
// A stand-in for the PLUG API, for the staff console's browser tests only. It serves the
// synthetic fixtures in /fixtures and knows one made-up staff member, so the tests need no
// backend, database or email. It listens on loopback and holds nothing real.
//
//   email staff@example.com, password "stub staff password", code 123456
//   email reader@example.com signs in, then every admin read is refused (403)
//   email down@example.com gets 503, as when staff email is not configured
//   staff@example.com is the owner in the Staff list; inviting taken@example.com is a conflict
import { createServer } from 'node:http';
import { readFileSync } from 'node:fs';

const port = Number(process.env.PLUG_STUB_API_PORT || 3102);
const fixture = (folder, name) => JSON.parse(readFileSync(new URL(`../../../fixtures/${folder}/${name}.json`, import.meta.url), 'utf8'));
const requestId = 'req_stub-0001';
const error = (code, message, extra = {}) => ({ error: { code, message, request_id: requestId, ...extra } });

const people = {
  'staff@example.com': { token: 'stub-access-staff', refresh: 'stub-refresh-staff' },
  'reader@example.com': { token: 'stub-access-refused', refresh: 'stub-refresh-refused' },
};
const challenges = new Map(); // challenge id -> email
// The Staff list starts as the fixture; staff@example.com is its owner (the first row).
const staffList = fixture('admin.staff.list', 'success').staff.map((member, index) =>
  index === 0 ? { ...member, email: 'staff@example.com' } : member);
const ownerId = staffList[0].user_id;
let issued = 0;
const revoked = new Set();

function session(person) {
  const soon = minutes => new Date(Date.now() + minutes * 60000).toISOString();
  return {
    access_token: person.token,
    access_token_expires_at: soon(15),
    refresh_token: person.refresh,
    refresh_token_expires_at: soon(720),
    account: { user_id: person === people['staff@example.com'] ? ownerId : 'usr_stub-reader', type: 'staff', scopes: ['admin'] },
    consent: { ...fixture('auth.guest', 'success').consent, accepted_version: null },
  };
}

const pages = {
  '/v1/admin/skills': 'admin.skills',
  '/v1/admin/skills/gaps': 'admin.gaps',
  '/v1/admin/classifications': 'admin.classifications',
  '/v1/admin/refusals': 'admin.refusals',
};

async function body(request) {
  let text = '';
  for await (const chunk of request) text += chunk;
  try { return text ? JSON.parse(text) : {}; } catch { return null; }
}

createServer(async (request, response) => {
  const url = new URL(request.url, `http://${request.headers.host}`);
  const send = (status, payload) => {
    response.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'X-Request-Id': requestId });
    response.end(payload === undefined ? '' : JSON.stringify(payload));
  };
  const bearer = (request.headers.authorization || '').replace(/^Bearer /, '');

  if (request.method === 'GET' && url.pathname === '/health') return send(200, { status: 'ok' });

  const signedIn = Object.values(people).some(person => person.token === bearer) && !revoked.has(bearer);
  const owner = bearer === people['staff@example.com'].token;

  if (request.method === 'GET' && url.pathname === '/v1/me') {
    if (!signedIn) return send(401, error('unauthenticated', 'Sign in again.'));
    return send(200, { account: session(owner ? people['staff@example.com'] : people['reader@example.com']).account,
      consent: { current_version: '2026-09-01', accepted_version: null } });
  }
  if (request.method === 'GET' && url.pathname === '/v1/admin/staff') {
    if (!signedIn) return send(401, error('unauthenticated', 'Sign in again.'));
    if (!owner) return send(403, fixture('admin.staff.list', 'forbidden'));
    return send(200, { staff: staffList });
  }

  if (request.method === 'GET' && pages[url.pathname]) {
    // An unknown, run-out or revoked token is 401. A real session that may not read is 403.
    const known = Object.values(people).some(person => person.token === bearer);
    if (!known || revoked.has(bearer)) return send(401, error('unauthenticated', 'Sign in again.'));
    if (bearer !== people['staff@example.com'].token) return send(403, fixture(pages[url.pathname], 'forbidden'));
    const page = fixture(pages[url.pathname], 'success');
    // The fixtures hold one page. A second, empty page stands in for "older entries".
    if (url.searchParams.has('cursor')) return send(200, { items: [], next_cursor: null });
    return send(200, page);
  }

  if (request.method !== 'POST') return send(404, error('not_found', 'No such route.'));
  const data = await body(request);
  if (data === null) return send(400, error('validation_failed', 'Malformed JSON.'));

  switch (url.pathname) {
    case '/v1/staff/login': {
      if (data.email === 'down@example.com') return send(503, error('dependency_unavailable', 'Staff email is not configured.', { retry_after_seconds: 60 }));
      const id = `slc_stub-${issued += 1}`;
      // Same answer for a wrong password or an unknown person; only a right one can be verified.
      if (people[data.email] && data.password === 'stub staff password') challenges.set(id, data.email);
      return send(202, { challenge_id: id, expires_at: new Date(Date.now() + 600000).toISOString() });
    }
    case '/v1/staff/login/verify': {
      const email = challenges.get(data.challenge_id);
      if (!email) return send(400, error('validation_failed', 'Start again.', { details: [{ field: 'challenge_id', code: 'expired' }] }));
      if (data.code !== '123456') return send(400, error('validation_failed', 'Wrong code.', { details: [{ field: 'code', code: 'invalid' }] }));
      challenges.delete(data.challenge_id);
      revoked.delete(people[email].token);
      return send(201, session(people[email]));
    }
    case '/v1/staff/invites/accept': {
      if (data.invite_token !== 'sti_stub-invitation') return send(400, error('validation_failed', 'Expired.', { details: [{ field: 'invite_token', code: 'expired' }] }));
      if (/password/i.test(data.password)) return send(400, error('validation_failed', 'Too weak.', { details: [{ field: 'password', code: 'too_weak' }] }));
      return send(204);
    }
    case '/v1/admin/staff/invites': {
      if (!signedIn) return send(401, error('unauthenticated', 'Sign in again.'));
      if (!owner) return send(403, fixture('admin.staff.invite', 'forbidden'));
      if (data.email === 'taken@example.com') return send(409, fixture('admin.staff.invite', 'conflict'));
      // Listed at once, as if the invitation had been accepted, so a test can then disable them.
      if (!staffList.some(item => item.email === data.email)) {
        staffList.push({ user_id: `usr_stub-${staffList.length + 1}`, email: data.email, role: data.role, status: 'active',
          created_at: new Date().toISOString() });
      }
      return send(201, { ...fixture('admin.staff.invite', 'success'), email: data.email, role: data.role });
    }
    case '/v1/auth/refresh': {
      const person = Object.values(people).find(item => item.refresh === data.refresh_token);
      if (!person) return send(401, error('unauthenticated', 'Sign in again.'));
      revoked.delete(person.token);
      return send(200, session(person));
    }
    case '/v1/auth/logout': {
      if (bearer) revoked.add(bearer);
      return send(204);
    }
    default: {
      const disable = url.pathname.match(/^\/v1\/admin\/staff\/(usr_[A-Za-z0-9-]+)\/disable$/);
      if (disable) {
        if (!signedIn) return send(401, error('unauthenticated', 'Sign in again.'));
        if (!owner) return send(403, fixture('admin.staff.disable', 'forbidden'));
        const member = staffList.find(item => item.user_id === disable[1]);
        if (!member) return send(404, fixture('admin.staff.disable', 'not-found'));
        if (member.user_id === ownerId) return send(409, fixture('admin.staff.disable', 'conflict'));
        member.status = 'disabled';
        return send(204);
      }
      return send(404, error('not_found', 'No such route.'));
    }
  }
}).listen(port, '127.0.0.1', () => console.log(`Staff API stub on http://127.0.0.1:${port}`));
