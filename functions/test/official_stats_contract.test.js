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
  assert.deepEqual(contract.journalOperationTypes, fixture.states.journalOperation);
  assert.deepEqual(contract.journalDeliveryStates, fixture.states.journalDelivery);
  assert.deepEqual(contract.boxScorePartKinds, fixture.states.boxScorePartKind);
  assert.deepEqual(contract.commandErrorRetries, fixture.commandErrors);
  assert.deepEqual(contract.commandErrorIdempotency, fixture.commandErrorIdempotency);
});

test("TypeScript canonical encoding matches shared Dart golden cases", () => {
  for (const testCase of fixture.canonicalCases) {
    assert.equal(contract.canonicalEncode(testCase.input), testCase.canonical, testCase.name);
    assert.equal(contract.canonicalSha256(testCase.input), testCase.sha256, testCase.name);
  }
  const byName = Object.fromEntries(fixture.canonicalCases.map((entry) => [entry.name, entry]));
  assert.equal(
    byName["hangul-last-valid-precomposed"].sha256,
    byName["hangul-last-valid-decomposed"].sha256,
  );
  assert.notEqual(
    byName["hangul-first-after-range"].sha256,
    byName["jamo-after-leading-range"].sha256,
  );
  assert.equal(
    contract.officialStatUnicodeNormalizationImplementation,
    "unicode-17.0-ecmascript-string-normalize-nfc-v1",
  );
  assert.equal(contract.officialStatUnicodeRuntimeVersion, "17.0");
  assert.equal(process.versions.unicode, "17.0");
  assert.doesNotThrow(() => contract.assertOfficialStatUnicodeRuntime());
  assert.equal(
    byName["unicode-17-combining-order-sentinel"].canonical,
    "{\"text\":\"ạ᫏\"}",
  );
});

test("timestamps are UTC with millisecond precision", () => {
  const testCase = fixture.timestampCases[0];
  assert.equal(contract.canonicalEncode(new Date(testCase.input)), `"${testCase.canonical}"`);
});

test("canonical numeric domain matches mathematical safe integers", () => {
  assert.equal(contract.canonicalEncode(Number.MIN_SAFE_INTEGER), "-9007199254740991");
  assert.equal(contract.canonicalEncode(Number.MAX_SAFE_INTEGER), "9007199254740991");
  assert.equal(contract.canonicalEncode(1.0), "1");
  assert.equal(contract.canonicalEncode(Number("1e0")), "1");
  assert.equal(contract.canonicalEncode(-0), "0");
  assert.equal(contract.canonicalEncode(JSON.parse("-0")), "0");
  for (const value of [
    Number.MIN_SAFE_INTEGER - 1,
    Number.MAX_SAFE_INTEGER + 1,
    0.5,
    Number.NaN,
    Number.POSITIVE_INFINITY,
    Number.NEGATIVE_INFINITY,
  ]) assert.throws(() => contract.canonicalEncode(value));
});

test("unsupported JavaScript containers and object properties fail closed", () => {
  assert.throws(() => contract.canonicalEncode(new Set([1, 2])));
  assert.throws(() => contract.canonicalEncode(new Map([["a", 1]])));
  assert.throws(() => contract.canonicalEncode(/x/));
  assert.throws(() => contract.canonicalEncode(new (class CustomRecord {})()));
  assert.throws(() => contract.canonicalEncode({"naïveKey": 1}));
  assert.throws(() => contract.canonicalEncode(new Date("+010000-01-01T00:00:00.000Z")));
  assert.throws(() => contract.canonicalEncode(undefined));

  const sparse = new Array(2);
  sparse[1] = 1;
  assert.throws(() => contract.canonicalEncode(sparse));

  const extraArray = [1];
  extraArray.extra = true;
  assert.throws(() => contract.canonicalEncode(extraArray));

  const symbolRecord = {a: 1};
  symbolRecord[Symbol("hidden")] = 2;
  assert.throws(() => contract.canonicalEncode(symbolRecord));

  const nonEnumerable = {a: 1};
  Object.defineProperty(nonEnumerable, "hidden", {value: 2, enumerable: false});
  assert.throws(() => contract.canonicalEncode(nonEnumerable));

  const accessor = {};
  Object.defineProperty(accessor, "a", {get: () => 1, enumerable: true});
  assert.throws(() => contract.canonicalEncode(accessor));

  const modifiedDate = new Date("2026-01-01T00:00:00.000Z");
  modifiedDate.extra = true;
  assert.throws(() => contract.canonicalEncode(modifiedDate));

  const nullPrototype = Object.create(null);
  nullPrototype["10"] = "ten";
  nullPrototype["2"] = "two";
  assert.equal(contract.canonicalEncode(nullPrototype), "{\"10\":\"ten\",\"2\":\"two\"}");
});

function temporalFixture(raw) {
  const effectiveTo = raw.effectiveTo.state === "known" ?
    {...raw.effectiveTo, value: new Date(raw.effectiveTo.value)} : raw.effectiveTo;
  return {
    effectiveFrom: new Date(raw.effectiveFrom),
    effectiveTo,
    recordedAt: new Date(raw.recordedAt),
  };
}

test("temporal intervals require the exact open-ended sentinel", () => {
  for (const raw of fixture.temporalIntervals.valid) {
    assert.doesNotThrow(() => contract.validateTemporalInterval(temporalFixture(raw)), raw.name);
  }
  for (const raw of fixture.temporalIntervals.invalid) {
    assert.throws(() => contract.validateTemporalInterval(temporalFixture(raw)), undefined, raw.name);
  }
  const open = temporalFixture(fixture.temporalIntervals.valid[1]);
  assert.equal(contract.temporalIntervalContains(open, new Date("2050-01-01T00:00:00Z")), true);
  const unknown = temporalFixture(fixture.temporalIntervals.valid[2]);
  assert.equal(contract.temporalIntervalContains(unknown, new Date("2050-01-01T00:00:00Z")), null);
});

