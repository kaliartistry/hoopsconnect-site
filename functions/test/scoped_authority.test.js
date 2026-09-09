'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const {Firestore, GeoPoint, Timestamp} = require('firebase-admin/firestore');
const {
  accessGrantMatchesScope,
  authorityGrantKey,
  capabilityRequirements,
  evaluateScopedAuthority,
  isAuthorityControl,
  isCommandScope,
  isExactScopeForAction,
  isStrictAccessEnvelope,
  isStrictAccessGrant,
  validAuthorityId,
  validAuthorityTeamEntryIds,
} = require('../lib/domain/scoped_authority');

const fixture = JSON.parse(fs.readFileSync(
  path.join(__dirname, '../../contracts/official_stats/v2/authority_fixtures.json'),
  'utf8',
));
const now = new Date(fixture.evaluationAnchor);
const timestamp = (value) => Timestamp.fromDate(new Date(value));
const offlineFirestore = new Firestore({projectId: 'demo-hoopsconnect'});

function materializeControlVector(vector) {
  const control = {
    ...(vector.origin === 'association' ? fixture.associationControlBase : fixture.seasonControlBase),
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
  case 'date': return new Date(fixture.evaluationAnchor);
  case 'map': return new Map();
  case 'set': return new Set();
  case 'customPrototype': return Object.create({inheritedGrant: true});
  case 'throwingPrototype': return new Proxy({}, {getPrototypeOf: () => { throw new Error('prototype trap'); }});
  default: throw new Error(`unknown grant-container vector: ${kind}`);
  }
}

function hydrateGrant(value, hydrateTime = true) {
  const result = {...value};
  if (hydrateTime) {
    result.effectiveFrom = timestamp(result.effectiveFrom);
    result.effectiveTo = result.effectiveTo === null ? null : timestamp(result.effectiveTo);
  }
  return result;
}

function grant(capability, scopeKind, changes = {}) {
  const value = {
    grantId: `grant-${capability.replaceAll('.', '-')}`,
    capability,
    scopeKind,
    associationId: 'jba',
    status: 'active',
    membershipVersion: 7,
    effectiveFrom: timestamp('2026-01-01T00:00:00.000Z'),
    effectiveTo: timestamp('2027-01-01T00:00:00.000Z'),
  };
  if (scopeKind !== 'association') Object.assign(value, {competitionId: 'nbl', seasonId: 's2026'});
  if (scopeKind === 'division' || scopeKind === 'teamEntry') value.divisionId = 'premier';
  if (scopeKind === 'teamEntry') value.teamEntryId = 'team-a';
  return Object.assign(value, changes);
}

function envelope(origin, grants = {}, changes = {}) {
  const base = origin === 'association' ? fixture.associationEnvelopeBase : fixture.seasonEnvelopeBase;
  return {...base, grants, ...changes};
}

function actionContract(capability) {
  return fixture.actionContracts.find((item) => item.capability === capability);
}

function grantKindForAction(contract) {
  if (contract.scope === 'association') return 'association';
  if (contract.scope === 'teamEntry') return 'teamEntry';
  if (contract.scope === 'division' || contract.scope === 'game') return 'division';
  return 'season';
}

function validInput(capability = 'stats.enter') {
  const contract = actionContract(capability);
  const scope = {...fixture.scopes[contract.scope]};
  const selectedGrant = grant(capability, grantKindForAction(contract));
  const key = authorityGrantKey(selectedGrant);
  const associationGrants = selectedGrant.scopeKind === 'association' ? {[key]: selectedGrant} : {};
  const seasonGrants = selectedGrant.scopeKind === 'association' ? {} : {[key]: selectedGrant};
  return {
    uid: 'operator',
    membership: {...fixture.membershipBase, capabilities: [capability]},
    associationControl: {...fixture.associationControlBase},
    associationAccess: envelope('association', associationGrants),
    ...(contract.scope === 'association' ? {} : {
      seasonControl: {...fixture.seasonControlBase},
      seasonAccess: envelope('season', seasonGrants),
    }),
    ...(contract.scope === 'game' ? {
      game: {...fixture.gameBase},
      expectedGameControlVersion: fixture.gameBase.controlVersion,
    } : {}),
    ...(contract.assignment ? {
      assignment: {...fixture.assignmentBase},
      expectedAssignmentVersion: fixture.assignmentBase.assignmentVersion,
      writerEpoch: fixture.assignmentBase.writerEpoch,
    } : {}),
    capability,
    scope,
    versions: {...(contract.calculator === 'required' ? fixture.versionsWithCalculator : fixture.versionsWithoutCalculator)},
    evaluationTime: now,
  };
}

