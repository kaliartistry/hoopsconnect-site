'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');

const inventory = require('../lib/stat_migration_inventory');
const firebaseAdapter = require('../lib/stat_migration_readonly_firebase');
const cli = require('../stat_migration_inventory');

const fixturePath = path.join(__dirname, '../fixtures/stat-migration/source-v1.json');
const contractFixturePath = path.join(__dirname, '../../contracts/official_stats/v2/contract_fixtures.json');

function loadFixture() {
  return JSON.parse(fs.readFileSync(fixturePath, 'utf8'));
}

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function dryRun(manifest, options = {}) {
  const operatorInventory = inventory.buildInventory(manifest, options);
  return {operatorInventory, report: inventory.buildDryRunReport(operatorInventory)};
}

function findRecord(report, entityType, predicate = () => true) {
  return report.payload.records.find((record) => record.entityType === entityType && predicate(record));
}

test('canonical encoder exactly matches Packet 01 golden hashes', () => {
  const shared = JSON.parse(fs.readFileSync(contractFixturePath, 'utf8'));
  for (const testCase of shared.canonicalCases) {
    assert.equal(inventory.canonicalEncode(testCase.input), testCase.canonical, testCase.name);
    assert.equal(inventory.canonicalSha256(testCase.input), testCase.sha256, testCase.name);
  }
  assert.equal(inventory.CANONICAL_ENCODING_VERSION, shared.versions.canonicalEncodingVersion);
});

test('classification vocabulary is exact and ordered', () => {
  assert.deepEqual(inventory.classifications, [
    'evidenced', 'unverified', 'synthetic', 'orphaned', 'contradictory',
    'duplicateCandidate', 'privacyRestricted',
  ]);
});

test('repeated dry runs have byte-identical payloads, hashes, and IDs', () => {
  const first = dryRun(loadFixture());
  const second = dryRun(loadFixture());
  assert.equal(inventory.canonicalEncode(first.operatorInventory), inventory.canonicalEncode(second.operatorInventory));
  assert.equal(inventory.canonicalEncode(first.report), inventory.canonicalEncode(second.report));
  assert.equal(first.report.payloadSha256, second.report.payloadSha256);
  assert.deepEqual(
    first.report.payload.records.flatMap((record) => record.proposedMappings.map((mapping) => mapping.proposedId)),
    second.report.payload.records.flatMap((record) => record.proposedMappings.map((mapping) => mapping.proposedId)),
  );
  assert.deepEqual(
    inventory.verifyReport(first.report, {
      inventoryEnvelope: first.operatorInventory,
      compareEnvelope: second.report,
    }),
    inventory.verifyReport(second.report, {inventoryEnvelope: second.operatorInventory}),
  );
});

test('source input order does not change the semantic result', () => {
  const original = loadFixture();
  const reversed = clone(original);
  reversed.records.reverse();
  const first = dryRun(original);
  const second = dryRun(reversed);
  assert.equal(first.operatorInventory.payload.sourceSnapshotSha256, second.operatorInventory.payload.sourceSnapshotSha256);
  assert.equal(inventory.canonicalEncode(first.report), inventory.canonicalEncode(second.report));
});

test('same source identity with a changed field hash creates an exact conflict', () => {
  const baseline = dryRun(loadFixture());
  const changed = loadFixture();
  const team = changed.records.find((record) => record.sourceKey === 'team-a');
  team.data.displayName = 'Changed Synthetic Lions';
  const rerun = dryRun(changed, {previousReport: baseline.report});
  const conflict = rerun.report.payload.conflicts.find((item) => (
    item.issues.some((issue) => issue.code === inventory.errorCodes.changedSourceHash)
  ));
  assert.ok(conflict);
  const detail = conflict.issues.find((issue) => issue.code === inventory.errorCodes.changedSourceHash);
  assert.equal(detail.expectedSourceFieldHash, inventory.canonicalSha256({approved: true, displayName: 'Synthetic Lions'}));
  assert.deepEqual(detail.observedSourceFieldHashes, [
    inventory.canonicalSha256({approved: true, displayName: 'Changed Synthetic Lions'}),
  ]);
  const changedRecord = rerun.report.payload.records.find((record) => record.sourceLabel === conflict.sourceLabel);
  assert.equal(changedRecord.blocked, true);
});

