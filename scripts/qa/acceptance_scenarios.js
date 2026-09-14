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
const EXPECTED_ALLOWED_HOSTS = Object.freeze(['127.0.0.1', 'localhost', '::1']);
const EXPECTED_STAGE0_SUCCESS_MARKERS = Object.freeze([
  'HOOPSCONNECT_QA_FIXTURES_OK',
  'HOOPSCONNECT_WEB_BOOT_OK fresh=true update=true newDocument=true staleWorkerRemoved=true',
  'HOOPSCONNECT_QA_DELIVERY_GUARD_OK codebases=default,public',
]);
const REQUIRED_FORBIDDEN_ACTIONS = Object.freeze([
  'production data write',
  'deployment',
  'store submission',
  'real notification delivery',
  'activation flag change',
  'destructive production migration',
]);
const ALLOWED_ROLES = Object.freeze([
  'guest', 'fan', 'rep', 'statistician', 'media', 'press', 'admin', 'superAdmin',
]);
const ALLOWED_WORKSTREAMS = Object.freeze(['A', 'B', 'C', 'D', 'E', 'F', 'I', 'Q']);
const ALLOWED_DRIVERS = Object.freeze([
  'browser',
  'browser-native',
  'browser-native-screen-reader',
  'browser-screen-reader',
  'browser-screen-reader-native',
  'hybrid',
  'review-provider',
  'shell-browser',
  'shell-browser-provider-review',
  'shell-hybrid',
]);
const ALLOWED_PLATFORMS = Object.freeze([
  'android',
  'android-talkback',
  'ios',
  'ios-safari-pwa',
  'ios-voiceover',
  'web-chrome',
]);
const ALLOWED_STAGES = Object.freeze([0, 1, 2, 3, 4]);
const ALLOWED_MUTATION_SCOPES = Object.freeze([
  'none', 'synthetic-emulator-only', 'isolated-staging-only',
]);
const ALLOWED_RESULT_CLASSIFICATIONS = Object.freeze([
  'pass',
  'product-defect',
  'fixture-error',
  'infrastructure-unavailable',
  'blocked-decision',
  'not-run',
]);
const ALLOWED_SEVERITIES = Object.freeze(['none', 'P0', 'P1', 'P2', 'P3']);
const SAFE_AUTOMATION_COMMANDS = new Set([
  ['node', 'scripts/run_local_qa.js'],
  ['flutter', 'test', '--no-pub', 'test/features/auth/login_screen_test.dart'],
  [
    'flutter',
    'test',
    '--no-pub',
    'test/app/branded_theme_test.dart',
    'test/core/widgets/app_ui_patterns_test.dart',
  ],
].map((command) => JSON.stringify(command)));
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

function assertNonEmptyStrings(values, label) {
  assert(Array.isArray(values) && values.length > 0, `${label} must be a non-empty array.`);
  for (const value of values) {
    assert(typeof value === 'string' && value.trim() === value && value.length > 0, `${label} has an invalid value.`);
  }
}

function assertExactValues(values, expected, label) {
  assertNonEmptyStrings(values, label);
  assertUnique(values, label);
  assert(
    JSON.stringify(sorted(values)) === JSON.stringify(sorted(expected)),
    `${label} must contain exactly ${expected.join(', ')}.`,
  );
}

function assertAllowedValues(values, allowed, label) {
  assertNonEmptyStrings(values, label);
  assertUnique(values, label);
  for (const value of values) {
    assert(allowed.includes(value), `${label} contains unsupported value ${value}.`);
  }
}

function assertSafeAutomationCommand(command, label) {
  assertNonEmptyStrings(command, label);
  assert(
    SAFE_AUTOMATION_COMMANDS.has(JSON.stringify(command)),
    `${label} is not an allowlisted local-only command.`,
  );
}

