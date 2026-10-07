#!/usr/bin/env node
// Staff accounts from the terminal (ADR-013), until the web console exists.
//
//   node tools/staff.mjs accept               choose a password with an emailed invitation code
//   node tools/staff.mjs login                email + password, then the emailed six-digit code
//   node tools/staff.mjs list                 every staff account
//   node tools/staff.mjs invite <email> [staff|owner]
//   node tools/staff.mjs disable <user_id>
//   node tools/staff.mjs logout
//
// PLUG_API_URL picks the server (default http://127.0.0.1:18080). Passwords are typed
// hidden and never stored. The staff session is kept in secrets/staff-session.json (owner
// only, gitignored) and never printed.
import { chmodSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { stdin, stdout } from 'node:process';
import { createInterface } from 'node:readline';

const base = process.env.PLUG_API_URL || 'http://127.0.0.1:18080';
const sessionFile = new URL('../secrets/staff-session.json', import.meta.url);

function ask(question, hidden = false) {
  return new Promise(resolve => {
    const rl = createInterface({ input: stdin, output: stdout, terminal: true });
    if (hidden) rl._writeToOutput = text => { if (text.startsWith(question)) stdout.write(question); };
    rl.question(question, answer => { rl.close(); if (hidden) stdout.write('\n'); resolve(answer.trim()); });
  });
}

async function call(method, path, body, token) {
  const headers = { 'Content-Type': 'application/json' };
  if (token) headers.Authorization = `Bearer ${token}`;
  const response = await fetch(new URL(path, base), { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  const text = await response.text();
  const data = text ? JSON.parse(text) : null;
  if (!response.ok) {
    const error = data?.error;
    const detail = error?.details?.[0] ? ` (${error.details[0].field}: ${error.details[0].code})` : '';
    throw new Error(`${response.status} ${error?.code || ''}: ${error?.message || 'request failed'}${detail}`);
  }
  return data;
}

function saved() {
  if (!existsSync(sessionFile)) throw new Error('Not signed in. Run: node tools/staff.mjs login');
  return JSON.parse(readFileSync(sessionFile, 'utf8'));
}

// Refreshes when the 15-minute access token has run out; a staff refresh lasts 12 hours.
async function token() {
  let session = saved();
  if (Date.parse(session.access_token_expires_at) - Date.now() < 30000) {
    session = await call('POST', '/v1/auth/refresh', { refresh_token: session.refresh_token });
    store(session);
  }
  return session.access_token;
}

function store(session) {
  mkdirSync(new URL('../secrets/', import.meta.url), { recursive: true });
  writeFileSync(sessionFile, JSON.stringify(session), { mode: 0o600 });
  chmodSync(sessionFile, 0o600);
}

const [command, ...args] = process.argv.slice(2);
try {
  switch (command) {
    case 'accept': {
      const invite = await ask('Invitation code (sti_…): ');
      const password = await ask('New password (12–64 characters): ', true);
      if (password !== await ask('Repeat password: ', true)) throw new Error('The passwords differ.');
      await call('POST', '/v1/staff/invites/accept', { invite_token: invite, password });
      console.log('Your staff account is ready. Sign in with: node tools/staff.mjs login');
      break;
    }
    case 'login': {
      const email = await ask('Email: ');
      const password = await ask('Password: ', true);
      const challenge = await call('POST', '/v1/staff/login', { email, password });
      console.log('If the email and password are right, a six-digit code is on its way.');
      const code = await ask('Code: ');
      const session = await call('POST', '/v1/staff/login/verify', { challenge_id: challenge.challenge_id, code });
      store(session);
      console.log(`Signed in as ${session.account.type} until ${session.refresh_token_expires_at}.`);
      break;
    }
    case 'list': {
      const { staff } = await call('GET', '/v1/admin/staff', undefined, await token());
      for (const member of staff) console.log(`${member.user_id}  ${member.role.padEnd(5)}  ${member.status.padEnd(8)}  ${member.email}`);
      break;
    }
    case 'invite': {
      const [email, role = 'staff'] = args;
      if (!email) throw new Error('Usage: node tools/staff.mjs invite <email> [staff|owner]');
      const invite = await call('POST', '/v1/admin/staff/invites', { email, role }, await token());
      console.log(`Invited ${invite.email} as ${invite.role}; the email link works until ${invite.expires_at}.`);
      break;
    }
    case 'disable': {
      const [userId] = args;
      if (!userId) throw new Error('Usage: node tools/staff.mjs disable <user_id>');
      await call('POST', `/v1/admin/staff/${encodeURIComponent(userId)}/disable`, undefined, await token());
      console.log('Disabled. Their sessions have ended.');
      break;
    }
    case 'logout': {
      await call('POST', '/v1/auth/logout', undefined, await token()).catch(() => {});
      rmSync(sessionFile, { force: true });
      console.log('Signed out.');
      break;
    }
    default:
      console.log('Usage: node tools/staff.mjs accept | login | list | invite <email> [staff|owner] | disable <user_id> | logout');
  }
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