test('association, source entity type, target type, and full path all affect mapping IDs', () => {
  const args = ['jba', 'legacyPlayer', 'player', 'associations/jba/players/a#a'];
  const baseline = inventory.mappingId(...args);
  assert.notEqual(baseline, inventory.mappingId('other', ...args.slice(1)));
  assert.notEqual(baseline, inventory.mappingId('jba', 'legacyRosterEntry', ...args.slice(2)));
  assert.notEqual(baseline, inventory.mappingId('jba', 'legacyPlayer', 'person', args[3]));
  assert.notEqual(baseline, inventory.mappingId('jba', 'legacyPlayer', 'player', 'associations/jba/players/b#b'));
});

test('names, emails, phones, and jerseys never act as identity merge keys', () => {
  const manifest = loadFixture();
  const rosterRecords = manifest.records.filter((record) => record.entityType === 'legacyRosterEntry');
  rosterRecords[0].data.email = 'same@example.invalid';
  rosterRecords[1].data.email = 'same@example.invalid';
  rosterRecords[0].data.phone = '000-0000';
  rosterRecords[1].data.phone = '000-0000';
  const first = dryRun(manifest).report;
  const playerIds = first.payload.records
    .filter((record) => record.entityType === 'legacyRosterEntry')
    .map((record) => record.proposedMappings.find((mapping) => mapping.targetEntityType === 'player').proposedId);
  assert.equal(new Set(playerIds).size, 2);

  rosterRecords[0].data.displayName = 'Entirely Different Name';
  rosterRecords[0].data.email = 'changed@example.invalid';
  rosterRecords[0].data.phone = '111-1111';
  rosterRecords[0].data.jersey = '77';
  const second = dryRun(manifest).report;
  const changedPlayerId = second.payload.records
    .find((record) => record.sourceIdentityHash === first.payload.records
      .filter((record) => record.entityType === 'legacyRosterEntry')[0].sourceIdentityHash)
    .proposedMappings.find((mapping) => mapping.targetEntityType === 'player').proposedId;
  assert.equal(changedPlayerId, playerIds[0]);
});

test('jersey strings 0 and 00 remain distinct and historical dates remain explicitly unknown', () => {
  const normalized = inventory.validateManifest(loadFixture());
  const rosters = normalized.records.filter((record) => record.entityType === 'legacyRosterEntry');
  assert.deepEqual(rosters.map((record) => record.data.jersey), ['0', '00']);
  assert.notEqual(inventory.canonicalSha256(rosters[0].data), inventory.canonicalSha256(rosters[1].data));
  for (const record of rosters) {
    assert.deepEqual(record.temporalEvidence.effectiveFrom, {
      reasonCode: 'not_recorded', state: 'unknown', value: null,
    });
  }
});

test('legacy approved is unverified without independent evidence', () => {
  const report = dryRun(loadFixture()).report;
  const approvedTeam = findRecord(report, 'legacyTeam');
  assert.ok(approvedTeam.classifications.includes('unverified'));
  assert.ok(!approvedTeam.classifications.includes('evidenced'));
  assert.equal(report.payload.reconciliationExpectations.legacyApprovalGrantsCertification, false);
});

test('explicit allowlisted generator provenance is synthetic and excluded from creates and certification', () => {
  const report = dryRun(loadFixture()).report;
  const synthetic = findRecord(report, 'legacyGameStats');
  assert.ok(synthetic.classifications.includes('synthetic'));
  assert.ok(report.payload.syntheticExclusions.includes(synthetic.sourceLabel));
  assert.ok(!report.payload.proposedCreates.some((create) => create.sourceLabel === synthetic.sourceLabel));
  assert.equal(report.payload.reconciliationExpectations.syntheticRecordsAutoCertified, 0);
});

test('orphan, contradiction, duplicate candidate, and privacy restriction are explicit and blocked', () => {
  const report = dryRun(loadFixture()).report;
  for (const classification of ['orphaned', 'contradictory', 'duplicateCandidate', 'privacyRestricted']) {
    const record = report.payload.records.find((candidate) => candidate.classifications.includes(classification));
    assert.ok(record, classification);
    assert.equal(record.blocked, true, classification);
  }
  assert.ok(report.payload.unresolvedJoins.length > 0);
  assert.ok(report.payload.conflicts.length > 0);
  assert.ok(report.payload.duplicateCandidates.length > 0);
  assert.ok(report.payload.privacyRestrictions.length > 0);
});

