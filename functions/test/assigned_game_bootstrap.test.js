'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const {Firestore, GeoPoint, Timestamp} = require('firebase-admin/firestore');
const {
  buildAssignedGameBootstrapDto,
  evaluateAssignedGameBootstrapRead,
} = require('../lib/domain/assigned_game_bootstrap');
const {authorityGrantKey} = require('../lib/domain/scoped_authority');

const authorityFixture = JSON.parse(fs.readFileSync(
  path.join(__dirname, '../../contracts/official_stats/v2/authority_fixtures.json'),
  'utf8',
));
const bootstrapFixture = JSON.parse(fs.readFileSync(
  path.join(__dirname, '../../contracts/official_stats/v2/assigned_game_bootstrap_fixtures.json'),
  'utf8',
));
const evaluationTime = new Date(authorityFixture.evaluationAnchor);
const timestamp = (value) => Timestamp.fromDate(new Date(value));
const offlineFirestore = new Firestore({projectId: 'demo-hoopsconnect'});

function materializeControlVector(vector) {
  const control = {
    ...(vector.origin === 'association' ? authorityFixture.associationControlBase : authorityFixture.seasonControlBase),
    ...(vector.patch || {}),
  };
  for (const key of vector.removeKeys || []) delete control[key];
  return control;
}

function materializeGrantContainer(kind) {
  switch (kind) {
  case 'nullPrototype': return Object.create(null);
  case 'timestamp': return Timestamp.now();
  case 'geoPoint': return new GeoPoint(18.0179, -76.8099);
  case 'documentReference': return offlineFirestore.doc('associations/jba');
  case 'date': return new Date(authorityFixture.evaluationAnchor);
  case 'map': return new Map();
  case 'set': return new Set();
  case 'customPrototype': return Object.create({inheritedGrant: true});
  case 'throwingPrototype': return new Proxy({}, {getPrototypeOf: () => { throw new Error('prototype trap'); }});
  default: throw new Error(`unknown grant-container vector: ${kind}`);
  }
}

function grant(scopeKind = 'division', changes = {}) {
  const value = {
    grantId: `grant-stats-enter-${scopeKind}`,
    capability: 'stats.enter',
    scopeKind,
    associationId: 'jba',
    status: 'active',
    membershipVersion: 7,
    effectiveFrom: timestamp('2026-01-01T00:00:00.000Z'),
    effectiveTo: null,
  };
  if (scopeKind !== 'association') Object.assign(value, {competitionId: 'nbl', seasonId: 's2026'});
  if (scopeKind === 'division') value.divisionId = 'premier';
  return Object.assign(value, changes);
}

function envelope(origin, grants = {}, changes = {}) {
  const base = origin === 'association' ? authorityFixture.associationEnvelopeBase : authorityFixture.seasonEnvelopeBase;
  return {...base, grants, ...changes};
}

function snapshots(changes = {}) {
  const selected = grant();
  return {
    membership: {...authorityFixture.membershipBase, capabilities: ['stats.enter']},
    associationControl: {...authorityFixture.associationControlBase},
    associationAccess: envelope('association'),
    seasonControl: {...authorityFixture.seasonControlBase},
    seasonAccess: envelope('season', {[authorityGrantKey(selected)]: selected}),
    game: {...authorityFixture.gameBase},
    assignment: {...authorityFixture.assignmentBase},
    ...changes,
  };
}

function decide(changes = {}, request = bootstrapFixture.requestBase, uid = 'operator', time = evaluationTime) {
  return evaluateAssignedGameBootstrapRead(snapshots(changes), uid, request, time);
}

function assertAllowed(decision, origin) {
  assert.equal(decision.kind, 'assignedGameBootstrapReadAllowed');
  assert.equal(decision.grant.origin, origin);
  return decision;
}

