'use strict';

const assert = require('node:assert/strict');
const {spawnSync} = require('node:child_process');
const path = require('node:path');
const test = require('node:test');

const {
  ALLOWED_DRIVERS,
  ALLOWED_PLATFORMS,
  ALLOWED_STAGES,
  EXPECTED_ALLOWED_HOSTS,
  REQUIRED_FINDING_IDS,
  REQUIRED_FORBIDDEN_ACTIONS,
  REQUIRED_JOURNEY_IDS,
  assertRunnableCheckpoint,
  formatRunbook,
  parseOptions,
  readCatalog,
  selectScenarios,
  validateCatalog,
  validateEvidenceRecord,
} = require('../qa/acceptance_scenarios');

test('acceptance catalog covers every remediation and cross-cutting finding', () => {
  const catalog = readCatalog();
  const counts = validateCatalog(catalog);

  assert.equal(counts.findings, 31);
  assert.equal(counts.scenarios, 47);
  assert.equal(counts.journeys, 8);
  assert.deepEqual(
    [...catalog.findings.map((finding) => finding.id)].sort(),
    [...REQUIRED_FINDING_IDS].sort(),
  );
  assert.deepEqual(
    [...catalog.journeys.map((journey) => journey.id)].sort(),
    [...REQUIRED_JOURNEY_IDS].sort(),
  );
});

test('action findings stay split and cross-cutting journeys are executable', () => {
  const catalog = readCatalog();
  const findings = new Map(catalog.findings.map((finding) => [finding.id, finding]));

  assert.equal(findings.get('F-03').scenarioIds.length, 3);
  assert.equal(findings.get('F-17').scenarioIds.length, 3);
  assert.equal(findings.get('F-19').scenarioIds.length, 2);
  assert.equal(findings.get('F-25').scenarioIds.length, 3);

  for (const journey of catalog.journeys) {
    const scenarios = selectScenarios(catalog, {journey: journey.id});
    assert.deepEqual(scenarios.map((scenario) => scenario.id), journey.scenarioIds);
    for (const scenario of scenarios) {
      assert.ok(scenario.steps.length > 0, scenario.id);
      assert.ok(scenario.assertions.length > 0, scenario.id);
      assert.ok(scenario.evidence.length > 0, scenario.id);
    }
  }
});

test('role, responsive, revision, privacy, recovery and deletion matrices remain pinned', () => {
  const catalog = readCatalog();
  const scenarios = new Map(catalog.scenarios.map((scenario) => [scenario.id, scenario]));

  assert.deepEqual(catalog.roles, [
    'guest', 'fan', 'rep', 'statistician', 'media', 'press', 'admin', 'superAdmin',
  ]);
  assert.deepEqual(catalog.viewports.map((viewport) => viewport.width), [375, 768, 1440]);
  assert.ok(scenarios.get('F14-REVISION-N-NPLUS1').dataStates.includes('revision-N-plus-1'));
  assert.ok(scenarios.get('F15-PUBLIC-DISCOVERY').assertions.join(' ').includes('public repositories'));
  assert.ok(scenarios.get('X01-DISPOSITION-PRIVACY').steps.join(' ').includes('27'));
  assert.ok(scenarios.get('X02-OFFLINE-RECOVERY').dataStates.includes('response-unknown'));
  assert.ok(scenarios.get('X02-OFFLINE-RECOVERY').dataStates.includes('writer-conflict'));
  for (const state of ['active', 'blocked', 'suspended', 'provider-cancelled', 'deleting', 'cleanup-pending']) {
    assert.ok(scenarios.get('X01-DELETION-ROUTES').dataStates.includes(state));
  }
});

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

test('catalog safety boundaries and all executable dimensions are allowlisted', () => {
  const catalog = readCatalog();
  assert.deepEqual(catalog.safety.allowedHosts, EXPECTED_ALLOWED_HOSTS);
  for (const action of REQUIRED_FORBIDDEN_ACTIONS) {
    assert.ok(catalog.safety.forbiddenActions.includes(action));
  }
  for (const scenario of catalog.scenarios) {
    assert.notEqual(scenario.mutationScope, 'production');
    assert.ok(ALLOWED_DRIVERS.includes(scenario.driver));
    assert.ok(ALLOWED_STAGES.includes(scenario.minimumStage));
    scenario.platforms.forEach((platform) => assert.ok(ALLOWED_PLATFORMS.includes(platform)));
  }
  assert.equal(catalog.safety.projectId, 'demo-hoopsconnect-stage0-platform');
  assert.equal(catalog.safety.entrypoint, 'lib/main_qa.dart');
});

