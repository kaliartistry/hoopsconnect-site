'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {canPublishLegacy} = require('../lib/legacy_live');
test('live compatibility publisher is closed without exact server approval', () => {
  const valid = {schemaVersion: 1, enabled: true, maintenance: false,
    associationId: 'jba', contractVersion: 'legacy-public-snapshot-v1.1'};
  assert.equal(canPublishLegacy(valid), true);
  for (const invalid of [undefined, {}, {...valid, maintenance: true},
    {...valid, enabled: false}, {...valid, associationId: 'other'},
    {...valid, contractVersion: 'public-release-v2'}]) {
    assert.equal(canPublishLegacy(invalid), false);
  }
});