test('missing game scope blocks mapping and never creates a null-scoped path', () => {
  const report = dryRun(loadFixture()).report;
  const missing = report.payload.records.find((record) => (
    record.issues.some((issue) => issue.code === inventory.errorCodes.missingScope)
  ));
  assert.ok(missing);
  assert.equal(missing.blocked, true);
  assert.ok(missing.proposedMappings.every((mapping) => mapping.proposedPath === null));
  assert.ok(!report.payload.proposedCreates.some((create) => create.sourceLabel === missing.sourceLabel));
});

test('missing required roster/game relationship evidence fails closed', () => {
  const manifest = loadFixture();
  const roster = manifest.records.find((record) => record.entityType === 'legacyRosterEntry');
  roster.references = [];
  const report = dryRun(manifest).report;
  const record = report.payload.records.find((candidate) => (
    candidate.sourceIdentityHash === inventory.canonicalSha256(`${roster.sourcePath}#${roster.sourceKey}`)
  ));
  assert.equal(record.blocked, true);
  assert.ok(record.classifications.includes('orphaned'));
  assert.ok(record.issues.some((issue) => (
    issue.code === inventory.errorCodes.orphanedReference && issue.relations.includes('team')
  )));
});

test('conflicting paired game scope is contradictory and blocked', () => {
  const manifest = loadFixture();
  const stats = manifest.records.find((record) => record.entityType === 'legacyGameStats');
  stats.scope.divisionId = 'division_2';
  const report = dryRun(manifest).report;
  const record = findRecord(report, 'legacyGameStats');
  assert.ok(record.classifications.includes('contradictory'));
  assert.ok(record.issues.some((issue) => (
    issue.code === inventory.errorCodes.contradictorySource
      && issue.contradictionCodes.includes('scope_divisionId_mismatch')
  )));
});

test('unsafe and cross-association paths fail closed with stable codes', () => {
  const unsafe = loadFixture();
  unsafe.records[0].sourcePath = 'associations/jba/seasons/../escape';
  assert.throws(
    () => inventory.buildInventory(unsafe),
    (error) => error.code === inventory.errorCodes.unsafePath,
  );
  const crossTenant = loadFixture();
  crossTenant.records[6].references[0].targetSourcePath = 'associations/other/teams/team-b';
  assert.throws(
    () => inventory.buildInventory(crossTenant),
    (error) => error.code === inventory.errorCodes.crossAssociationReference,
  );
});

test('pagination and checkpoints are bounded and deterministic', () => {
  const small = dryRun(loadFixture(), {pageSize: 3}).operatorInventory;
  const larger = dryRun(loadFixture(), {pageSize: 5}).operatorInventory;
  assert.equal(small.payload.pagination.pageSize, 3);
  assert.equal(small.payload.pagination.checkpoints.length, 5);
  assert.ok(small.payload.pagination.checkpoints.every((page) => page.pageRecordCount <= 3));
  assert.equal(small.payload.sourceSnapshotSha256, larger.payload.sourceSnapshotSha256);
  assert.throws(
    () => inventory.buildInventory(loadFixture(), {pageSize: inventory.MAX_PAGE_SIZE + 1}),
    (error) => error.code === inventory.errorCodes.oversizedPage,
  );
});

test('repeated exact source identities are explicit duplicate candidates', () => {
  const manifest = loadFixture();
  manifest.records.push(clone(manifest.records[0]));
  const report = dryRun(manifest).report;
  const duplicate = report.payload.records.find((record) => (
    record.issues.some((issue) => issue.code === inventory.errorCodes.duplicateCandidate
      && issue.sourceOccurrences === 2)
  ));
  assert.ok(duplicate);
  assert.equal(duplicate.blocked, true);
});

