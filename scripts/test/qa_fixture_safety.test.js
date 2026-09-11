'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const {
  AUTHORIZATION_SCHEMA_VERSION,
  TEAM_FIXTURES,
  authorizationSchema,
  identity,
  normalizePublicFixtureValue,
  requireSafeEnvironment,
  roles,
} = require('../qa/seed_local_qa');

const safeEnvironment = {
  GCLOUD_PROJECT: 'demo-hoopsconnect-stage0-platform',
  FIREBASE_AUTH_EMULATOR_HOST: '127.0.0.1:19099',
  FIRESTORE_EMULATOR_HOST: '127.0.0.1:18080',
  FUNCTIONS_EMULATOR_HOST: '127.0.0.1:15001',
  FIREBASE_STORAGE_EMULATOR_HOST: '127.0.0.1:19199',
};

test('QA fixture accepts only the recorded synthetic local target', () => {
  assert.doesNotThrow(() => requireSafeEnvironment(safeEnvironment));
  assert.throws(
    () => requireSafeEnvironment({...safeEnvironment, GCLOUD_PROJECT: 'hoops-connect-jm'}),
    /must be demo-hoopsconnect-stage0-platform/,
  );
  assert.throws(
    () => requireSafeEnvironment({
      ...safeEnvironment,
      FIRESTORE_EMULATOR_HOST: '127.0.0.1@evil.example:8080',
    }),
    /explicit loopback/,
  );
  assert.throws(
    () => requireSafeEnvironment({...safeEnvironment, FIREBASE_TOKEN: 'secret'}),
    /FIREBASE_TOKEN is forbidden/,
  );
});

test('full and empty identities are deterministic and cover every app role', () => {
  assert.deepEqual(
    roles.map(([role]) => role),
    ['superAdmin', 'admin', 'statistician', 'rep', 'media', 'press', 'fan'],
  );
  const generated = roles.flatMap(([role]) => [
    identity(role, 'full'),
    identity(role, 'empty'),
  ]);
  assert.equal(new Set(generated.map((entry) => entry.uid)).size, 14);
  assert.equal(identity('superAdmin', 'full').uid, 'qa-superadmin');
  assert.equal(identity('press', 'empty').email, 'press-empty@hoopsconnect.test');
});

test('QA role authority and schema version exactly match the canonical Functions schema', () => {
  const canonical = require('../../functions/src/authorization_schema_v1.json');
  assert.strictEqual(authorizationSchema, canonical);
  assert.equal(AUTHORIZATION_SCHEMA_VERSION, canonical.schemaVersion);
  assert.deepEqual(Object.fromEntries(roles), canonical.roles);
  for (const [role, capabilities] of roles) {
    assert.deepEqual(capabilities, canonical.roles[role]);
  }
});

test('full dataset has four deterministic teams for roster and division journeys', () => {
  assert.deepEqual(TEAM_FIXTURES.map((team) => team.id), [
    'kingston-lions',
    'montego-bay-waves',
    'spanish-town-sparks',
    'portmore-pelicans',
  ]);
  assert.deepEqual(new Set(TEAM_FIXTURES.map((team) => team.divisionId)), new Set([
    'premier',
    'development',
  ]));
});

test('QA public data uses the reviewed pure projector without a deployable trigger', () => {
  const seedSource = fs.readFileSync(
    path.resolve(__dirname, '../qa/seed_local_qa.js'),
    'utf8',
  );
  assert.match(seedSource, /publicSnapshotBuilder\(\)\(\{/);
  assert.match(
    seedSource,
    /publicData\/\$\{ASSOCIATION_ID\}\/snapshots\/current/,
  );
  assert.doesNotMatch(seedSource, /onPublicLeagueSourceWritten/);
  const converted = normalizePublicFixtureValue({
    startTime: {toDate: () => new Date('2026-09-10T20:00:00.000Z')},
    nested: [{value: 1}],
  });
  assert.deepEqual(converted, {
    startTime: '2026-09-10T20:00:00.000Z',
    nested: [{value: 1}],
  });
});