test('shared request is exact, fixed-purpose, bounded, and rejects caller-selected authority inputs', () => {
  assert.equal(bootstrapFixture.fixtureVersion, 1);
  assertAllowed(decide(), 'season');
  for (const forbidden of bootstrapFixture.forbiddenRequestKeys) {
    const request = {...bootstrapFixture.requestBase, [forbidden]: forbidden === 'uid' ? 'operator' : 'forged'};
    assert.equal(decide({}, request).code, 'invalid_request', forbidden);
  }
  for (const request of [
    {...bootstrapFixture.requestBase, readSchemaVersion: 1},
    {...bootstrapFixture.requestBase, locator: {...bootstrapFixture.requestBase.locator, gameId: 'bad/id'}},
    {...bootstrapFixture.requestBase, locator: {...bootstrapFixture.requestBase.locator, extra: 'x'}},
    {readSchemaVersion: 2},
  ]) assert.deepEqual(decide({}, request), {
    kind: 'assignedGameBootstrapReadDenied', code: 'invalid_request',
  });
  assert.deepEqual(decide({}, {...bootstrapFixture.requestBase, padding: 'x'.repeat(5000)}), {
    kind: 'assignedGameBootstrapReadDenied', code: 'request_too_large',
  });
});

test('division, season, and association origins select deterministically with independent invalid or expired narrower leaves', () => {
  assertAllowed(decide(), 'season');

  const season = grant('season');
  const invalidDivision = {...grant('division'), divisionId: undefined};
  assertAllowed(decide({
    seasonAccess: envelope('season', {
      'stats.enter|division|premier': invalidDivision,
      [authorityGrantKey(season)]: season,
    }),
  }), 'season');

  const association = grant('association', {effectiveTo: timestamp('2100-01-01T00:00:00.000Z')});
  const expiredDivision = grant('division', {effectiveTo: timestamp('2026-02-01T00:00:00.000Z')});
  const expiredSeason = grant('season', {effectiveTo: timestamp('2026-02-01T00:00:00.000Z')});
  assertAllowed(decide({
    associationAccess: envelope('association', {[authorityGrantKey(association)]: association}),
    seasonAccess: envelope('season', {
      [authorityGrantKey(expiredDivision)]: expiredDivision,
      [authorityGrantKey(expiredSeason)]: expiredSeason,
    }),
  }), 'association');
});

test('selected-origin policy permits absent or valid unusable unused sources but rejects present malformed envelopes', () => {
  const association = grant('association');
  const associationAccess = envelope('association', {[authorityGrantKey(association)]: association});
  assertAllowed(decide({associationAccess, seasonAccess: undefined}), 'association');
  assertAllowed(decide({associationAccess, seasonAccess: envelope('season', {}, {membershipVersion: 6})}), 'association');
  assertAllowed(decide({associationAccess, seasonAccess: envelope('season', {}, {status: 'revoked'})}), 'association');
  assert.equal(decide({associationAccess: {...associationAccess, grants: []}}).code, 'scope_denied');
  assert.equal(decide({associationAccess: {...associationAccess, extra: true}}).code, 'scope_denied');

  const division = grant('division');
  const seasonAccess = envelope('season', {[authorityGrantKey(division)]: division});
  assertAllowed(decide({associationAccess: undefined, seasonAccess}), 'season');
  assertAllowed(decide({associationAccess: envelope('association', {}, {status: 'revoked'}), seasonAccess}), 'season');
  assert.equal(decide({associationAccess: {...envelope('association'), grants: []}, seasonAccess}).code, 'scope_denied');
});

test('shared grant-container vectors fail closed for every non-map Firestore representation', () => {
  const association = grant('association');
  const associationAccess = envelope('association', {[authorityGrantKey(association)]: association});
  for (const vector of authorityFixture.grantContainerVectors) {
    const decision = decide({
      associationAccess,
      seasonAccess: envelope('season', materializeGrantContainer(vector.kind)),
    });
    assert.equal(
      decision.kind === 'assignedGameBootstrapReadAllowed',
      vector.expectedValid,
      vector.name,
    );
  }
});