test("release-head schema and state invariants match shared fixtures", () => {
  for (const {name, ...head} of fixture.publicationReleaseHeads.valid) {
    assert.doesNotThrow(() => contract.validatePublicationReleaseHead(head), name);
  }
  for (const {name, ...head} of fixture.publicationReleaseHeads.invalid) {
    assert.throws(() => contract.validatePublicationReleaseHead(head), undefined, name);
  }
});

test("box-score input descriptors are complete, ordered, and hash-bound", () => {
  const parts = fixture.boxScoreInputParts.validComplete;
  assert.doesNotThrow(() => contract.validateBoxScoreInputParts(parts, "complete"));
  assert.equal(contract.boxScoreInputHash(parts), fixture.boxScoreInputParts.validCompleteInputHash);
  assert.throws(() => contract.validateBoxScoreInputParts(parts.filter((part) => part.kind !== "teamOnlyInputs"), "complete"));
  assert.throws(() => contract.validateBoxScoreInputParts(parts.filter((part) => part.kind !== "periods"), "complete"));
  assert.throws(() => contract.validateBoxScoreInputParts([parts[0], {...parts[1], partId: parts[0].partId}], "complete"));
  assert.throws(() => contract.validateBoxScoreInputParts([parts[1], parts[0], ...parts.slice(2)], "complete"));
  assert.throws(() => contract.validateBoxScoreInputParts([{...parts[0], count: 0}, ...parts.slice(1)], "complete"));
  assert.throws(() => contract.validateBoxScoreInputParts([{...parts[0], count: Number.MAX_SAFE_INTEGER + 1}, ...parts.slice(1)], "complete"));
  assert.throws(() => contract.validateBoxScoreInputParts([{...parts[0], sha256: "ABC"}, ...parts.slice(1)], "complete"));
  assert.throws(() => contract.validateBoxScoreInputParts([{...parts[0], kind: "unknownKind"}, ...parts.slice(1)], "complete"));
});

test("journal semantic and request hashes exclude only pinned metadata", () => {
  const journal = fixture.journalContract;
  assert.deepEqual(Object.keys(journal.semanticInput).sort(), [...journal.semanticHashFields].sort());
  assert.deepEqual(Object.keys(journal.requestInput).sort(), [...journal.requestHashFields].sort());
  assert.equal(contract.canonicalSha256(journal.semanticInput), journal.semanticHash);
  assert.equal(contract.canonicalSha256(journal.requestInput), journal.requestHash);

  const operation = {
    ...journal.semanticInput,
    operationId: journal.requestInput.operationId,
    commandId: "command_7",
    actorAccountId: journal.requestInput.actorAccountId,
    deviceSessionId: journal.requestInput.deviceSessionId,
    writerEpoch: journal.requestInput.writerEpoch,
    localSequence: journal.requestInput.localSequence,
    previousOperationHash: journal.requestInput.previousOperationHash,
    expectedServerHead: journal.requestInput.expectedServerHead,
    semanticHash: journal.semanticHash,
    requestHash: journal.requestHash,
    clientObservedAt: new Date("2026-01-01T00:00:00.000Z"),
  };
  assert.deepEqual(contract.journalSemanticHashInput(operation), journal.semanticInput);
  assert.deepEqual(contract.journalRequestHashInput(operation), journal.requestInput);
  assert.doesNotThrow(() => contract.validateJournalOperation(operation));
  assert.throws(() => contract.validateJournalOperation({...operation, logicalPlayOrder: 43}));
  assert.equal(
    contract.canonicalSha256(contract.journalRequestHashInput({
      ...operation,
      commandId: "a_different_idempotency_key",
      clientObservedAt: new Date("2030-01-01T00:00:00.000Z"),
    })),
    journal.requestHash,
  );

  const receipt = {
    receiptId: "receipt_7",
    scope: operation.scope,
    workspaceId: operation.workspaceId,
    operationId: operation.operationId,
    commandId: operation.commandId,
    actorAccountId: operation.actorAccountId,
    commandKind: operation.operationType,
    requestHash: operation.requestHash,
    serverSequence: 7,
    acceptedJournalHead: "head_7",
    acceptedJournalHash: "b".repeat(64),
    writerEpoch: operation.writerEpoch,
    acceptedAt: new Date("2026-01-01T00:00:01.000Z"),
  };
  assert.deepEqual(Object.keys(receipt), journal.receiptRequiredFields);
  assert.doesNotThrow(() => contract.validateOperationReceipt(receipt));
  assert.doesNotThrow(() => contract.validateJournalDelivery({
    operationId: operation.operationId,
    state: "accepted",
    retryCount: 1,
    nextAttemptAt: {state: "notApplicable", value: null, reasonCode: "accepted"},
    lastErrorCode: {state: "notApplicable", value: null, reasonCode: "accepted"},
    receipt: {state: "known", value: receipt},
  }));
  assert.throws(() => contract.validateJournalDelivery({
    operationId: operation.operationId,
    state: "accepted",
    retryCount: 1,
    nextAttemptAt: {state: "notApplicable", value: null, reasonCode: "accepted"},
    lastErrorCode: {state: "notApplicable", value: null, reasonCode: "accepted"},
    receipt: {state: "unknown", value: null, reasonCode: "not_received"},
  }));
});
