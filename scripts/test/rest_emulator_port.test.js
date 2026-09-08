'use strict';

const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const test = require('node:test');

test('REST seed transports preserve the configured emulator port', () => {
  for (const file of [
    'seed_firestore.js',
    'seed_mock_league.js',
    'seed_nbl.js',
    'seed_season_games.js',
  ]) {
    const source = fs.readFileSync(path.resolve(__dirname, '..', file), 'utf8');
    assert.match(source, /port:\s*url\.port/, file + ' drops the emulator port');
  }
});