test('shared malformed-control vectors fail closed before bootstrap compatibility normalization', () => {
  for (const vector of authorityFixture.controlShapeVectors) {
    const field = vector.origin === 'association' ? 'associationControl' : 'seasonControl';
    const decision = decide({[field]: materializeControlVector(vector)});
    assert.equal(
      decision.kind === 'assignedGameBootstrapReadAllowed',
      vector.expectedValid,
      vector.name,
    );
  }
});

test('shared selected-origin access-state vectors execute against the Admin evaluator', () => {
  for (const vector of bootstrapFixture.accessSourceVectors) {
    const division = grant('division');
    const season = grant('season');
    const association = grant('association');
    let associationGrants = {};
    let seasonGrants = {};
    if (vector.winner === 'division') seasonGrants = {[authorityGrantKey(division)]: division};
    if (vector.winner === 'season') {
      seasonGrants = {
        'stats.enter|division|premier': {...division, divisionId: undefined},
        [authorityGrantKey(season)]: season,
      };
    }
    if (vector.winner === 'association') {
      associationGrants = {[authorityGrantKey(association)]: association};
      seasonGrants = {
        [authorityGrantKey(division)]: {...division, status: 'revoked'},
        [authorityGrantKey(season)]: {...season, status: 'revoked'},
      };
    }
    const accessFor = (origin, state, grants) => {
      if (state === 'absent') return undefined;
      if (state === 'stale') return envelope(origin, grants, {membershipVersion: 6});
      if (state === 'revoked') return envelope(origin, grants, {status: 'revoked'});
      if (state === 'malformed') return {...envelope(origin, grants), extra: true};
      return envelope(origin, grants);
    };
    const decision = decide({
      associationAccess: accessFor('association', vector.associationState, associationGrants),
      seasonAccess: accessFor('season', vector.seasonState, seasonGrants),
    });
    assert.equal(
      decision.kind === 'assignedGameBootstrapReadAllowed',
      vector.expectedAllowed,
      vector.name,
    );
    if (vector.expectedAllowed) {
      const expectedOrigin = vector.winner === 'association' ? 'association' : 'season';
      assert.equal(decision.grant.origin, expectedOrigin, vector.name);
    }
  }
});

