// Supplier SMS copy, the reply grammar and its regression cases are one artefact
// (manual §27.4). These checks keep them consistent with each other and with the
// contract; the backend parser (P3.S5) runs the cases themselves.
import assert from 'node:assert/strict';
import test from 'node:test';
import { contract, readJSON } from './validate.mjs';

const templates = readJSON('contracts/messages/templates.v1.json');
const grammar = readJSON('contracts/messages/grammar.v1.json');
const suite = readJSON('contracts/messages/cases.v1.json');
const schemas = contract.components.schemas;

// GSM 03.38 basic character set. Anything else (emoji, curly quotes, dashes, or the
// extension table's {}[]~^|\ and €) changes the encoding or the length of a text.
const GSM7 = new Set([...'@£$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞÆæßÉ !"#¤%&\'()*+,-./0123456789:;<=>?¡'
  + 'ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà']);
const placeholders = text => [...text.matchAll(/\{([a-z_]+)\}/g)].map(match => match[1]);
const longest = text => text.replace(/\{([a-z_]+)\}/g, (_, name) => 'W'.repeat(templates.placeholders[name].max));
const keywords = new Set(Object.values(grammar.keywords).flat());
const words = body => body.normalize('NFKC').toUpperCase().trim().split(/\s+/)
  .map(word => word.replace(/^[^A-Z0-9$]+|[^A-Z0-9]+$/g, '')).filter(Boolean);

for (const [id, template] of Object.entries(templates.sms)) {
  test(`sms ${id} fits two GSM-7 segments with its longest values`, () => {
    for (const name of placeholders(template.body)) {
      assert.ok(templates.placeholders[name], `Undeclared placeholder {${name}}`);
    }
    const rendered = longest(template.body);
    assert.ok(rendered.length <= templates.limits.sms_max_rendered_chars,
      `${rendered.length} characters when rendered at maximum`);
    for (const char of rendered) assert.ok(GSM7.has(char), `Not GSM-7: ${JSON.stringify(char)}`);
    for (const name of placeholders(template.body)) {
      const example = templates.placeholders[name].example;
      assert.ok(example.length <= templates.placeholders[name].max, `{${name}} example too long`);
      for (const char of example) assert.ok(GSM7.has(char), `Not GSM-7 in {${name}} example`);
    }
  });

  test(`sms ${id} says who is texting and asks only for words the grammar reads`, () => {
    assert.match(template.body, /^PLUG[: ]/);
    const asked = template.body.replace(/\{[a-z_]+\}/g, '').match(/\b[A-Z]{2,}\b/g) ?? [];
    for (const word of asked.filter(word => word !== 'PLUG')) {
      assert.ok(keywords.has(word), `${id} asks for ${word}, which the grammar does not read`);
    }
  });
}

test('every text that can start a conversation says how to stop', () => {
  for (const id of ['optin_confirm', 'outreach']) assert.match(templates.sms[id].body, /\bSTOP\b/);
  assert.match(templates.sms.help.body, /\bSTOP\b/);
  assert.match(templates.sms.stop_confirm.body, /\bSTART\b/);
});

test('every hint, confirmation and keyword reply named by the grammar exists', () => {
  for (const id of ['offer_received', 'offer_incomplete', 'offer_over_budget', 'offer_outside_window',
    'unparseable', 'request_closed', 'booked', 'released', 'stop_confirm', 'optin_confirmed',
    'pause_confirm', 'help', 'reservation_request', 'reservation_timed_out', 'reservation_canceled']) {
    assert.ok(templates.sms[id], `Missing template ${id}`);
  }
});

test('the push alert fits the contract and carries nothing about the asker', () => {
  const { title, body } = templates.push.provider_match;
  const alert = schemas.ProviderMatchNotification.properties.aps.properties.alert.properties;
  assert.ok(longest(title).length <= Math.min(templates.limits.push_title_max, alert.title.maxLength));
  assert.ok(longest(body).length <= Math.min(templates.limits.push_body_max, alert.body.maxLength));
  for (const name of placeholders(title + body)) assert.ok(['service', 'distance', 'window'].includes(name), name);
});

test('the consent version is one the contract accepts', () => {
  assert.match(templates.consent_version, new RegExp(schemas.SupplierOptIn.properties.consent_version.pattern));
});

test('the cases cover every parse result and every keyword, with unique ids', () => {
  const ids = suite.cases.map(item => item.id);
  assert.equal(new Set(ids).size, ids.length);
  assert.equal(suite.grammar, grammar.version);
  const results = new Set(suite.cases.map(item => item.expect.result));
  assert.deepEqual([...results].sort(), [...schemas.InboundParseResult.enum].sort());
  const used = new Set(suite.cases.flatMap(item => words(item.body)));
  for (const keyword of keywords) assert.ok(used.has(keyword), `No case uses ${keyword}`);
});

for (const item of suite.cases) {
  test(`case ${item.id} is well formed`, () => {
    const context = { ...suite.defaults, ...item.context };
    assert.ok(['outreach', 'reservation', 'none'].includes(context.kind));
    assert.ok(schemas.InboundParseResult.enum.includes(item.expect.result));
    if (context.kind === 'reservation') assert.match(context.ref, new RegExp(schemas.Reservation.properties.booking_ref.pattern));
    if (item.expect.result === 'offer') {
      assert.equal(context.kind, 'outreach');
      const { min, max } = grammar.offer.price_dollars;
      assert.ok(Number.isInteger(item.expect.price_cents));
      assert.ok(item.expect.price_cents >= min * 100 && item.expect.price_cents <= max * 100);
      if (context.budget_cents !== null) assert.ok(item.expect.price_cents <= context.budget_cents);
      const at = Date.parse(item.expect.available_at);
      assert.match(item.expect.available_at, /Z$/);
      assert.ok(at >= Date.parse(context.received_at) - 60_000, 'Offer time before the reply');
      assert.ok(at <= Date.parse(context.received_at) + 24 * 3_600_000, 'Offer time beyond 24 hours');
      if (context.needed_by !== null) assert.ok(at <= Date.parse(context.needed_by), 'Offer time after needed_by');
    } else {
      assert.equal(item.expect.price_cents, undefined);
    }
    if (['stop', 'start', 'help'].includes(item.expect.result)) {
      assert.ok(['twilio', 'plug'].includes(item.expect.reply_by));
      const exact = item.expect.result === 'stop' ? grammar.keywords.opt_out_exact
        : item.expect.result === 'start' ? grammar.keywords.opt_in_exact : grammar.keywords.help_first;
      const whole = words(item.body).join(' ');
      assert.equal(item.expect.reply_by === 'twilio', exact.includes(whole), 'Twilio replies only to an exact keyword');
    }
    if (context.message_sid_seen) assert.equal(item.expect.result, 'duplicate');
  });
}