test('game-line names remain evidence and never become player identity mappings', () => {
  const report = dryRun(loadFixture()).report;
  const line = findRecord(report, 'legacyGamePlayerLine');
  assert.deepEqual(
    line.proposedMappings.map((mapping) => mapping.targetEntityType),
    ['gameParticipantEvidence', 'rosterSnapshotParticipant'],
  );
  assert.ok(!line.proposedMappings.some((mapping) => ['person', 'player'].includes(mapping.targetEntityType)));
});

test('sanitized report and console-safe errors do not contain sensitive source values', () => {
  const result = dryRun(loadFixture());
  const report = result.report;
  const encoded = inventory.canonicalEncode(report);
  const operatorEncoded = inventory.canonicalEncode(result.operatorInventory);
  for (const sensitive of [
    'fixture@example.invalid', 'Private Fixture', 'Same Synthetic Player', 'Evidence, Not Identity',
  ]) assert.ok(!encoded.includes(sensitive), sensitive);
  assert.ok(!operatorEncoded.includes('fixture@example.invalid'));
  assert.ok(operatorEncoded.includes('associations/jba/players/private-a'));
  const redacted = inventory.redactError(new Error('email=real@example.com Bearer abc.def phone:12345'));
  assert.ok(!redacted.includes('real@example.com'));
  assert.ok(!redacted.includes('abc.def'));
  assert.ok(!redacted.includes('12345'));
});

