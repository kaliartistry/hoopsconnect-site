'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');

const {PINS, parseMajor} = require('../qa/toolchain');

test('local QA pins the same toolchain versions as CI', () => {
  assert.deepEqual(PINS, {
    nodeMajor: 22,
    javaMajor: 21,
    flutter: '3.41.2',
    dart: '3.11.0',
    firebaseCli: '15.8.0',
  });
});

test('toolchain version diagnostics parse Node and Java formats', () => {
  assert.equal(parseMajor('v22.22.2', 'Node'), 22);
  assert.equal(parseMajor('openjdk version "21.0.3" 2024-04-16', 'Java'), 21);
  assert.throws(() => parseMajor('unknown', 'runtime'), /Could not parse runtime/);
});