function decide(capability = 'stats.enter', changes = {}) {
  return evaluateScopedAuthority(Object.assign(validInput(capability), changes));
}

test('shared fixture is executable and matches the exact action table', () => {
  assert.equal(fixture.fixtureVersion, 4);
  assert.equal(fixture.safeIntegerMax, Number.MAX_SAFE_INTEGER);
  assert.equal(fixture.actionContracts.length, Object.keys(capabilityRequirements).length);
  for (const contract of fixture.actionContracts) {
    assert.deepEqual(capabilityRequirements[contract.capability], {
      scope: contract.scope,
      calculator: contract.calculator === 'required',
      game: contract.scope === 'game',
      assignment: contract.assignment,
      ...(contract.closed ? {closed: true} : {}),
    });
  }
});

test('shared malformed-control vectors preserve presence and type before normalization', () => {
  for (const vector of fixture.controlShapeVectors) {
    const control = materializeControlVector(vector);
    const scope = fixture.scopes[vector.origin];
    assert.equal(isAuthorityControl(control, scope, vector.origin), vector.expectedValid, `${vector.name} validator`);
    const field = vector.origin === 'association' ? 'associationControl' : 'seasonControl';
    assert.equal(
      evaluateScopedAuthority({...validInput('stats.enter'), [field]: control}).authorized,
      vector.expectedValid,
      `${vector.name} command`,
    );
  }
});

test('shared grant-container vectors accept only plain Firestore map representations', () => {
  const association = grant('stats.enter', 'association');
  const associationAccess = envelope('association', {[authorityGrantKey(association)]: association});
  for (const vector of fixture.grantContainerVectors) {
    const grants = materializeGrantContainer(vector.kind);
    assert.equal(
      isStrictAccessEnvelope(
        envelope('season', grants), 'season', 'operator', fixture.scopes.season,
      ),
      vector.expectedValid,
      `${vector.name} envelope`,
    );
    assert.equal(
      decide('stats.enter', {
        associationAccess,
        seasonAccess: envelope('season', grants),
      }).authorized,
      vector.expectedValid,
      `${vector.name} command`,
    );
  }
});

test('shared grant vectors enforce exact fields, timestamp type, containment, and deterministic keys', () => {
  for (const vector of fixture.grantVectors) {
    const candidate = hydrateGrant({...fixture.grantBase, ...vector.patch}, !vector.doNotHydrateTime);
    const target = fixture.scopes[vector.target];
    assert.equal(isStrictAccessGrant(candidate), vector.expectedShape, `${vector.name} shape`);
    assert.equal(authorityGrantKey(candidate), vector.expectedKey, `${vector.name} key`);
    assert.equal(accessGrantMatchesScope(candidate, target), vector.expectedMatchesTarget, `${vector.name} target`);
  }
});

test('shared envelope, calculator ID, counter, and named-team vectors execute', () => {
  for (const vector of fixture.envelopeVectors) {
    const origin = vector.origin;
    const candidate = {...(origin === 'association' ? fixture.associationEnvelopeBase : fixture.seasonEnvelopeBase), ...vector.patch};
    assert.equal(isStrictAccessEnvelope(candidate, origin, 'operator', fixture.scopes[origin]), vector.expectedValid, vector.name);
  }
  for (const vector of fixture.calculatorIdVectors) assert.equal(validAuthorityId(vector.value), vector.expectedValid, vector.name);
  for (const vector of fixture.teamEntrySetVectors) assert.equal(validAuthorityTeamEntryIds(vector.value), vector.expectedValid, vector.name);
  for (const vector of fixture.counterVectors) {
    const input = validInput('players.manage');
    input.associationControl = {...input.associationControl, controlVersion: vector.value};
    assert.equal(evaluateScopedAuthority(input).authorized, vector.expectedValid, vector.name);
  }
});