test('fixture and dry-run code expose no remote write-capable API', () => {
  const source = fs.readFileSync(path.join(__dirname, '../lib/stat_migration_readonly_firebase.js'), 'utf8');
  for (const pattern of [
    /\.set\s*\(/, /\.update\s*\(/, /\.create\s*\(/, /\.delete\s*\(/,
    /batch\s*\(/, /runTransaction\s*\(/, /commit\s*\(/,
  ]) assert.doesNotMatch(source, pattern);
  assert.equal(dryRun(loadFixture()).report.payload.estimatedBoundedOperations.writesExecuted, 0);
});

test('Firebase adapter pages only with GET ordered by document ID', async () => {
  const calls = [];
  const pages = [
    {
      documents: [{
        name: 'projects/demo/databases/(default)/documents/associations/jba/teams/team-a',
        fields: {displayName: {stringValue: 'Fixture Team'}},
      }],
      nextPageToken: 'next',
    },
    {
      documents: [{
        name: 'projects/demo/databases/(default)/documents/associations/jba/teams/team-b',
        fields: {displayName: {stringValue: 'Fixture Team B'}},
      }],
    },
  ];
  const fetchImpl = async (url, options) => {
    calls.push({options, url});
    return {ok: true, status: 200, json: async () => pages.shift()};
  };
  const manifest = loadFixture();
  manifest.records = [];
  manifest.source.projectOrExportId = 'demo';
  manifest.source.exportIdentifier = 'read-only-test';
  manifest.providerCollections = [{
    collectionPath: 'associations/jba/teams',
    entityType: 'legacyTeam',
    sourceCollection: 'teams',
    scope: {
      associationId: 'jba', competitionId: 'nbl', seasonId: 'season_2026', divisionId: 'division_1',
    },
  }];
  const loaded = await firebaseAdapter.loadReadOnlyFirebaseManifest({
    baseUrl: 'http://127.0.0.1:8080/v1/projects/demo/databases/(default)/documents',
    fetchImpl,
    manifest,
    pageSize: 1,
  });
  assert.equal(loaded.records.length, 2);
  assert.ok(loaded.source.adapterCheckpointSha256);
  assert.equal(calls.length, 2);
  assert.ok(calls.every((call) => call.options.method === 'GET'));
  assert.ok(calls.every((call) => call.url.includes('orderBy=__name__')));
  assert.ok(calls.every((call) => call.url.includes('pageSize=1')));
  assert.ok(calls[1].url.includes('pageToken=next'));
  assert.doesNotThrow(() => inventory.buildInventory(loaded, {pageSize: 1}));
});

test('Firebase adapter rejects provider pages that are not strictly document-ID ordered', async () => {
  const response = {
    ok: true,
    status: 200,
    json: async () => ({documents: [
      {name: 'projects/demo/databases/(default)/documents/associations/jba/teams/z', fields: {}},
      {name: 'projects/demo/databases/(default)/documents/associations/jba/teams/a', fields: {}},
    ]}),
  };
  await assert.rejects(
    () => firebaseAdapter.readCollection({
      baseUrl: 'http://127.0.0.1:8080/v1/projects/demo/databases/(default)/documents',
      bearerToken: null,
      collectionPath: 'associations/jba/teams',
      fetchImpl: async () => response,
      pageSize: 2,
    }),
    (error) => error.code === inventory.errorCodes.contradictorySource,
  );
});

test('write-like CLI modes and flags are rejected before any adapter access', () => {
  for (const args of [['--mode=write'], ['--apply=yes'], ['--delete=true']]) {
    assert.throws(
      () => cli.parseArgs(args),
      (error) => error.code === inventory.errorCodes.attemptedWriteMode,
    );
  }
});

test('Firebase mode requires exact flags and a no-write acknowledgement', async () => {
  await assert.rejects(
    () => cli.loadManifest({
      associationId: 'jba',
      inputPath: fixturePath,
      mode: 'firebase',
      pageSize: 25,
      projectId: 'demo',
      readOnlyAcknowledgement: null,
    }, ['--project=demo', '--association=jba']),
    (error) => error.code === inventory.errorCodes.attemptedWriteMode,
  );
});

test('report verification detects tampering and nondeterminism', () => {
  const {operatorInventory, report} = dryRun(loadFixture());
  const tampered = clone(report);
  tampered.payload.counts.sourceRecords += 1;
  assert.throws(
    () => inventory.verifyReport(tampered, {inventoryEnvelope: operatorInventory}),
    (error) => error.code === inventory.errorCodes.nondeterminism,
  );
  const other = clone(report);
  other.payload.source.exportIdentifier = 'different';
  other.payloadSha256 = inventory.canonicalSha256(other.payload);
  assert.throws(
    () => inventory.verifyReport(report, {compareEnvelope: other}),
    (error) => error.code === inventory.errorCodes.nondeterminism,
  );
});

test('private artifact writer uses restrictive permissions and rejects escape paths', () => {
  const temporaryRepo = fs.mkdtempSync(path.join(os.tmpdir(), 'hc-mi-'));
  const output = inventory.ensurePrivateOutputDirectory(
    path.join(temporaryRepo, '.local/stat-migration/test'),
    temporaryRepo,
  );
  const file = path.join(output, 'report.json');
  inventory.writePrivateCanonicalJson(file, {ok: true});
  assert.equal(fs.statSync(output).mode & 0o777, 0o700);
  assert.equal(fs.statSync(file).mode & 0o777, 0o600);
  assert.deepEqual(cli.readJson(file, {requireCanonical: true}), {ok: true});
  fs.writeFileSync(file, '{\n  "ok": true\n}\n');
  assert.throws(
    () => cli.readJson(file, {requireCanonical: true}),
    (error) => error.code === inventory.errorCodes.nondeterminism,
  );
  assert.throws(
    () => inventory.ensurePrivateOutputDirectory(path.join(temporaryRepo, 'outside'), temporaryRepo),
    (error) => error.code === inventory.errorCodes.unsafePath,
  );
});

test('unsupported source schema and malformed canonical numbers have stable codes', () => {
  const unsupported = loadFixture();
  unsupported.manifestSchemaVersion = 'future-v99';
  assert.throws(
    () => inventory.buildInventory(unsupported),
    (error) => error.code === inventory.errorCodes.unsupportedSchemaVersion,
  );
  const malformed = loadFixture();
  malformed.records[0].data.fractional = 0.5;
  assert.throws(
    () => inventory.buildInventory(malformed),
    (error) => error.code === inventory.errorCodes.malformedSource,
  );
});

test('required references enforce target type and blocked dependency eligibility', () => {
  const wrongType = loadFixture();
  const roster = wrongType.records.find((record) => record.entityType === 'legacyRosterEntry');
  const season = wrongType.records.find((record) => record.entityType === 'season');
  roster.references[0].targetSourcePath = season.sourcePath;
  roster.references[0].targetSourceKey = season.sourceKey;
  const wrongTypeReport = dryRun(wrongType).report;
  const wrongTypeRecord = wrongTypeReport.payload.records.find((record) => (
    record.sourceIdentityHash === inventory.canonicalSha256(`${roster.sourcePath}#${roster.sourceKey}`)
  ));
  assert.equal(wrongTypeRecord.blocked, true);
  assert.ok(wrongTypeRecord.issues.some((issue) => (
    issue.code === inventory.errorCodes.contradictorySource
      && issue.contradictionCodes.includes('reference_team_target_type_mismatch')
  )));
  assert.ok(!wrongTypeReport.payload.proposedCreates.some((item) => item.sourceLabel === wrongTypeRecord.sourceLabel));

  const blockedParent = loadFixture();
  blockedParent.records.find((record) => record.sourceKey === 'team-a')
    .classificationEvidence.privacyRestrictedFields = ['contact'];
  const blockedReport = dryRun(blockedParent).report;
  const dependent = blockedReport.payload.records.find((record) => (
    record.entityType === 'legacyRosterEntry' && record.referenceMappings.length > 0
  ));
  assert.equal(dependent.blocked, true);
  assert.ok(dependent.classifications.includes('orphaned'));
  assert.ok(!blockedReport.payload.proposedCreates.some((item) => item.sourceLabel === dependent.sourceLabel));

  const syntheticParent = loadFixture();
  syntheticParent.records.find((record) => record.sourceKey === 'team-a').provenance.generator = {
    evidenceHash: 'b'.repeat(64),
    generatorId: 'backfill_pending_game_stats',
    ruleVersion: 'legacy-generator-rule-v1',
  };
  const syntheticReport = dryRun(syntheticParent).report;
  const syntheticDependent = syntheticReport.payload.records.find((record) => (
    record.entityType === 'legacyRosterEntry' && record.referenceMappings.length > 0
  ));
  assert.equal(syntheticDependent.blocked, true);
  assert.ok(!syntheticReport.payload.proposedCreates.some((item) => (
    item.sourceLabel === syntheticDependent.sourceLabel
  )));
});

test('canonical destination paths use mapped container IDs and are unique', () => {
  const report = dryRun(loadFixture()).report;
  const seasonRecord = findRecord(report, 'season');
  const seasonMapping = seasonRecord.proposedMappings.find((mapping) => mapping.targetEntityType === 'season');
  assert.ok(seasonMapping.proposedPath.endsWith(`/seasons/${seasonMapping.proposedId}`));
  const gameRecord = findRecord(report, 'legacyGame', (record) => !record.blocked);
  const gameMapping = gameRecord.proposedMappings.find((mapping) => mapping.targetEntityType === 'game');
  assert.ok(gameMapping.proposedPath.includes(`/seasons/${seasonMapping.proposedId}/games/${gameMapping.proposedId}`));
  const evidence = findRecord(report, 'legacyGameStats').proposedMappings[0];
  assert.ok(evidence.proposedPath.includes(`/games/${gameMapping.proposedId}/`));
  const paths = report.payload.proposedCreates.map((item) => item.proposedPath);
  assert.equal(new Set(paths).size, paths.length);
});

test('all duplicate occurrence evidence is deterministic and source-bound', () => {
  const manifest = loadFixture();
  const original = clone(manifest.records[0]);
  const second = clone(original);
  const third = clone(original);
  second.data.variant = 'middle';
  second.scope.seasonId = 'metadata-change';
  third.data.variant = 'last';
  manifest.records.push(second, third);
  const reversed = clone(manifest);
  reversed.records.reverse();
  const first = dryRun(manifest);
  const other = dryRun(reversed);
  assert.equal(inventory.canonicalEncode(first.operatorInventory), inventory.canonicalEncode(other.operatorInventory));
  const record = first.operatorInventory.payload.records.find((candidate) => candidate.sourceOccurrences === 3);
  assert.equal(record.occurrenceEvidenceHashes.length, 3);
  const issue = record.issues.find((candidate) => candidate.code === inventory.errorCodes.changedSourceHash);
  assert.equal(issue.observedSourceFieldHashes.length, 3);

  const tampered = clone(first.operatorInventory);
  tampered.payload.records[0].fieldHash = '0'.repeat(64);
  tampered.payloadSha256 = inventory.canonicalSha256(tampered.payload);
  assert.throws(
    () => inventory.buildDryRunReport(tampered),
    (error) => error.code === inventory.errorCodes.nondeterminism,
  );
});

test('sanitized metadata is hashed and native errors never echo source content', () => {
  const manifest = loadFixture();
  manifest.source.exportIdentifier = 'fixture-person@example.invalid';
  manifest.records[0].sourceCollection = 'users/fixture-person@example.invalid/stats';
  const encoded = inventory.canonicalEncode(dryRun(manifest).report);
  assert.ok(!encoded.includes('fixture-person@example.invalid'));
  const native = inventory.redactError(new SyntaxError('Unexpected token in {"8765550100":NaN}'));
  assert.ok(!native.includes('8765550100'));
  assert.match(native, /inspect the private operator context/);
});

test('private output rejects root, nested, and destination symlinks', () => {
  const rootRepo = fs.mkdtempSync(path.join(os.tmpdir(), 'hc-mi-root-link-'));
  const outside = fs.mkdtempSync(path.join(os.tmpdir(), 'hc-mi-outside-'));
  fs.mkdirSync(path.join(rootRepo, '.local'));
  fs.symlinkSync(outside, path.join(rootRepo, '.local/stat-migration'));
  assert.throws(
    () => inventory.ensurePrivateOutputDirectory(path.join(rootRepo, '.local/stat-migration/run'), rootRepo),
    (error) => error.code === inventory.errorCodes.unsafePath,
  );

  const nestedRepo = fs.mkdtempSync(path.join(os.tmpdir(), 'hc-mi-nested-link-'));
  const allowed = inventory.ensurePrivateOutputDirectory(path.join(nestedRepo, '.local/stat-migration'), nestedRepo);
  fs.symlinkSync(outside, path.join(allowed, 'linked'));
  assert.throws(
    () => inventory.ensurePrivateOutputDirectory(path.join(allowed, 'linked/run'), nestedRepo),
    (error) => error.code === inventory.errorCodes.unsafePath,
  );
  const destination = path.join(allowed, 'report.json');
  fs.symlinkSync(path.join(outside, 'report.json'), destination);
  assert.throws(
    () => inventory.writePrivateCanonicalJson(destination, {ok: true}),
    (error) => error.code === inventory.errorCodes.unsafePath,
  );
});

test('known temporal intervals must be canonical and ordered', () => {
  const reversed = loadFixture();
  const roster = reversed.records.find((record) => record.entityType === 'legacyRosterEntry');
  roster.temporalEvidence = {
    effectiveFrom: {state: 'known', value: '2026-12-31T00:00:00.000Z'},
    effectiveTo: {state: 'known', value: '2026-01-01T00:00:00.000Z'},
  };
  assert.throws(
    () => inventory.buildInventory(reversed),
    (error) => error.code === inventory.errorCodes.contradictorySource,
  );
  const equal = loadFixture();
  equal.records.find((record) => record.entityType === 'legacyRosterEntry').temporalEvidence = {
    effectiveFrom: {state: 'known', value: '2026-01-01T00:00:00.000Z'},
    effectiveTo: {state: 'known', value: '2026-01-01T00:00:00.000Z'},
  };
  assert.throws(
    () => inventory.buildInventory(equal),
    (error) => error.code === inventory.errorCodes.contradictorySource,
  );
});

test('Firebase embedded identity keys must be explicit stable ID fields', async () => {
  const manifest = JSON.parse(fs.readFileSync(
    path.join(__dirname, '../fixtures/stat-migration/firebase-provider-v1.example.json'),
    'utf8',
  ));
  manifest.providerCollections[0].embeddedArrays[0].keyField = 'displayName';
  const response = {
    ok: true,
    status: 200,
    json: async () => ({documents: [{
      name: 'projects/demo/databases/(default)/documents/associations/jba/teams/team-a',
      fields: {roster: {arrayValue: {values: []}}},
    }]}),
  };
  await assert.rejects(
    () => firebaseAdapter.loadReadOnlyFirebaseManifest({
      baseUrl: 'http://127.0.0.1:8080/v1/projects/demo/databases/(default)/documents',
      fetchImpl: async () => response,
      manifest,
      pageSize: 1,
    }),
    (error) => error.code === inventory.errorCodes.malformedSource,
  );
});
