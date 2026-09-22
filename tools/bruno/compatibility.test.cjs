// Exercise Bruno's integrations with the patched major-version overrides.
const assert = require('node:assert/strict');
const test = require('node:test');
const { parseCSV } = require('@usebruno/cli/src/utils/filesystem');
const { generateGrpcSampleMessage } = require('@usebruno/requests');

test('Bruno still parses quoted CSV iteration data with the patched parser', async () => {
  const rows = await parseCSV('\uFEFFquery,count\n"hello, world",2\n\n');
  assert.deepEqual(rows, [{ query: 'hello, world', count: '2' }]);
});

test('Bruno can generate primitive and repeated values with patched Faker', () => {
  const result = generateGrpcSampleMessage({ requestType: { field: [
    { name: 'number', type: 'TYPE_FLOAT' },
    { name: 'enabled', type: 'TYPE_BOOL' },
    { name: 'text', type: 'TYPE_STRING' },
    { name: 'bytes', type: 'TYPE_BYTES' },
    { name: 'items', type: 'TYPE_INT32', label: 'LABEL_REPEATED' },
  ] } }, { arraySize: 2 });
  assert.equal(typeof result.number, 'number');
  assert.equal(typeof result.enabled, 'boolean');
  assert.ok(result.text.length > 0);
  assert.ok(Buffer.from(result.bytes, 'base64').length >= 5);
  assert.equal(result.items.length, 2);
  assert.ok(result.items.every(Number.isInteger));
});