test('all action scopes are exact and policy closures stay closed', () => {
  for (const contract of fixture.actionContracts) {
    const input = validInput(contract.capability);
    assert.equal(isCommandScope(input.scope), true, `${contract.capability} union scope`);
    assert.equal(isExactScopeForAction(input.scope, contract.capability), true, `${contract.capability} exact scope`);
    const valid = evaluateScopedAuthority(input);
    assert.equal(valid.authorized, !contract.closed, `${contract.capability} valid decision`);
    if (contract.closed) assert.equal(valid.code, 'policy_gate_closed');
    for (const key of Object.keys(input.scope)) {
      const missing = {...input.scope}; delete missing[key];
      assert.equal(evaluateScopedAuthority({...input, scope: missing}).code, 'invalid_scope', `${contract.capability} missing ${key}`);
      assert.equal(evaluateScopedAuthority({...input, scope: {...input.scope, [key]: null}}).code, 'invalid_scope', `${contract.capability} null ${key}`);
    }
    for (const bad of [{...input.scope, extra: 'x'}, {...input.scope, [Object.keys(input.scope)[0]]: undefined}]) {
      assert.equal(evaluateScopedAuthority({...input, scope: bad}).code, 'invalid_scope', `${contract.capability} extra/undefined`);
    }
  }
});

test('association actions use only association control while lower actions require both exact controls', () => {
  const association = validInput('players.manage');
  assert.equal(evaluateScopedAuthority({...association, seasonControl: {authorityMode: 'disabled'}}).authorized, true);
  assert.equal(evaluateScopedAuthority({...association, associationControl: undefined}).code, 'authority_disabled');
  for (const authorityMode of ['disabled', 'shadow', undefined, null, 'unknown']) {
    const input = validInput('stats.review');
    input.associationControl = {...input.associationControl, authorityMode};
    assert.equal(evaluateScopedAuthority(input).authorized, false, `association ${authorityMode}`);
  }
  for (const authorityMode of ['disabled', 'shadow', undefined, null, 'unknown']) {
    const input = validInput('stats.review');
    input.seasonControl = authorityMode === undefined ? undefined : {...input.seasonControl, authorityMode};
    assert.equal(evaluateScopedAuthority(input).authorized, false, `season ${authorityMode}`);
  }
});

test('independent association, season, and game counters pass while only expected game version fences the game', () => {
  const input = validInput('stats.enter');
  input.associationControl.controlVersion = 2;
  input.seasonControl.controlVersion = 7;
  input.game.controlVersion = 11;
  input.expectedGameControlVersion = 11;
  const decision = evaluateScopedAuthority(input);
  assert.equal(decision.authorized, true);
  assert.equal(decision.associationControlVersion, 2);
  assert.equal(decision.seasonControlVersion, 7);
  assert.equal(decision.game.controlVersion, 11);
  assert.equal(evaluateScopedAuthority({...input, expectedGameControlVersion: 7}).code, 'stale_control_version');
});

test('calculator compatibility is explicit per action and validated by both controls', () => {
  for (const vector of fixture.compatibilityVectors) {
    const capability = vector.required ? 'results.publish' : 'results.retract';
    const input = validInput(capability);
    input.associationControl = {...input.associationControl, acceptedCalculatorVersions: vector.associationAccepted};
    input.seasonControl = {...input.seasonControl, acceptedCalculatorVersions: vector.seasonAccepted};
    input.versions = {...fixture.versionsWithoutCalculator};
    if (!vector.omitCalculator) input.versions.calculatorVersion = vector.calculatorVersion;
    assert.equal(evaluateScopedAuthority(input).authorized, vector.expectedAccepts, vector.name);
  }
});

test('shared calculator allowlist bound accepts 0, 1, 2, or 4 unique IDs and rejects 5, duplicates, and malformed IDs', () => {
  for (const vector of fixture.calculatorAllowlistVectors) {
    const input = validInput('results.retract');
    input.associationControl = {...input.associationControl, acceptedCalculatorVersions: vector.value};
    input.seasonControl = {...input.seasonControl, acceptedCalculatorVersions: vector.value};
    assert.equal(evaluateScopedAuthority(input).authorized, vector.expectedValid, vector.name);
  }
});