function validateCatalog(catalog = readCatalog()) {
  assert(catalog && typeof catalog === 'object' && !Array.isArray(catalog), 'Catalog must be an object.');
  assert(catalog.schemaVersion === 1, 'Unsupported acceptance scenario schema.');
  assert(catalog.suiteId === 'hoopsconnect-qa-remediation-acceptance-v1', 'Unexpected acceptance suite.');
  assert(
    catalog.plan === 'docs/planning/qa-remediation-execution-plan-2026-09-11.md',
    'Unexpected remediation plan path.',
  );
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
  assertSafeAutomationCommand(catalog.stage0?.command, 'Stage 0 command');
  assertExactValues(
    catalog.stage0?.successMarkers,
    EXPECTED_STAGE0_SUCCESS_MARKERS,
    'Stage 0 success markers',
  );
  assertExactValues(catalog.safety?.allowedHosts, EXPECTED_ALLOWED_HOSTS, 'Allowed hosts');
  assertNonEmptyStrings(catalog.safety?.forbiddenActions, 'Forbidden actions');
  for (const action of REQUIRED_FORBIDDEN_ACTIONS) {
    assert(catalog.safety.forbiddenActions.includes(action), `Forbidden actions must include ${action}.`);
  }
  assertExactValues(catalog.roles, ALLOWED_ROLES, 'Catalog roles');
  assertExactValues(
    catalog.resultClassifications,
    ALLOWED_RESULT_CLASSIFICATIONS,
    'Result classifications',
  );
  assertExactValues(catalog.severities, ALLOWED_SEVERITIES, 'Evidence severities');
  assertNonEmptyStrings(catalog.defaultEvidence, 'Default evidence');
  assert(Array.isArray(catalog.findings), 'Findings must be an array.');
  assert(Array.isArray(catalog.scenarios), 'Scenarios must be an array.');
  assert(Array.isArray(catalog.journeys), 'Journeys must be an array.');
  assert(Array.isArray(catalog.viewports), 'Viewports must be an array.');

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
    assert(typeof finding.title === 'string' && finding.title.length > 0, `${finding.id} needs a title.`);
    assertAllowedValues(finding.owners, ALLOWED_WORKSTREAMS, `${finding.id} owners`);
    assert(
      Array.isArray(finding.scenarioIds) && finding.scenarioIds.length > 0,
      `${finding.id} needs at least one scenario.`,
    );
    assertUnique(finding.scenarioIds, `${finding.id} scenario links`);
    for (const scenarioId of finding.scenarioIds) {
      const scenario = scenarioById.get(scenarioId);
      assert(scenario, `${finding.id} references missing scenario ${scenarioId}.`);
      assert(scenario.covers.includes(finding.id), `${scenarioId} must cover ${finding.id}.`);
    }
  }

  for (const scenario of catalog.scenarios) {
    for (const key of ['covers', 'roles', 'platforms', 'dataStates', 'steps', 'assertions', 'evidence']) {
      assertNonEmptyStrings(scenario[key], `${scenario.id} ${key}`);
    }
    assertUnique(scenario.covers, `${scenario.id} covers`);
    assert(ALLOWED_STAGES.includes(scenario.minimumStage), `${scenario.id} has an unsupported minimumStage.`);
    assert(ALLOWED_DRIVERS.includes(scenario.driver), `${scenario.id} has an unsupported driver.`);
    assert(
      ALLOWED_MUTATION_SCOPES.includes(scenario.mutationScope),
      `${scenario.id} has an unsafe mutationScope.`,
    );
    if (scenario.mutationScope === 'isolated-staging-only') {
      assert(scenario.minimumStage === 4, `${scenario.id} may use isolated staging only at Stage 4.`);
    }
    for (const findingId of scenario.covers) {
      assert(findingById.has(findingId), `${scenario.id} covers unknown finding ${findingId}.`);
      assert(
        findingById.get(findingId).scenarioIds.includes(scenario.id),
        `${scenario.id} is not linked back from ${findingId}.`,
      );
    }
    assertAllowedValues(scenario.roles, ALLOWED_ROLES, `${scenario.id} roles`);
    assertAllowedValues(scenario.platforms, ALLOWED_PLATFORMS, `${scenario.id} platforms`);
    if (scenario.preconditions !== undefined) {
      assertNonEmptyStrings(scenario.preconditions, `${scenario.id} preconditions`);
    }
    for (const command of scenario.automation || []) {
      assertSafeAutomationCommand(command, `${scenario.id} automation command`);
    }
  }

  const journeyIds = catalog.journeys.map((journey) => journey.id);
  assertUnique(journeyIds, 'Journey IDs');
  assert(
    JSON.stringify(sorted(journeyIds)) === JSON.stringify(sorted(REQUIRED_JOURNEY_IDS)),
    'Catalog must contain exactly the required journeys.',
  );
  for (const journey of catalog.journeys) {
    assertNonEmptyStrings(journey.scenarioIds, `${journey.id} scenarios`);
    assertUnique(journey.scenarioIds, `${journey.id} scenarios`);
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
    JSON.stringify(catalog.viewports) === JSON.stringify([
      {name: 'phone', width: 375, height: 812},
      {name: 'tablet', width: 768, height: 1024},
      {name: 'desktop', width: 1440, height: 900},
    ]),
    'Responsive acceptance must retain the exact phone, tablet and desktop viewports.',
  );

  return {
    findings: catalog.findings.length,
    scenarios: catalog.scenarios.length,
    journeys: catalog.journeys.length,
  };
}