test('64-slot maximum fallback succeeds with four maximum-length calculator IDs and maximum-length authority identifiers', () => {
  const identifier = (prefix) => prefix + prefix.toLowerCase().repeat(127);
  const uid = identifier('U');
  const associationId = identifier('A');
  const competitionId = identifier('C');
  const seasonId = identifier('S');
  const gameId = identifier('G');
  const divisionId = identifier('D');
  const phaseId = identifier('P');
  const homeTeamEntryId = identifier('H');
  const awayTeamEntryId = identifier('W');
  const calculators = ['K', 'L', 'M', 'N'].map(identifier);
  const commonGrant = {
    capability: 'stats.enter', associationId, status: 'active', membershipVersion: 7,
    effectiveFrom: timestamp('2026-01-01T00:00:00.000Z'),
  };
  const expiredDivision = {
    ...commonGrant, grantId: identifier('I'), scopeKind: 'division', competitionId,
    seasonId, divisionId, effectiveTo: timestamp('2026-02-01T00:00:00.000Z'),
  };
  const expiredSeason = {
    ...commonGrant, grantId: identifier('J'), scopeKind: 'season', competitionId,
    seasonId, effectiveTo: timestamp('2026-02-01T00:00:00.000Z'),
  };
  const associationWinner = {
    ...commonGrant, grantId: identifier('O'), scopeKind: 'association',
    effectiveTo: timestamp('2100-01-01T00:00:00.000Z'),
  };
  const associationGrants = {'stats.enter|association': associationWinner};
  const seasonGrants = {
    [`stats.enter|division|${divisionId}`]: expiredDivision,
    'stats.enter|season': expiredSeason,
  };
  for (let index = 0; index < 31; index += 1) associationGrants[`unused-a-${index}`] = {ignored: true};
  for (let index = 0; index < 30; index += 1) seasonGrants[`unused-s-${index}`] = {ignored: true};
  assert.equal(Object.keys(associationGrants).length + Object.keys(seasonGrants).length, 64);
  const customSnapshots = {
    membership: {authorizationSchemaVersion: 2, associationId, status: 'active', membershipVersion: 7, capabilities: ['stats.enter']},
    associationControl: {...authorityFixture.associationControlBase, associationId, acceptedCalculatorVersions: calculators},
    seasonControl: {...authorityFixture.seasonControlBase, associationId, competitionId, seasonId, acceptedCalculatorVersions: calculators},
    associationAccess: {...authorityFixture.associationEnvelopeBase, uid, associationId, grants: associationGrants},
    seasonAccess: {...authorityFixture.seasonEnvelopeBase, uid, associationId, competitionId, seasonId, grants: seasonGrants},
    game: {...authorityFixture.gameBase, associationId, competitionId, seasonId, divisionId, phaseId, gameId, homeTeamEntryId, awayTeamEntryId},
    assignment: {...authorityFixture.assignmentBase, uid, associationId, competitionId, seasonId, divisionId, phaseId, gameId, homeTeamEntryId, awayTeamEntryId, duties: ['submit', 'enter']},
  };
  const request = {readSchemaVersion: 2, locator: {associationId, competitionId, seasonId, gameId}};
  const decision = evaluateAssignedGameBootstrapRead(customSnapshots, uid, request, evaluationTime);
  assertAllowed(decision, 'association');
  assert.equal(decision.accessSources.association.accessVersion, 3);
  assert.equal(decision.accessSources.season.accessVersion, 5);
});

test('controls remain mandatory while bootstrap needs no calculator or client expected versions', () => {
  for (const field of ['associationControl', 'seasonControl']) {
    for (const authorityMode of [undefined, null, 'disabled', 'shadow', 'unknown']) {
      const base = snapshots();
      base[field] = authorityMode === undefined ? undefined : {...base[field], authorityMode};
      const decision = evaluateAssignedGameBootstrapRead(base, 'operator', bootstrapFixture.requestBase, evaluationTime);
      assert.notEqual(decision.kind, 'assignedGameBootstrapReadAllowed');
    }
  }
  assertAllowed(decide({
    associationControl: {...authorityFixture.associationControlBase, acceptedCalculatorVersions: []},
    seasonControl: {...authorityFixture.seasonControlBase, acceptedCalculatorVersions: []},
  }), 'season');
  const allowed = assertAllowed(decide({
    associationControl: {...authorityFixture.associationControlBase, acceptedCalculatorVersions: ['calc-v1']},
    seasonControl: {...authorityFixture.seasonControlBase, acceptedCalculatorVersions: ['calc-v2']},
  }), 'season');
  assert.deepEqual(buildAssignedGameBootstrapDto(allowed).compatibility.acceptedCalculatorVersions, []);
});

test('canonical game and exact 15-field assignment reject stale, swapped, foreign, and extra facts', () => {
  for (const game of [
    {...authorityFixture.gameBase, associationId: 'other'},
    {...authorityFixture.gameBase, divisionId: 'bad/id'},
    {...authorityFixture.gameBase, phaseId: ''},
    {...authorityFixture.gameBase, homeTeamEntryId: 'team-a', awayTeamEntryId: 'team-a'},
    {...authorityFixture.gameBase, teamEntryIds: ['team-a', 'team-b']},
    {...authorityFixture.gameBase, controlVersion: Number.MAX_SAFE_INTEGER + 1},
  ]) assert.equal(decide({game}).code, 'game_control_denied');
  for (const assignment of [
    {...authorityFixture.assignmentBase, uid: 'other'},
    {...authorityFixture.assignmentBase, homeTeamEntryId: 'team-b', awayTeamEntryId: 'team-a'},
    {...authorityFixture.assignmentBase, membershipVersion: 6},
    {...authorityFixture.assignmentBase, writerEpoch: Number.MAX_SAFE_INTEGER + 1},
    {...authorityFixture.assignmentBase, duties: ['submit']},
    {...authorityFixture.assignmentBase, extra: true},
  ]) assert.equal(decide({assignment}).code, 'assignment_denied');
});

