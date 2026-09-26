'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {buildPlan} = require('../import_jbl_results');

test('rejects a result referencing an unknown team before any write', () => {
  const backup = {records: [{path: 'associations/jba', data: {
    currentSeasonId: '2025', leagueCatalogV1: {leagues: [{leagueId: 'jbl', historicalStatistics: true}]},
  }}]};
  assert.throws(() => buildPlan(backup, {games: [{sides: [{teamId: 'unknown'}, {teamId: 'other'}]}]}));
});

test('refuses an association without the expected historical league', () => {
  assert.throws(() => buildPlan({records: [{path: 'associations/jba', data: {leagueCatalogV1: {leagues: []}}}]}, {games: []}));
});
