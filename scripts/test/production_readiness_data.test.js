'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');
const {
  assertSanitized,
  buildPlan,
  canonicalJson,
  exitCodeForPlan,
  loadOrCreateKey,
  parseArgs,
  pseudonym,
  sanitizeErrorMessage,
  writePrivateJson,
} = require('../audit_production_readiness_data');

function fixture() {
  const emptyCollections = Object.fromEntries([
    'seasons', 'divisions', 'players', 'rosters', 'playerSeasonStats',
    'teamSeasonStats', 'standings', 'leaderboard',
  ].map((name) => [name, []]));
  const teams = [{id: 'raw-team-identifier', data: {
    schemaVersion: undefined,
    rosterEntries: 2,
    hasLogoReference: false,
  }}];
  const events = [{id: 'raw-event-identifier', data: {
    schemaVersion: undefined,
    type: 'game',
    statsStatus: 'approved',
  }}];
  const gameStats = [{id: 'raw-stat-identifier', data: {
    schemaVersion: undefined,
    status: 'approved',
    playerLineEntries: 2,
  }}];
  return {
    projectId: 'hoops-connect-jm',
    associationId: 'jba',
    associationExists: true,
    authUserIds: ['raw-user-identifier'],
    users: [{id: 'raw-user-identifier', data: {
      role: 'admin', associationId: 'jba', authorizationSchemaVersion: undefined,
    }}],
    memberships: [],
    posts: [{id: 'raw-post-identifier', data: {
      visibility: undefined, requiresAck: true, hasImageReference: false,
    }}],
    invites: [{id: 'STATIC-INVITE-SECRET', data: {
      credentialVersion: undefined, authorizationSchemaVersion: undefined, status: 'active',
    }}],
    teams,
    events,
    gameStats,
    collections: {...emptyCollections, teams, events, gameStats},
    storageObjects: [{
      name: 'posts/raw-post-identifier/image.png',
      kind: 'posts',
      entityId: 'raw-post-identifier',
      hasDownloadToken: true,
      hasRequiredMetadata: false,
      classification: 'legacy_or_unclassified',
    }],
  };
}

test('migration dry run is deterministic, pseudonymous, and fail closed', () => {
  const key = Buffer.alloc(32, 7);
  const snapshot = fixture();
  const first = buildPlan(snapshot, key);
  const second = buildPlan(snapshot, key);
  const reordered = buildPlan({
    ...snapshot,
    users: [...snapshot.users].reverse(),
    posts: [...snapshot.posts].reverse(),
    invites: [...snapshot.invites].reverse(),
    storageObjects: [...snapshot.storageObjects].reverse(),
  }, key);
  assert.equal(canonicalJson(first.plan), canonicalJson(second.plan));
  assert.equal(canonicalJson(first.plan), canonicalJson(reordered.plan));
  assert.equal(first.plan.proposedActions.memberships.length, 1);
  assert.equal(first.plan.proposedActions.posts[0].proposed.visibility, 'internal');
  assert.equal(first.plan.proposedActions.invites.length, 1);
  assert.equal(first.plan.proposedActions.storageObjects.length, 1);
  assert.equal(first.plan.blockers.length, 4);
  assert.equal(exitCodeForPlan(first.plan), 1);
  assert.equal(exitCodeForPlan({blockers: []}), 0);
  assertSanitized(first.plan, snapshot);
  const serialized = canonicalJson(first.plan);
  const operatorSerialized = canonicalJson(first.operatorMapping);
  assert.doesNotMatch(serialized, /raw-user-identifier|raw-post-identifier|STATIC-INVITE-SECRET/);
  assert.doesNotMatch(operatorSerialized, /STATIC-INVITE-SECRET/);
  assert.match(pseudonym(key, 'user', 'raw-user-identifier'), /^user_[a-f0-9]{16}$/);
});

test('read-only parser rejects write flags, positionals, and unsafe output paths', () => {
  assert.throws(
    () => parseArgs(['--project=x', '--association=jba', '--output-dir=.local/production-readiness', '--apply']),
    /Unsupported flag --apply/,
  );
  assert.throws(
    () => parseArgs(['unexpected', '--association=jba', '--output-dir=.local/production-readiness']),
    /Positional arguments/,
  );
  assert.throws(
    () => parseArgs(['--association=jba', '--output-dir=/tmp/not-allowed']),
    /must stay under/,
  );
});

test('provider errors redact principals, raw document IDs, tokens, and signed URLs', () => {
  const sanitized = sanitizeErrorMessage(new Error(
    'user@example.com users/raw-user-identifier inviteCodes/STATIC-INVITE-SECRET '
      + 'Bearer abc.def https://example.com/file?X-Goog-Signature=secret',
  ));
  assert.doesNotMatch(sanitized, /user@example|raw-user|STATIC-INVITE|abc\.def|X-Goog/);
  assert.match(sanitized, /\[redacted-principal\]/);
});

test('operator artifacts and pseudonym keys are owner-readable', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'hoops-readiness-'));
  const keyPath = path.join(root, 'pseudonym.key');
  const artifactPath = path.join(root, 'artifact.json');
  const key = loadOrCreateKey(keyPath);
  writePrivateJson(artifactPath, {safe: true});
  assert.equal(key.length, 32);
  assert.equal(fs.statSync(keyPath).mode & 0o777, 0o600);
  assert.equal(fs.statSync(artifactPath).mode & 0o777, 0o600);
  fs.rmSync(root, {recursive: true, force: true});
});