function parseOptions(args, allowedNames) {
  const options = {};
  const positionals = [];
  for (let index = 0; index < args.length; index += 1) {
    const value = args[index];
    if (!value.startsWith('--')) {
      positionals.push(value);
      continue;
    }
    assert(value !== '--' && !value.includes('='), `Unsupported option syntax ${value}.`);
    const name = value.slice(2);
    assert(allowedNames.includes(name), `Unknown option --${name}.`);
    assert(options[name] === undefined, `Duplicate option --${name}.`);
    const next = args[index + 1];
    if (!next || next.startsWith('--')) throw new Error(`Missing value for --${name}.`);
    options[name] = next;
    index += 1;
  }
  return {options, positionals};
}

function assertSingleSelector(options) {
  const selectors = ['scenario', 'finding', 'journey'].filter((name) => options[name] !== undefined);
  assert(selectors.length <= 1, 'Use only one of --scenario, --finding or --journey.');
}

function selectScenarios(catalog, options = {}) {
  for (const name of Object.keys(options)) {
    assert(['scenario', 'finding', 'journey'].includes(name), `Unknown scenario filter ${name}.`);
  }
  assertSingleSelector(options);
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

function assertRunnableCheckpoint(checkpoint, state = repositoryState()) {
  assert(state.clean === true, 'Working tree is not clean; no runnable runbook was emitted.');
  assert(state.head === checkpoint, 'Requested checkpoint is not checked out; no runnable runbook was emitted.');
  return state;
}

function formatRunbook(catalog, scenarios, checkpoint, state = repositoryState()) {
  assertRunnableCheckpoint(checkpoint, state);
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

function normalizedIsoTimestamp(value) {
  assert(typeof value === 'string' && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/.test(value),
    'Evidence executedAt must be a canonical UTC ISO-8601 timestamp.');
  const parsed = Date.parse(value);
  assert(Number.isFinite(parsed), 'Evidence executedAt must be a real date.');
  const canonical = new Date(parsed).toISOString().replace('.000Z', 'Z');
  assert(canonical === value, 'Evidence executedAt must be a real canonical UTC date.');
  return value;
}

function validateEvidenceRecord(record, catalog = readCatalog(), state = repositoryState()) {
  assert(record && typeof record === 'object' && !Array.isArray(record), 'Evidence record must be an object.');
  const scenarioById = new Map(catalog.scenarios.map((scenario) => [scenario.id, scenario]));
  const findingById = new Map(catalog.findings.map((finding) => [finding.id, finding]));
  for (const field of RESULT_REQUIRED_FIELDS) {
    assert(record[field] !== undefined && record[field] !== '', `Evidence record is missing ${field}.`);
  }
  const scenario = scenarioById.get(record.scenarioId);
  assert(scenario, `Unknown evidence scenario ${record.scenarioId}.`);
  assert(/^[a-f0-9]{40}$/.test(record.checkpoint), 'Evidence checkpoint must be a full SHA.');
  assert(state.clean === true, 'Evidence cannot be accepted from a dirty working tree.');
  assert(record.checkpoint === state.head, 'Evidence checkpoint must equal the current checked-out HEAD.');
  normalizedIsoTimestamp(record.executedAt);
  assert(
    catalog.resultClassifications.includes(record.classification),
    `Unknown result classification ${record.classification}.`,
  );
  assert(scenario.roles.includes(record.role), `${record.scenarioId} does not allow role ${record.role}.`);
  assert(scenario.platforms.includes(record.platform), `${record.scenarioId} does not allow platform ${record.platform}.`);
  assert(scenario.dataStates.includes(record.dataState), `${record.scenarioId} does not allow data state ${record.dataState}.`);
  const responsibleOwners = new Set(
    scenario.covers.flatMap((findingId) => findingById.get(findingId).owners),
  );
  assert(
    responsibleOwners.has(record.responsibleWorkstream),
    `${record.scenarioId} does not allow responsible workstream ${record.responsibleWorkstream}.`,
  );
  assert(catalog.severities.includes(record.severity), `Unknown evidence severity ${record.severity}.`);
  assertNonEmptyStrings(record.evidence, 'Evidence references');
  for (const field of ['tester', 'expected', 'observed']) {
    assert(
      typeof record[field] === 'string' && record[field].trim().length > 0,
      `Evidence ${field} must be non-empty text.`,
    );
  }
  return true;
}

function verifyEvidenceFile(file, catalog, state = repositoryState()) {
  const resolved = path.resolve(process.cwd(), file);
  const parsed = JSON.parse(fs.readFileSync(resolved, 'utf8'));
  const records = Array.isArray(parsed) ? parsed : [parsed];
  assert(records.length > 0, 'Evidence file has no records.');
  records.forEach((record) => validateEvidenceRecord(record, catalog, state));
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
    assert(rest.length === 0, 'validate accepts no arguments.');
    console.log(
      `HOOPSCONNECT_ACCEPTANCE_SCENARIOS_OK findings=${counts.findings} ` +
      `scenarios=${counts.scenarios} journeys=${counts.journeys}`,
    );
    return;
  }
  if (command === 'list') {
    const {options, positionals} = parseOptions(rest, ['finding', 'journey']);
    assert(positionals.length === 0, 'list accepts only named filters.');
    assertSingleSelector(options);
    for (const scenario of selectScenarios(catalog, options)) {
      console.log(`${scenario.id}\t${scenario.covers.join(',')}\tstage${scenario.minimumStage}\t${scenario.driver}`);
    }
    return;
  }
  if (command === 'runbook') {
    const {options, positionals} = parseOptions(rest, ['checkpoint', 'scenario', 'finding', 'journey']);
    assert(positionals.length === 0, 'runbook accepts only named options.');
    assertSingleSelector(options);
    const checkpoint = resolveCheckpoint(options.checkpoint);
    const filters = {...options};
    delete filters.checkpoint;
    process.stdout.write(formatRunbook(catalog, selectScenarios(catalog, filters), checkpoint));
    return;
  }
  if (command === 'verify-evidence') {
    const {options, positionals} = parseOptions(rest, []);
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
  ALLOWED_DRIVERS,
  ALLOWED_PLATFORMS,
  ALLOWED_SEVERITIES,
  ALLOWED_STAGES,
  CATALOG_PATH,
  EXPECTED_ALLOWED_HOSTS,
  EXPECTED_STAGE0_SUCCESS_MARKERS,
  REQUIRED_FINDING_IDS,
  REQUIRED_FORBIDDEN_ACTIONS,
  REQUIRED_JOURNEY_IDS,
  RESULT_REQUIRED_FIELDS,
  SAFE_AUTOMATION_COMMANDS,
  assertRunnableCheckpoint,
  formatRunbook,
  parseOptions,
  readCatalog,
  repositoryState,
  resolveCheckpoint,
  selectScenarios,
  validateCatalog,
  validateEvidenceRecord,
  verifyEvidenceFile,
};
