'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');

const {
  REQUIRED_FINDING_IDS,
  REQUIRED_JOURNEY_IDS,
  formatRunbook,
  readCatalog,
  selectScenarios,
  validateCatalog,
  validateEvidenceRecord,
} = require('../qa/acceptance_scenarios');

test('acceptance catalog covers every remediation and cross-cutting finding', () => {
  const catalog = readCatalog();
  const counts = validateCatalog(catalog);

  assert.equal(counts.findings, 31);
  assert.equal(counts.scenarios, 41);
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
  assert.equal(findings.get('F-17').scenarioIds.length, 2);
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

test('automation is local-only and contains no deploy command', () => {
  const catalog = readCatalog();
  for (const scenario of catalog.scenarios) {
    assert.notEqual(scenario.mutationScope, 'production');
    for (const command of scenario.automation || []) {
      const rendered = command.join(' ');
      assert.doesNotMatch(rendered, /\bfirebase\s+deploy\b/);
      assert.doesNotMatch(rendered, /--project=hoops-connect-jm/);
    }
  }
  assert.equal(catalog.safety.projectId, 'demo-hoopsconnect-stage0-platform');
  assert.equal(catalog.safety.entrypoint, 'lib/main_qa.dart');
});

test('runbook includes exact checkpoint, safety state and ordered assertions', () => {
  const catalog = readCatalog();
  const scenario = selectScenarios(catalog, {scenario: 'F14-REVISION-N-NPLUS1'});
  const checkpoint = '6e74ba13faf316da2c506c2cafcfca985dd774cc';
  const runbook = formatRunbook(catalog, scenario, checkpoint);

  assert.match(runbook, new RegExp(checkpoint));
  assert.match(runbook, /demo-hoopsconnect-stage0-platform/);
  assert.match(runbook, /Submit named revision N/);
  assert.match(runbook, /only N\+1 becomes accepted\/certified\/published/);
  assert.match(runbook, /Mutation scope: synthetic-emulator-only/);
});

test('evidence records require reproducible defect context', () => {
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

  assert.equal(validateEvidenceRecord(valid, catalog), true);
  assert.throws(
    () => validateEvidenceRecord({...valid, observed: ''}, catalog),
    /missing observed/,
  );
  assert.throws(
    () => validateEvidenceRecord({...valid, checkpoint: 'HEAD'}, catalog),
    /full SHA/,
  );
  assert.throws(
    () => validateEvidenceRecord({...valid, classification: 'probably-fixed'}, catalog),
    /Unknown result classification/,
  );
});