test('grant provenance, deterministic slots, narrowing, and 64-entry bound fail closed', () => {
  const associationInSeason = grant('results.retract', 'association');
  assert.equal(decide('results.retract', {
    associationAccess: envelope('association', {}),
    seasonAccess: envelope('season', {[authorityGrantKey(associationInSeason)]: associationInSeason}),
  }).authorized, false);

  const wrongKey = grant('results.retract', 'season');
  assert.equal(decide('results.retract', {seasonAccess: envelope('season', {'results.retract|season-wrong': wrongKey})}).authorized, false);

  const team = grant('stats.review', 'teamEntry');
  assert.equal(decide('stats.review', {seasonAccess: envelope('season', {[authorityGrantKey(team)]: team})}).authorized, false);

  const overBoundAssociation = {};
  const overBoundSeason = {};
  for (let i = 0; i < 33; i += 1) overBoundAssociation[`unrelated-a-${i}`] = {};
  for (let i = 0; i < 32; i += 1) overBoundSeason[`unrelated-s-${i}`] = {};
  const parent = grant('results.retract', 'season');
  overBoundSeason[authorityGrantKey(parent)] = parent;
  assert.equal(decide('results.retract', {
    associationAccess: envelope('association', overBoundAssociation),
    seasonAccess: envelope('season', overBoundSeason),
  }).authorized, false);
});

test('malformed envelopes reject; inactive or stale valid envelopes contribute no authority', () => {
  const input = validInput('results.retract');
  const validAssociationGrant = grant('results.retract', 'association');
  const validAssociation = envelope('association', {[authorityGrantKey(validAssociationGrant)]: validAssociationGrant});
  for (const malformed of [
    {...input.seasonAccess, grants: []},
    {...input.seasonAccess, uid: 'other'},
    {...input.seasonAccess, competitionId: 'other'},
    {...input.seasonAccess, accessVersion: Number.MAX_SAFE_INTEGER + 1},
    {...input.seasonAccess, capabilities: ['results.retract']},
  ]) assert.equal(evaluateScopedAuthority({...input, associationAccess: validAssociation, seasonAccess: malformed}).authorized, false);
  for (const changes of [{status: 'revoked'}, {status: 'suspended'}, {membershipVersion: 6}]) {
    assert.equal(evaluateScopedAuthority({...input, associationAccess: envelope('association', {}, changes), seasonAccess: envelope('season', {}, changes)}).authorized, false);
  }
});

test('candidate grants validate independently and intervals are exactly half-open', () => {
  const input = validInput('games.schedule');
  const seasonParent = grant('games.schedule', 'season', {effectiveFrom: timestamp(fixture.boundaries.startsAt), effectiveTo: timestamp(fixture.boundaries.endsAt)});
  const invalidSpecific = {...grant('games.schedule', 'division'), divisionId: undefined};
  const grants = {
    'games.schedule|division|premier': invalidSpecific,
    [authorityGrantKey(seasonParent)]: seasonParent,
    unrelated: {broken: true},
  };
  assert.equal(evaluateScopedAuthority({...input, seasonAccess: envelope('season', grants), evaluationTime: new Date(fixture.boundaries.startsAt)}).authorized, true);
  assert.equal(evaluateScopedAuthority({...input, seasonAccess: envelope('season', grants), evaluationTime: new Date(fixture.boundaries.endsAt)}).code, 'grant_inactive');
  for (const changes of [
    {status: 'revoked'},
    {effectiveFrom: timestamp('2026-06-02T00:00:00.000Z')},
    {effectiveTo: timestamp('2026-05-31T00:00:00.000Z')},
    {membershipVersion: 6},
  ]) {
    const changed = {...seasonParent, ...changes};
    const result = evaluateScopedAuthority({...input, seasonAccess: envelope('season', {[authorityGrantKey(changed) || 'games.schedule|season']: changed})});
    assert.equal(result.authorized, false);
  }
});

test('populated foreign targets and malformed required grant fields deny through authority', () => {
  const input = validInput('games.schedule');
  const foreign = grant('games.schedule', 'division', {competitionId: 'other'});
  assert.equal(evaluateScopedAuthority({...input, seasonAccess: envelope('season', {[authorityGrantKey(foreign)]: foreign})}).code, 'scope_denied');
  for (const malformed of [
    {...grant('games.schedule', 'division'), divisionId: undefined},
    {...grant('rosters.assert', 'teamEntry'), teamEntryId: undefined},
  ]) {
    const target = malformed.capability === 'rosters.assert' ? validInput('rosters.assert') : input;
    const slot = malformed.capability === 'rosters.assert' ? 'rosters.assert|teamEntry|premier|team-a' : 'games.schedule|division|premier';
    assert.equal(evaluateScopedAuthority({...target, seasonAccess: envelope('season', {[slot]: malformed})}).code, 'scope_denied');
  }
});

