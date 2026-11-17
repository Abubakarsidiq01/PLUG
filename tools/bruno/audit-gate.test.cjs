const assert = require('node:assert/strict');
const test = require('node:test');
const { blockingAdvisories } = require('./audit-gate.cjs');

const advisory = (id, severity, name = 'pkg') =>
  ({ source: 1, name, severity, title: 't', url: `https://github.com/advisories/${id}` });
const report = (...via) => ({ vulnerabilities: { pkg: { via }, parent: { via: ['pkg'] } } });

test('allows only the documented picomatch advisory', () => {
  assert.deepEqual(blockingAdvisories(report(advisory('GHSA-fc5q-39xc-vjpf', 'high'))), []);
});

test('blocks any other high or critical advisory', () => {
  const found = blockingAdvisories(report(advisory('GHSA-fc5q-39xc-vjpf', 'high'), advisory('GHSA-aaaa-bbbb-cccc', 'critical')));
  assert.equal(found.length, 1);
  assert.match(found[0], /GHSA-aaaa-bbbb-cccc critical/);
});

test('ignores moderate and low advisories', () => {
  assert.deepEqual(blockingAdvisories(report(advisory('GHSA-aaaa-bbbb-cccc', 'moderate'))), []);
});

test('fails closed when npm audit returns an error', () => {
  assert.throws(() => blockingAdvisories({ error: { code: 'ENOAUDIT' } }));
});