test('catalog rejects host, forbidden-action, command, driver, platform and stage bypasses', () => {
  const catalog = readCatalog();
  const expectCatalogFailure = (mutate, pattern) => {
    const adversarial = clone(catalog);
    mutate(adversarial);
    assert.throws(() => validateCatalog(adversarial), pattern);
  };

  expectCatalogFailure(
    (value) => value.safety.allowedHosts.push('example.com'),
    /Allowed hosts must contain exactly/,
  );
  expectCatalogFailure(
    (value) => { value.safety.allowedHosts = ['localhost']; },
    /Allowed hosts must contain exactly/,
  );
  expectCatalogFailure(
    (value) => { value.safety.forbiddenActions = []; },
    /Forbidden actions must be a non-empty array/,
  );
  expectCatalogFailure(
    (value) => { value.safety.forbiddenActions = value.safety.forbiddenActions.slice(1); },
    /Forbidden actions must include production data write/,
  );
  expectCatalogFailure(
    (value) => { value.stage0.command = ['node', '-e', 'process.exit(0)']; },
    /Stage 0 command is not an allowlisted/,
  );
  expectCatalogFailure(
    (value) => { value.stage0.successMarkers[0] = 'ANYTHING_OK'; },
    /Stage 0 success markers must contain exactly/,
  );
  expectCatalogFailure(
    (value) => {
      const finding = value.findings.find((item) => item.id === 'F-03');
      finding.scenarioIds.push(finding.scenarioIds[0]);
    },
    /F-03 scenario links must be unique/,
  );
  expectCatalogFailure(
    (value) => { value.scenarios[0].automation = [['firebase', 'deploy']]; },
    /automation command is not an allowlisted/,
  );
  expectCatalogFailure(
    (value) => { value.scenarios[0].driver = 'manual-shell'; },
    /unsupported driver/,
  );
  expectCatalogFailure(
    (value) => { value.scenarios[0].platforms = ['production-browser']; },
    /unsupported value production-browser/,
  );
  expectCatalogFailure(
    (value) => { value.scenarios[0].minimumStage = 5; },
    /unsupported minimumStage/,
  );
  expectCatalogFailure(
    (value) => {
      const scenario = value.scenarios.find((item) => item.id === 'X05-RELEASE-REHEARSAL');
      scenario.minimumStage = 2;
    },
    /isolated staging only at Stage 4/,
  );
});

test('CLI option parsing rejects unknown, duplicate, equals, missing and combined selectors', () => {
  assert.deepEqual(parseOptions(['--finding', 'F-01'], ['finding']), {
    options: {finding: 'F-01'}, positionals: [],
  });
  assert.throws(() => parseOptions(['--unknown', 'x'], ['finding']), /Unknown option/);
  assert.throws(
    () => parseOptions(['--finding', 'F-01', '--finding', 'F-02'], ['finding']),
    /Duplicate option/,
  );
  assert.throws(() => parseOptions(['--finding=F-01'], ['finding']), /Unsupported option syntax/);
  assert.throws(() => parseOptions(['--finding'], ['finding']), /Missing value/);
  const catalog = readCatalog();
  assert.throws(
    () => selectScenarios(catalog, {scenario: 'F01-WEB-BOOT', finding: 'F-01'}),
    /Use only one/,
  );
  assert.throws(() => selectScenarios(catalog, {checkpoint: 'HEAD'}), /Unknown scenario filter/);
});