test('trusted half-open time, grant-map bound, membership capability, and tenant fences fail closed', () => {
  const startsNow = grant('division', {
    effectiveFrom: timestamp(authorityFixture.boundaries.startsAt),
    effectiveTo: timestamp(authorityFixture.boundaries.endsAt),
  });
  assertAllowed(decide({
    seasonAccess: envelope('season', {[authorityGrantKey(startsNow)]: startsNow}),
  }, bootstrapFixture.requestBase, 'operator', new Date(authorityFixture.boundaries.startsAt)), 'season');
  assert.equal(decide({
    seasonAccess: envelope('season', {[authorityGrantKey(startsNow)]: startsNow}),
  }, bootstrapFixture.requestBase, 'operator', new Date(authorityFixture.boundaries.endsAt)).code, 'grant_inactive');

  const invalidInterval = grant('division', {
    effectiveFrom: timestamp('2026-07-01T00:00:00.000Z'),
    effectiveTo: timestamp('2026-06-01T00:00:00.000Z'),
  });
  assert.equal(decide({
    seasonAccess: envelope('season', {[authorityGrantKey(invalidInterval)]: invalidInterval}),
  }).code, 'grant_inactive');

  const selected = grant();
  const overBound = {[authorityGrantKey(selected)]: selected};
  for (let index = 0; index < 64; index += 1) overBound[`unrelated-${index}`] = {};
  assert.equal(decide({seasonAccess: envelope('season', overBound)}).code, 'scope_denied');
  assert.equal(decide({
    membership: {...authorityFixture.membershipBase, capabilities: [], role: 'superAdmin'},
  }).code, 'capability_denied');
  assert.equal(decide({}, {
    readSchemaVersion: 2,
    locator: {...bootstrapFixture.requestBase.locator, associationId: 'other'},
  }).code, 'unsupported_schema');
});

test('DTO uses the exact shared allowlist, sorted intersection, privacy boundary, and deep immutability', () => {
  const allowed = assertAllowed(decide({
    associationControl: {...authorityFixture.associationControlBase, acceptedCalculatorVersions: ['calc-z', 'calc-a', 'calc-b']},
    seasonControl: {...authorityFixture.seasonControlBase, acceptedCalculatorVersions: ['calc-a', 'calc-z']},
    assignment: {...authorityFixture.assignmentBase, duties: ['submit', 'enter']},
  }), 'season');
  const dto = buildAssignedGameBootstrapDto(allowed);
  assert.deepEqual(dto, bootstrapFixture.dtoBase);
  assert.deepEqual(Object.keys(dto), bootstrapFixture.dtoKeys);
  assert.equal(JSON.stringify(dto).includes('grants'), false);
  assert.equal(JSON.stringify(dto).includes('capabilities'), false);
  assert.equal(JSON.stringify(dto).includes('authorizedToWrite'), false);
  assert.equal(Buffer.byteLength(JSON.stringify(dto)), 610);
  assert.ok(Buffer.byteLength(JSON.stringify(dto)) <= bootstrapFixture.responseByteLimit);
  assert.equal(Object.isFrozen(dto), true);
  assert.equal(Object.isFrozen(dto.scope), true);
  assert.equal(Object.isFrozen(dto.assignment.duties), true);
  assert.throws(() => { dto.scope.gameId = 'mutated'; }, TypeError);
  assert.throws(() => { dto.compatibility.acceptedCalculatorVersions.push('mutated'); }, TypeError);
});