test('canonical named teams and complete assignment shape are order-sensitive', () => {
  assert.equal(decide().authorized, true);
  for (const game of [
    {...fixture.gameBase, homeTeamEntryId: 'team-a', awayTeamEntryId: 'team-a'},
    {...fixture.gameBase, homeTeamEntryId: ''},
    {...fixture.gameBase, divisionId: 'other'},
    {...fixture.gameBase, controlVersion: Number.MAX_SAFE_INTEGER + 1},
    {...fixture.gameBase, teamEntryIds: ['team-a', 'team-b']},
  ]) assert.equal(decide('stats.enter', {game}).authorized, false);
  for (const assignment of [
    {...fixture.assignmentBase, homeTeamEntryId: 'team-b', awayTeamEntryId: 'team-a'},
    {...fixture.assignmentBase, uid: 'other'},
    {...fixture.assignmentBase, dataSchemaVersion: 1},
    {...fixture.assignmentBase, duties: ['enter', 'enter']},
    {...fixture.assignmentBase, writerEpoch: Number.MAX_SAFE_INTEGER + 1},
    {...fixture.assignmentBase, unverified: true},
  ]) assert.equal(decide('stats.enter', {assignment}).authorized, false);
});

test('membership and control collections reject invalid, duplicate, unsafe, and malformed values', () => {
  for (const membership of [
    {...fixture.membershipBase, capabilities: ['stats.enter', 'stats.enter']},
    {...fixture.membershipBase, capabilities: ['stats.enter', 'unknown']},
    {...fixture.membershipBase, membershipVersion: Number.MAX_SAFE_INTEGER + 1},
    {...fixture.membershipBase, status: 'revoked'},
  ]) assert.equal(decide('stats.enter', {membership}).authorized, false);
  for (const controlChange of [
    {acceptedCalculatorVersions: ['calc-v1', 'calc-v1']},
    {acceptedCalculatorVersions: ['bad/id']},
    {controlVersion: Number.MAX_SAFE_INTEGER + 1},
    {associationId: 'other'},
    {competitionId: 'unexpected'},
  ]) assert.equal(decide('stats.enter', {associationControl: {...fixture.associationControlBase, ...controlChange}}).authorized, false);
});

test('success returns every detached verified binding and no request references', () => {
  const input = validInput('stats.enter');
  const decision = evaluateScopedAuthority(input);
  assert.equal(decision.authorized, true);
  assert.deepEqual(decision.scope, fixture.scopes.game);
  assert.deepEqual(decision.versions, fixture.versionsWithCalculator);
  assert.deepEqual(decision.grant, {
    origin: 'season',
    accessPath: 'associations/jba/competitions/nbl/seasons/s2026/access/operator',
    accessVersion: 5,
    grantKey: 'stats.enter|division|premier',
    grantId: 'grant-stats-enter',
  });
  assert.deepEqual(decision.game, {
    gamePath: 'associations/jba/competitions/nbl/seasons/s2026/games/game-1',
    controlVersion: 11,
    homeTeamEntryId: 'team-a',
    awayTeamEntryId: 'team-b',
  });
  assert.deepEqual(decision.assignment, {
    assignmentPath: 'associations/jba/competitions/nbl/seasons/s2026/games/game-1/assignments/operator',
    assignmentVersion: 4,
    writerEpoch: 6,
  });
  assert.equal(decision.membershipVersion, 7);
  assert.equal(decision.associationControlVersion, 2);
  assert.equal(decision.seasonControlVersion, 7);
  assert.equal(decision.evaluatedAt.toISOString(), fixture.evaluationAnchor);
  input.scope.associationId = 'mutated';
  input.versions.calculatorVersion = 'mutated';
  input.game.homeTeamEntryId = 'mutated';
  input.assignment.writerEpoch = 99;
  assert.equal(decision.scope.associationId, 'jba');
  assert.equal(decision.versions.calculatorVersion, 'calc-v1');
  assert.equal(decision.game.homeTeamEntryId, 'team-a');
  assert.equal(decision.assignment.writerEpoch, 6);
});

test('roles and unverified extras never authorize or appear in success', () => {
  const input = validInput('players.manage');
  input.membership = {...input.membership, role: 'superAdmin'};
  input.unverified = {domainValidationPassed: true};
  const decision = evaluateScopedAuthority(input);
  assert.equal(decision.authorized, true);
  assert.equal(Object.prototype.hasOwnProperty.call(decision, 'role'), false);
  assert.equal(Object.prototype.hasOwnProperty.call(decision, 'unverified'), false);
  assert.equal(evaluateScopedAuthority({...input, scope: {associationId: 'other'}}).authorized, false);
});