test('runbook requires the exact clean checkpoint before emitting runnable content', () => {
  const catalog = readCatalog();
  const scenario = selectScenarios(catalog, {scenario: 'F14-REVISION-N-NPLUS1'});
  const checkpoint = '6e74ba13faf316da2c506c2cafcfca985dd774cc';
  const cleanState = {head: checkpoint, clean: true};
  const runbook = formatRunbook(catalog, scenario, checkpoint, cleanState);

  assert.match(runbook, new RegExp(checkpoint));
  assert.match(runbook, /demo-hoopsconnect-stage0-platform/);
  assert.match(runbook, /Submit named revision N/);
  assert.match(runbook, /only N\+1 becomes accepted\/certified\/published/);
  assert.match(runbook, /Mutation scope: synthetic-emulator-only/);
  assert.throws(
    () => assertRunnableCheckpoint(checkpoint, {head: '1'.repeat(40), clean: true}),
    /not checked out/,
  );
  assert.throws(
    () => formatRunbook(catalog, scenario, checkpoint, {head: checkpoint, clean: false}),
    /not clean/,
  );

  const cli = path.resolve(__dirname, '../qa/acceptance_scenarios.js');
  const rejected = spawnSync(
    process.execPath,
    [cli, 'runbook', '--checkpoint', checkpoint, '--scenario', 'F14-REVISION-N-NPLUS1'],
    {cwd: path.resolve(__dirname, '../..'), encoding: 'utf8'},
  );
  assert.notEqual(rejected.status, 0);
  assert.equal(rejected.stdout, '');
  assert.doesNotMatch(rejected.stderr, /# HoopsConnect independent acceptance runbook/);
});

test('evidence records are bound to scenario dimensions and the current clean checkpoint', () => {
  const catalog = readCatalog();
  const valid = {
    scenarioId: 'F02-STATISTICIAN-ROUTES',
    checkpoint: '6e74ba13faf316da2c506c2cafcfca985dd774cc',
    executedAt: '2026-09-11T16:00:00Z',
    tester: 'Q',
    classification: 'product-defect',
    role: 'statistician',
    platform: 'web-chrome',
    dataState: 'assigned-game',
    expected: 'Assigned statistician reaches post-game entry.',
    observed: 'The route returned unrelated content.',
    severity: 'P0',
    responsibleWorkstream: 'A',
    evidence: ['screenshot.png', 'console.txt'],
  };
  const cleanState = {head: valid.checkpoint, clean: true};

  assert.equal(validateEvidenceRecord(valid, catalog, cleanState), true);
  assert.throws(
    () => validateEvidenceRecord({...valid, observed: ''}, catalog, cleanState),
    /missing observed/,
  );
  assert.throws(
    () => validateEvidenceRecord({...valid, checkpoint: 'HEAD'}, catalog, cleanState),
    /full SHA/,
  );
  assert.throws(
    () => validateEvidenceRecord({...valid, classification: 'probably-fixed'}, catalog, cleanState),
    /Unknown result classification/,
  );
  assert.throws(
    () => validateEvidenceRecord({...valid, role: 'guest'}, catalog, cleanState),
    /does not allow role guest/,
  );
  assert.throws(
    () => validateEvidenceRecord({...valid, platform: 'ios-safari-pwa'}, catalog, cleanState),
    /does not allow platform/,
  );
  assert.throws(
    () => validateEvidenceRecord({...valid, dataState: 'unlisted-state'}, catalog, cleanState),
    /does not allow data state/,
  );
  assert.throws(
    () => validateEvidenceRecord({...valid, responsibleWorkstream: 'D'}, catalog, cleanState),
    /does not allow responsible workstream/,
  );
  assert.throws(
    () => validateEvidenceRecord({...valid, severity: 'urgent'}, catalog, cleanState),
    /Unknown evidence severity/,
  );
  assert.throws(
    () => validateEvidenceRecord({...valid, executedAt: '2026-02-30T16:00:00Z'}, catalog, cleanState),
    /real canonical UTC date/,
  );
  assert.throws(
    () => validateEvidenceRecord(valid, catalog, {head: '2'.repeat(40), clean: true}),
    /must equal the current/,
  );
  assert.throws(
    () => validateEvidenceRecord(valid, catalog, {head: valid.checkpoint, clean: false}),
    /dirty working tree/,
  );
});

test('high-risk lifecycle and interaction gaps have explicit planned assertions', () => {
  const scenarios = new Map(readCatalog().scenarios.map((scenario) => [scenario.id, scenario]));
  const expected = {
    'F13-POST-GAME-ONLY-MATCH': ['passed start time', 'explicit lifecycle state'],
    'F15-CSV-SAFETY': ['formula-capable cell', 'leading whitespace'],
    'F16-COURTSIDE-INTERACTION': ['Shortcuts fire exactly once', 'caret/selection', 'leave/re-enter'],
    'F23-DIVISION-LIFECYCLE': ['unused division', 'referenced division', 'Archive is reversible'],
    'F24-MANUAL-SCHEDULE': ['two distinct eligible teams', 'venue-time conflicts', 'at most one game'],
    'X01-CLIENT-CLEANUP': ['sessions are fenced', 'listeners stop', 'notification tokens', 'user-scoped caches'],
  };
  for (const [scenarioId, phrases] of Object.entries(expected)) {
    const scenario = scenarios.get(scenarioId);
    assert.ok(scenario, scenarioId);
    const contract = [...scenario.steps, ...scenario.assertions].join(' ');
    for (const phrase of phrases) assert.ok(contract.includes(phrase), `${scenarioId}: ${phrase}`);
    assert.ok(scenario.minimumStage >= 1, `${scenarioId} must not be claimed as Stage 0 verified`);
  }
});
