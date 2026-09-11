#!/usr/bin/env node
'use strict';

const {execFileSync} = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const REPOSITORY_ROOT = path.resolve(__dirname, '../..');
const CATALOG_PATH = path.join(__dirname, 'acceptance_scenarios.v1.json');
const REQUIRED_FINDING_IDS = Object.freeze([
  ...Array.from({length: 26}, (_, index) => `F-${String(index + 1).padStart(2, '0')}`),
  ...Array.from({length: 5}, (_, index) => `X-${String(index + 1).padStart(2, '0')}`),
]);
const REQUIRED_JOURNEY_IDS = Object.freeze([
  'role-route',
  'error-retry',
  'responsive-accessibility',
  'revision-n-nplus1',
  'public-privacy',
  'offline-recovery',
  'deletion-lifecycle',
  'staging-release',
]);
const RESULT_REQUIRED_FIELDS = Object.freeze([
  'scenarioId',
  'checkpoint',
  'executedAt',
  'tester',
  'classification',
  'role',
  'platform',
  'dataState',
  'expected',
  'observed',
  'severity',
  'responsibleWorkstream',
  'evidence',
]);

function readCatalog() {
  return JSON.parse(fs.readFileSync(CATALOG_PATH, 'utf8'));
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function sorted(values) {
  return [...values].sort((left, right) => left.localeCompare(right));
}

function assertUnique(values, label) {
  assert(new Set(values).size === values.length, `${label} must be unique.`);
}

function validateCatalog(catalog = readCatalog()) {
  assert(catalog.schemaVersion === 1, 'Unsupported acceptance scenario schema.');
  assert(
    catalog.safety?.projectId === 'demo-hoopsconnect-stage0-platform',
    'Acceptance scenarios must target the isolated Stage 0 project.',
  );
  assert(
    catalog.safety?.entrypoint === 'lib/main_qa.dart',
    'Acceptance scenarios must use the QA-only Flutter entrypoint.',
  );
  assert(/^[a-f0-9]{64}$/.test(catalog.sourceAudit?.sha256 || ''), 'Source audit hash is invalid.');
  assert(/^[a-f0-9]{40}$/.test(catalog.stage0?.checkpoint || ''), 'Stage 0 checkpoint must be a full SHA.');

  const findingIds = catalog.findings.map((finding) => finding.id);
  assertUnique(findingIds, 'Finding IDs');
  assert(
    JSON.stringify(sorted(findingIds)) === JSON.stringify(sorted(REQUIRED_FINDING_IDS)),
    'Catalog must contain exactly F-01 through F-26 and X-01 through X-05.',
  );

  const scenarioIds = catalog.scenarios.map((scenario) => scenario.id);
  assertUnique(scenarioIds, 'Scenario IDs');
  const scenarioById = new Map(catalog.scenarios.map((scenario) => [scenario.id, scenario]));
  const findingById = new Map(catalog.findings.map((finding) => [finding.id, finding]));

  for (const finding of catalog.findings) {
    assert(Array.isArray(finding.owners) && finding.owners.length > 0, `${finding.id} needs an owner.`);
    assert(
      Array.isArray(finding.scenarioIds) && finding.scenarioIds.length > 0,
      `${finding.id} needs at least one scenario.`,
    );
    for (const scenarioId of finding.scenarioIds) {
      const scenario = scenarioById.get(scenarioId);
      assert(scenario, `${finding.id} references missing scenario ${scenarioId}.`);
      assert(scenario.covers.includes(finding.id), `${scenarioId} must cover ${finding.id}.`);
    }
  }

  for (const scenario of catalog.scenarios) {
    for (const key of ['covers', 'roles', 'platforms', 'dataStates', 'steps', 'assertions', 'evidence']) {
      assert(Array.isArray(scenario[key]) && scenario[key].length > 0, `${scenario.id} needs ${key}.`);
    }
    assert(Number.isInteger(scenario.minimumStage), `${scenario.id} needs an integer minimumStage.`);
    assert(
      ['none', 'synthetic-emulator-only', 'isolated-staging-only'].includes(scenario.mutationScope),
      `${scenario.id} has an unsafe mutationScope.`,
    );
    for (const findingId of scenario.covers) {
      assert(findingById.has(findingId), `${scenario.id} covers unknown finding ${findingId}.`);
      assert(
        findingById.get(findingId).scenarioIds.includes(scenario.id),
        `${scenario.id} is not linked back from ${findingId}.`,
      );
    }
    for (const role of scenario.roles) {
      assert(catalog.roles.includes(role), `${scenario.id} uses unknown role ${role}.`);
    }
    for (const command of scenario.automation || []) {
      assert(Array.isArray(command) && command.length > 0, `${scenario.id} has an invalid automation command.`);
      const joined = command.join(' ');
      assert(!/\bfirebase\s+deploy\b/.test(joined), `${scenario.id} must not deploy.`);
      assert(!joined.includes('--project=hoops-connect-jm'), `${scenario.id} must not target production.`);
    }
  }

  const journeyIds = catalog.journeys.map((journey) => journey.id);
  assertUnique(journeyIds, 'Journey IDs');
  for (const journeyId of REQUIRED_JOURNEY_IDS) {
    assert(journeyIds.includes(journeyId), `Missing required journey ${journeyId}.`);
  }
  for (const journey of catalog.journeys) {
    assert(journey.scenarioIds.length > 0, `${journey.id} has no scenarios.`);
    for (const scenarioId of journey.scenarioIds) {
      assert(scenarioById.has(scenarioId), `${journey.id} references missing scenario ${scenarioId}.`);
    }
  }

  for (const [findingId, minimum] of Object.entries({'F-03': 3, 'F-17': 2, 'F-19': 2, 'F-25': 3})) {
    assert(
      findingById.get(findingId).scenarioIds.length >= minimum,
      `${findingId} must remain split into at least ${minimum} action checks.`,
    );
  }

  assert(
    scenarioById.get('F14-REVISION-N-NPLUS1').dataStates.includes('revision-N-plus-1'),
    'Revision acceptance must name N+1.',
  );
  for (const state of ['active', 'blocked', 'suspended', 'provider-cancelled', 'deleting', 'cleanup-pending']) {
    assert(
      scenarioById.get('X01-DELETION-ROUTES').dataStates.includes(state),
      `Deletion routes must cover ${state}.`,
    );
  }
  for (const state of ['response-unknown', 'relaunch', 'writer-conflict', 'assignment-revoked', 'quota']) {
    assert(
      scenarioById.get('X02-OFFLINE-RECOVERY').dataStates.includes(state),
      `Offline recovery must cover ${state}.`,
    );
  }
  assert(
    catalog.viewports.map((viewport) => viewport.width).join(',') === '375,768,1440',
    'Responsive acceptance must retain 375, 768 and 1440 pixel widths.',
  );

  return {
    findings: catalog.findings.length,
    scenarios: catalog.scenarios.length,
    journeys: catalog.journeys.length,
  };
}

function parseOptions(args) {
  const options = {};
  const positionals = [];
  for (let index = 0; index < args.length; index += 1) {
    const value = args[index];
    if (!value.startsWith('--')) {
      positionals.push(value);
      continue;
    }
    const name = value.slice(2);
    const next = args[index + 1];
    if (!next || next.startsWith('--')) throw new Error(`Missing value for --${name}.`);
    options[name] = next;
    index += 1;
  }
  return {options, positionals};
}

function selectScenarios(catalog, options = {}) {
  let selected = catalog.scenarios;
  if (options.scenario) {
    selected = selected.filter((scenario) => scenario.id === options.scenario);
    assert(selected.length === 1, `Unknown scenario ${options.scenario}.`);
  }
  if (options.finding) {
    assert(REQUIRED_FINDING_IDS.includes(options.finding), `Unknown finding ${options.finding}.`);
    selected = selected.filter((scenario) => scenario.covers.includes(options.finding));
  }
  if (options.journey) {
    const journey = catalog.journeys.find((candidate) => candidate.id === options.journey);
    assert(journey, `Unknown journey ${options.journey}.`);
    const order = new Map(journey.scenarioIds.map((scenarioId, index) => [scenarioId, index]));
    selected = selected
      .filter((scenario) => order.has(scenario.id))
      .sort((left, right) => order.get(left.id) - order.get(right.id));
  }
  assert(selected.length > 0, 'No scenarios match the requested filters.');
  return selected;
}

function resolveCheckpoint(value) {
  assert(value, 'runbook requires --checkpoint <commit>.');
  const resolved = execFileSync('git', ['rev-parse', '--verify', `${value}^{commit}`], {
    cwd: REPOSITORY_ROOT,
    encoding: 'utf8',
  }).trim();
  assert(/^[a-f0-9]{40}$/.test(resolved), 'Checkpoint did not resolve to a full commit SHA.');
  return resolved;
}

function repositoryState() {
  const head = execFileSync('git', ['rev-parse', 'HEAD'], {
    cwd: REPOSITORY_ROOT,
    encoding: 'utf8',
  }).trim();
  const status = execFileSync('git', ['status', '--porcelain'], {
    cwd: REPOSITORY_ROOT,
    encoding: 'utf8',
  });
  return {head, clean: status.length === 0};
}

function formatRunbook(catalog, scenarios, checkpoint) {
  const state = repositoryState();
  const lines = [
    '# HoopsConnect independent acceptance runbook',
    '',
    `Checkpoint: \`${checkpoint}\``,
    `Current HEAD: \`${state.head}\``,
    `Working tree clean: \`${state.clean}\``,
    `Synthetic project: \`${catalog.safety.projectId}\``,
    `QA entrypoint: \`${catalog.safety.entrypoint}\``,
    '',
  ];
  if (state.head !== checkpoint) {
    lines.push('STOP: the requested checkpoint is not checked out. Do not record closure evidence.', '');
  }
  if (!state.clean) {
    lines.push('STOP: the working tree is not clean. Runs may diagnose, but cannot close a finding.', '');
  }
  for (const scenario of scenarios) {
    lines.push(`## ${scenario.id}`, '');
    lines.push(`Covers: ${scenario.covers.join(', ')}`);
    lines.push(`Minimum stage: ${scenario.minimumStage}`);
    lines.push(`Driver: ${scenario.driver}`);
    lines.push(`Roles: ${scenario.roles.join(', ')}`);
    lines.push(`Platforms: ${scenario.platforms.join(', ')}`);
    lines.push(`Data states: ${scenario.dataStates.join(', ')}`);
    lines.push(`Mutation scope: ${scenario.mutationScope}`, '');
    if (scenario.preconditions?.length) {
      lines.push('Preconditions:', ...scenario.preconditions.map((item) => `- ${item}`), '');
    }
    lines.push('Steps:', ...scenario.steps.map((item, index) => `${index + 1}. ${item}`), '');
    lines.push('Assertions:', ...scenario.assertions.map((item) => `- ${item}`), '');
    lines.push(
      'Evidence:',
      ...[...catalog.defaultEvidence, ...scenario.evidence].map((item) => `- ${item}`),
      '',
    );
    if (scenario.automation?.length) {
      lines.push(
        'Automation commands:',
        ...scenario.automation.map((command) => `- \`${command.join(' ')}\``),
        '',
      );
    }
  }
  return `${lines.join('\n')}\n`;
}

function validateEvidenceRecord(record, catalog = readCatalog()) {
  const scenarioIds = new Set(catalog.scenarios.map((scenario) => scenario.id));
  for (const field of RESULT_REQUIRED_FIELDS) {
    assert(record[field] !== undefined && record[field] !== '', `Evidence record is missing ${field}.`);
  }
  assert(scenarioIds.has(record.scenarioId), `Unknown evidence scenario ${record.scenarioId}.`);
  assert(/^[a-f0-9]{40}$/.test(record.checkpoint), 'Evidence checkpoint must be a full SHA.');
  assert(
    catalog.resultClassifications.includes(record.classification),
    `Unknown result classification ${record.classification}.`,
  );
  assert(Array.isArray(record.evidence) && record.evidence.length > 0, 'Evidence must be a non-empty array.');
  return true;
}

function verifyEvidenceFile(file, catalog) {
  const resolved = path.resolve(process.cwd(), file);
  const parsed = JSON.parse(fs.readFileSync(resolved, 'utf8'));
  const records = Array.isArray(parsed) ? parsed : [parsed];
  assert(records.length > 0, 'Evidence file has no records.');
  records.forEach((record) => validateEvidenceRecord(record, catalog));
  return records.length;
}

function usage() {
  return [
    'Usage:',
    '  node scripts/qa/acceptance_scenarios.js validate',
    '  node scripts/qa/acceptance_scenarios.js list [--finding F-01] [--journey role-route]',
    '  node scripts/qa/acceptance_scenarios.js runbook --checkpoint <commit> [--scenario ID|--finding ID|--journey ID]',
    '  node scripts/qa/acceptance_scenarios.js verify-evidence <file.json>',
  ].join('\n');
}

function main(args = process.argv.slice(2)) {
  const [command, ...rest] = args;
  const catalog = readCatalog();
  const counts = validateCatalog(catalog);

  if (command === 'validate') {
    console.log(
      `HOOPSCONNECT_ACCEPTANCE_SCENARIOS_OK findings=${counts.findings} ` +
      `scenarios=${counts.scenarios} journeys=${counts.journeys}`,
    );
    return;
  }
  if (command === 'list') {
    const {options, positionals} = parseOptions(rest);
    assert(positionals.length === 0, 'list accepts only named filters.');
    for (const scenario of selectScenarios(catalog, options)) {
      console.log(`${scenario.id}\t${scenario.covers.join(',')}\tstage${scenario.minimumStage}\t${scenario.driver}`);
    }
    return;
  }
  if (command === 'runbook') {
    const {options, positionals} = parseOptions(rest);
    assert(positionals.length === 0, 'runbook accepts only named options.');
    const checkpoint = resolveCheckpoint(options.checkpoint);
    process.stdout.write(formatRunbook(catalog, selectScenarios(catalog, options), checkpoint));
    return;
  }
  if (command === 'verify-evidence') {
    const {options, positionals} = parseOptions(rest);
    assert(Object.keys(options).length === 0 && positionals.length === 1, 'verify-evidence requires one JSON file.');
    const count = verifyEvidenceFile(positionals[0], catalog);
    console.log(`HOOPSCONNECT_ACCEPTANCE_EVIDENCE_OK records=${count}`);
    return;
  }
  throw new Error(usage());
}

if (require.main === module) {
  try {
    main();
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}

module.exports = {
  CATALOG_PATH,
  REQUIRED_FINDING_IDS,
  REQUIRED_JOURNEY_IDS,
  RESULT_REQUIRED_FIELDS,
  formatRunbook,
  readCatalog,
  repositoryState,
  resolveCheckpoint,
  selectScenarios,
  validateCatalog,
  validateEvidenceRecord,
  verifyEvidenceFile,
};
