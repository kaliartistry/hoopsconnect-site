const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const contract = require("../lib/domain/official_stats_contract.js");
const fixture = JSON.parse(fs.readFileSync(
  path.join(__dirname, "../../contracts/official_stats/v2/contract_fixtures.json"),
  "utf8",
));

test("TypeScript contract versions and states match shared fixtures", () => {
  assert.deepEqual(contract.officialStatVersions, {
    authorizationSchemaVersion: fixture.versions.authorizationSchemaVersion,
    canonicalEncodingVersion: fixture.versions.canonicalEncodingVersion,
    commandSchemaVersion: fixture.versions.commandSchemaVersion,
    dataSchemaVersion: fixture.versions.dataSchemaVersion,
    domainSchemaVersion: fixture.versions.domainSchemaVersion,
    projectionSchemaVersion: fixture.versions.projectionSchemaVersion,
  });
  assert.deepEqual(contract.playStates, fixture.states.play);
  assert.deepEqual(contract.reviewStates, fixture.states.review);
  assert.deepEqual(contract.publicationStates, fixture.states.publication);
  assert.deepEqual(contract.resultDispositions, fixture.states.resultDisposition);
  assert.deepEqual(contract.statisticsDispositions, fixture.states.statisticsDisposition);
  assert.deepEqual(contract.privacyPermissionStates, fixture.states.privacy);
  assert.deepEqual(contract.commandErrorRetries, fixture.commandErrors);
  assert.deepEqual(contract.commandErrorIdempotency, fixture.commandErrorIdempotency);
});

test("TypeScript canonical encoding matches shared Dart golden cases", () => {
  for (const testCase of fixture.canonicalCases) {
    assert.equal(contract.canonicalEncode(testCase.input), testCase.canonical, testCase.name);
    assert.equal(contract.canonicalSha256(testCase.input), testCase.sha256, testCase.name);
  }
});

test("timestamps are UTC with millisecond precision", () => {
  const testCase = fixture.timestampCases[0];
  assert.equal(contract.canonicalEncode(new Date(testCase.input)), `"${testCase.canonical}"`);
});

test("ambiguous canonical values fail closed", () => {
  assert.throws(() => contract.canonicalEncode(0.5));
  assert.throws(() => contract.canonicalEncode(Number.MAX_SAFE_INTEGER + 1));
  assert.throws(() => contract.canonicalEncode(new Set([1, 2])));
  assert.throws(() => contract.canonicalEncode({"naïveKey": 1}));
  assert.throws(() => contract.canonicalEncode(new Date("+010000-01-01T00:00:00.000Z")));
});
