const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const contract = require("../lib/domain/account_deletion_contract.js");

const fixture = JSON.parse(fs.readFileSync(
  path.join(__dirname, "../../contracts/account_deletion/v1/contract_fixtures.json"),
  "utf8",
));
const policyRegistry = JSON.parse(fs.readFileSync(
  path.join(__dirname, "../../contracts/account_deletion/v1/retention_policy_registry.json"),
  "utf8",
));
const releaseGates = JSON.parse(fs.readFileSync(
  path.join(__dirname, "../../contracts/account_deletion/v1/release_gates.json"),
  "utf8",
));

test("TypeScript deletion versions and states match shared fixtures", () => {
  assert.deepEqual(contract.accountDeletionVersions, fixture.versions);
  assert.deepEqual(contract.accountLifecycleStates, fixture.states.accountLifecycle);
  assert.deepEqual(contract.deletionJobStates, fixture.states.deletionJob);
  assert.deepEqual(contract.resumeStages, fixture.states.resumeStage);
  assert.deepEqual(contract.custodyChoices, fixture.states.custodyChoice);
  assert.deepEqual(contract.custodyOutcomes, fixture.states.custodyOutcome);
  assert.deepEqual(contract.associationCustodyStates, fixture.states.associationCustody);
  assert.deepEqual(contract.holdStates, fixture.states.hold);
  assert.deepEqual(contract.adapterApplicabilities, fixture.states.adapterApplicability);
  assert.deepEqual(contract.adapterResultStates, fixture.states.adapterResult);
  assert.deepEqual(contract.dispositionActions, fixture.states.disposition);
  assert.deepEqual(contract.providerNames, fixture.states.providerName);
  assert.deepEqual(contract.providerCheckpointStates, fixture.states.providerCheckpoint);
  assert.deepEqual(contract.deletionStatusPhases, fixture.states.deletionStatusPhase);
  assert.deepEqual(contract.idempotencyDecisions, fixture.states.idempotencyDecision);
  assert.deepEqual(contract.completionCheckpointNames, fixture.completionCheckpointNames);
});

test("lifecycle and job transition allowlists fail closed", () => {
  for (const [from, to] of fixture.transitions.accountLifecycle) {
    assert.equal(contract.canTransitionAccountLifecycle(from, to), true);
  }
  assert.equal(contract.canTransitionAccountLifecycle("deleting", "active"), false);
  assert.equal(contract.canTransitionAccountLifecycle("deleted", "active"), false);
  for (const [from, to] of fixture.transitions.deletionJob) {
    assert.equal(contract.canTransitionDeletionJob(from, to), true);
  }
  assert.equal(contract.canTransitionDeletionJob("complete", "accepted"), false);
  assert.equal(contract.canTransitionDeletionJob("verify", "inventory"), false);
});

function request(overrides = {}) {
  return {
    schemaVersion: 1,
    intentId: "intent_1",
    policyVersion: "policy_v1",
    impactVersion: "impact_v1",
    operationId: "operation_fixture_1",
    requestId: "request_fixture_1",
    statusSecretHash: fixture.statusCapability.secretHash,
    confirmation: "deleteAccount",
    custodyChoice: "ordinary",
    ...overrides,
  };
}

test("request schemas reject missing and unknown authority-affecting fields", () => {
  assert.deepEqual(contract.validatePrepareDeletionRequest({schemaVersion: 1}), {schemaVersion: 1});
  assert.throws(() => contract.validatePrepareDeletionRequest({schemaVersion: 1, uid: "victim"}));
  assert.doesNotThrow(() => contract.validateRequestDeletion(request()));
  assert.doesNotThrow(() => contract.validateRequestDeletion(request({providerRevocationRef: "apple_ref_1"})));
  assert.throws(() => contract.validateRequestDeletion(request({providerRevocationRef: null})));
  assert.throws(() => contract.validateRequestDeletion(request({targetUid: "victim"})));
  assert.throws(() => contract.validateRequestDeletion(request({schemaVersion: 2})));
  assert.throws(() => contract.validateRequestDeletion(request({confirmation: "disableAccount"})));
  const missing = request();
  delete missing.policyVersion;
  assert.throws(() => contract.validateRequestDeletion(missing));
  assert.doesNotThrow(() => contract.validateDeletionStatusRequest({
    schemaVersion: 1,
    requestId: "request_fixture_1",
    statusSecret: fixture.statusCapability.secret,
  }));
  assert.throws(() => contract.validateDeletionStatusRequest({
    schemaVersion: 1,
    requestId: "request_fixture_1",
    statusSecret: fixture.statusCapability.secret,
    uid: "victim",
  }));
});

test("status aliases and minimal tombstones reject extra identity material", () => {
  const statusAlias = {
    schemaVersion: 1,
    requestId: "request_fixture_1",
    internalJobId: "job_fixture_1",
    statusSecretHash: fixture.statusCapability.secretHash,
    createdAt: new Date("2026-01-02T03:04:05.678Z"),
    expiryPolicyDecisionId: "retention.deletion_operational_residue.v1",
  };
  assert.doesNotThrow(() => contract.validateStatusAlias(statusAlias));
  assert.throws(() => contract.validateStatusAlias({...statusAlias, uid: "uid_fixture_alpha"}));
  const tombstone = {
    schemaVersion: 1,
    generationHmac: "1".repeat(64),
    deletionEpoch: 2,
    policyVersion: "policy_v1",
    suppressionKeyVersion: "key_v1",
    acceptedAt: new Date("2026-01-02T03:04:05.678Z"),
    completedAt: null,
    minimumReplayCutoff: new Date("2026-01-02T03:04:05.678Z"),
  };
  assert.doesNotThrow(() => contract.validateMinimalTombstone(tombstone));
  assert.throws(() => contract.validateMinimalTombstone({...tombstone, email: "person@example.com"}));
  assert.deepEqual(
    Object.keys(statusAlias).sort(),
    [...fixture.schemas.statusAlias.required].sort(),
  );
  assert.deepEqual(
    Object.keys(tombstone).sort(),
    [...fixture.schemas.minimalTombstone.required].sort(),
  );
});

test("generation, semantic fingerprint, and envelope match cross-runtime goldens", () => {
  const generation = {
    ...fixture.generation.input,
    authCreatedAt: new Date(fixture.generation.input.authCreatedAt),
  };
  assert.deepEqual({
    accountIdUtf16LeBase64Url: contract.firebaseUidUtf16LeBase64Url(generation.accountId),
    authCreatedAt: generation.authCreatedAt.toISOString(),
    authNamespace: generation.authNamespace,
  }, fixture.generation.canonicalInput);
  assert.equal(contract.accountGenerationHash(generation), fixture.generation.generationHash);
  const accepted = request({intentId: "intent_1", providerRevocationRef: "apple_ref_1"});
  const semanticInput = contract.semanticFingerprintInput(accepted, generation);
  assert.deepEqual(Object.keys(semanticInput).sort(), [...fixture.fingerprints.semanticFields].sort());
  assert.deepEqual(semanticInput, fixture.fingerprints.semanticInput);
  const semantic = contract.semanticFingerprint(accepted, generation);
  assert.equal(semantic, fixture.fingerprints.semanticHash);
  assert.equal(contract.operationEnvelopeFingerprint(accepted, semantic), fixture.fingerprints.envelopeHash);
  assert.deepEqual(
    Object.keys(contract.operationEnvelopeInput(accepted, semantic)).sort(),
    [...fixture.fingerprints.envelopeFields].sort(),
  );
  assert.equal(contract.semanticFingerprint(request({intentId: "intent_2"}), generation), semantic);
  assert.equal(contract.semanticFingerprint(request({providerRevocationRef: "apple_ref_2"}), generation), semantic);
  assert.notEqual(contract.semanticFingerprint(request({custodyChoice: "suspendToCustody"}), generation), semantic);
});

test("generation identity preserves the exact Firebase UID byte sequence", () => {
  for (const accountId of fixture.generationIdentityCases.acceptedFirebaseUids) {
    assert.doesNotThrow(() => contract.accountGenerationHash({
      accountId,
      authCreatedAt: new Date(fixture.generation.input.authCreatedAt),
      authNamespace: fixture.generation.input.authNamespace,
    }));
  }
  const [composed, decomposed] = fixture.generationIdentityCases.normalizationDistinct;
  const generation = {
    authCreatedAt: new Date(fixture.generation.input.authCreatedAt),
    authNamespace: fixture.generation.input.authNamespace,
  };
  assert.notEqual(
    contract.accountGenerationHash({...generation, accountId: composed}),
    contract.accountGenerationHash({...generation, accountId: decomposed}),
  );
  const losslessEdgeIds = ["\ud800", "\ud801", "\ufffd"];
  assert.equal(new Set(losslessEdgeIds.map((accountId) =>
    contract.accountGenerationHash({...generation, accountId}))).size, losslessEdgeIds.length);
  assert.throws(() => contract.accountGenerationHash({...generation, accountId: ""}));
  assert.throws(() => contract.accountGenerationHash({...generation, accountId: "x".repeat(129)}));
});

test("status capability is 256-bit, purpose-limited, hash-bound, and non-enumerating", () => {
  assert.equal(contract.decodeStatusSecret(fixture.statusCapability.secret).length, 32);
  assert.equal(contract.statusSecretHash(fixture.statusCapability.secret), fixture.statusCapability.secretHash);
  assert.equal(contract.statusSecretMatches(fixture.statusCapability.secret, fixture.statusCapability.secretHash), true);
  assert.equal(contract.statusSecretMatches(fixture.statusCapability.secret, "0".repeat(64)), false);
  assert.throws(() => contract.decodeStatusSecret("short"));
  assert.deepEqual(fixture.statusCapability.allowedCapability, ["readOwnCoarseDeletionStatus"]);
  assert.ok(fixture.statusCapability.forbiddenCapabilities.includes("grantAuthority"));
  assert.ok(fixture.statusCapability.forbiddenCapabilities.includes("restoreAccount"));
  assert.ok(fixture.statusCapability.serverNeverStores.includes("statusSecret"));
});

test("idempotency distinguishes exact retry, conflict, and two-device status recovery", () => {
  for (const testCase of fixture.idempotencyCases) {
    assert.equal(contract.evaluateIdempotency(testCase), testCase.expected, testCase.name);
  }
  const winner = fixture.idempotencyCases.find((entry) => entry.name === "secondDeviceBeforeDisable");
  const late = fixture.idempotencyCases.find((entry) => entry.name === "secondDeviceAfterDisable");
  assert.equal(winner.expected, "attachStatusAlias");
  assert.equal(late.expected, "denyFenced");
});

test("deleting or stale accounts never regain authority through a granting receipt", () => {
  for (const testCase of fixture.authorityFenceCases) {
    const actual = contract.canReplayGrant(testCase);
    assert.equal(actual, testCase.grantReceiptReplay, testCase.name);
  }
});

test("lifecycle serialization rejects inconsistent terminal fields", () => {
  const generationHash = fixture.generation.generationHash;
  assert.doesNotThrow(() => contract.validateAccountLifecycle({
    schemaVersion: 1,
    state: "active",
    epoch: 0,
    generationHash,
    internalJobId: null,
    acceptedAt: null,
    completedAt: null,
  }));
  assert.doesNotThrow(() => contract.validateAccountLifecycle({
    schemaVersion: 1,
    state: "deleted",
    epoch: 2,
    generationHash,
    internalJobId: "job_1",
    acceptedAt: new Date("2026-01-01T00:00:00Z"),
    completedAt: new Date("2026-01-02T00:00:00Z"),
  }));
  assert.throws(() => contract.validateAccountLifecycle({
    schemaVersion: 1,
    state: "active",
    epoch: 1,
    generationHash,
    internalJobId: "job_1",
    acceptedAt: null,
    completedAt: null,
  }));
  assert.throws(() => contract.validateAccountLifecycle({
    schemaVersion: 1,
    state: "active",
    epoch: Number.MAX_SAFE_INTEGER + 1,
    generationHash,
    internalJobId: null,
    acceptedAt: null,
    completedAt: null,
  }));
});

test("retry and attention jobs require an exact resume stage", () => {
  const base = {
    schemaVersion: 1,
    internalJobId: "job_1",
    generationHash: fixture.generation.generationHash,
    state: "inventory",
    resumeStage: null,
    policyVersion: "policy_v1",
    inventoryVersion: fixture.versions.inventoryVersion,
    authAbsent: false,
    dataDispositionVerified: false,
    publicPrivacyVerified: false,
    custodyRecorded: false,
    providerDispositionRecorded: false,
    restoreSuppressionDurable: false,
    safeErrorCode: null,
  };
  assert.doesNotThrow(() => contract.validateDeletionJob(base));
  assert.doesNotThrow(() => contract.validateDeletionJob({...base, state: "retryWait", resumeStage: "inventory"}));
  assert.throws(() => contract.validateDeletionJob({...base, state: "retryWait", resumeStage: null}));
  assert.throws(() => contract.validateDeletionJob({...base, state: "inventory", resumeStage: "inventory"}));
  assert.throws(() => contract.validateDeletionJob({...base, safeErrorCode: "INTERNAL_STACK_TRACE"}));
  assert.throws(() => contract.validateDeletionJob({...base, state: "complete"}));
  assert.doesNotThrow(() => contract.validateDeletionJob({
    ...base,
    state: "complete",
    authAbsent: true,
    dataDispositionVerified: true,
    publicPrivacyVerified: true,
    custodyRecorded: true,
    providerDispositionRecorded: true,
    restoreSuppressionDurable: true,
  }));
  assert.deepEqual(Object.keys(base).sort(), [...fixture.schemas.deletionJob.required].sort());
});

function completeInput(testCase) {
  const results = fixture.adapterIds.map((adapterId) => ({
    adapterId,
    applicability: "applicable",
    state: "complete",
    disposition: adapterId === "v2_certified_evidence" ? "restrictedRetention" : "erase",
    policyDecisionState: "approved",
    policyDecisionId: `retention.${adapterId}`,
    policyVersion: "policy_v1",
    holdState: adapterId === "v2_certified_evidence" ? "activeApproved" : "none",
    evidenceCode: "fixture_verified",
    evidenceRef: "evidence_fixture",
  }));
  if (!testCase.allAdaptersComplete) results[0] = {...results[0], state: "blocked"};
  return {
    authAbsent: testCase.authAbsent,
    checkpoints: {
      dataDispositionVerified: testCase.allCheckpoints,
      publicPrivacyVerified: testCase.allCheckpoints,
      custodyRecorded: testCase.allCheckpoints,
      providerDispositionRecorded: testCase.allCheckpoints,
      restoreSuppressionDurable: testCase.allCheckpoints,
    },
    requiredAdapterIds: [...fixture.adapterIds],
    adapterResults: results,
    providerCheckpoints: [
      {provider: "firebaseAuth", state: "complete", evidenceCode: "absent_verified", checkedAt: new Date()},
      {provider: "appleCredential", state: testCase.allProvidersTerminal ? (testCase.appleOutcome || "notApplicable") : "retryRequired", evidenceCode: "fixture", checkedAt: new Date()},
    ],
    unknownRequiredState: testCase.unknownRequiredState,
  };
}

test("completion requires Auth absence and every adapter, privacy, custody, provider, and restore checkpoint", () => {
  for (const testCase of fixture.completionCases) {
    assert.equal(contract.isDeletionComplete(completeInput(testCase)), testCase.expected, testCase.name);
  }
  const duplicate = completeInput(fixture.completionCases[0]);
  duplicate.adapterResults.push(duplicate.adapterResults[0]);
  assert.equal(contract.isDeletionComplete(duplicate), false);
  const unknownHold = completeInput(fixture.completionCases[0]);
  unknownHold.adapterResults[1] = {...unknownHold.adapterResults[1], holdState: "unknown"};
  assert.equal(contract.isDeletionComplete(unknownHold), false);
  const missingApple = completeInput(fixture.completionCases[0]);
  missingApple.providerCheckpoints.pop();
  assert.equal(contract.isDeletionComplete(missingApple), false);
  const duplicateFirebase = completeInput(fixture.completionCases[0]);
  duplicateFirebase.providerCheckpoints[1] = {...duplicateFirebase.providerCheckpoints[0]};
  assert.equal(contract.isDeletionComplete(duplicateFirebase), false);
  const falseFirebaseFallback = completeInput(fixture.completionCases[0]);
  falseFirebaseFallback.providerCheckpoints[0] = {
    ...falseFirebaseFallback.providerCheckpoints[0],
    state: "manualActionGuidance",
  };
  assert.equal(contract.isDeletionComplete(falseFirebaseFallback), false);
  const emptyInventory = completeInput(fixture.completionCases[0]);
  emptyInventory.requiredAdapterIds = [];
  emptyInventory.adapterResults = [];
  assert.equal(contract.isDeletionComplete(emptyInventory), false);
  const emptyCheckpoints = completeInput(fixture.completionCases[0]);
  emptyCheckpoints.checkpoints = {};
  assert.equal(contract.isDeletionComplete(emptyCheckpoints), false);
  const extraUnsupported = completeInput(fixture.completionCases[0]);
  extraUnsupported.requiredAdapterIds.push("unsupported_extra");
  extraUnsupported.adapterResults.push({...extraUnsupported.adapterResults[0], adapterId: "unsupported_extra"});
  assert.equal(contract.isDeletionComplete(extraUnsupported), false);
  const missingEvidence = completeInput(fixture.completionCases[0]);
  missingEvidence.adapterResults[0] = {...missingEvidence.adapterResults[0], evidenceRef: ""};
  assert.equal(contract.isDeletionComplete(missingEvidence), false);
  const releasePendingNotApplicable = completeInput(fixture.completionCases[0]);
  releasePendingNotApplicable.adapterResults[0] = {
    ...releasePendingNotApplicable.adapterResults[0],
    applicability: "notApplicable",
    state: "notApplicable",
    disposition: "notApplicable",
    holdState: "releasePending",
  };
  assert.equal(contract.isDeletionComplete(releasePendingNotApplicable), false);
  const unknownDisposition = completeInput(fixture.completionCases[0]);
  unknownDisposition.adapterResults[0] = {...unknownDisposition.adapterResults[0], disposition: "invented"};
  assert.equal(contract.isDeletionComplete(unknownDisposition), false);
  const providerMissingEvidence = completeInput(fixture.completionCases[0]);
  providerMissingEvidence.providerCheckpoints[0] = {...providerMissingEvidence.providerCheckpoints[0], evidenceCode: ""};
  assert.equal(contract.isDeletionComplete(providerMissingEvidence), false);
  const stringFalseAuth = completeInput(fixture.completionCases[0]);
  stringFalseAuth.authAbsent = "false";
  assert.equal(contract.isDeletionComplete(stringFalseAuth), false);
  const missingUnknownState = completeInput(fixture.completionCases[0]);
  delete missingUnknownState.unknownRequiredState;
  assert.equal(contract.isDeletionComplete(missingUnknownState), false);
  assert.deepEqual(
    Object.keys(completeInput(fixture.completionCases[0]).adapterResults[0]).sort(),
    [...fixture.schemas.adapterResult.required].sort(),
  );
});

test("every disposition row has one adapter and a closed policy decision", () => {
  assert.deepEqual(contract.accountDeletionAdapterIds, fixture.adapterIds);
  assert.equal(new Set(fixture.adapterIds).size, fixture.adapterIds.length);
  assert.equal(policyRegistry.activationApproved, false);
  assert.equal(policyRegistry.policyVersion, null);
  assert.equal(policyRegistry.decisions.length, fixture.adapterIds.length);
  const decisions = new Map(policyRegistry.decisions.map((decision) => [decision.adapterId, decision]));
  for (const adapterId of fixture.adapterIds) {
    assert.ok(decisions.has(adapterId), adapterId);
  }
  for (const field of policyRegistry.requiredDecisionFields) {
    assert.equal(policyRegistry.decisionTemplate[field], null, field);
  }
  assert.equal(policyRegistry.decisionTemplate.approved, false);
  assert.equal(policyRegistry.decisionTemplate.decisionState, "pendingAuthoritativeDecision");
});

test("all G1-G11 release gates remain closed with owners and evidence absent", () => {
  assert.equal(releaseGates.activationAllowed, false);
  assert.deepEqual(releaseGates.gates.map((gate) => gate.id), [
    "G1", "G2", "G3", "G4", "G5", "G6", "G7", "G8", "G9", "G10", "G11",
  ]);
  for (const gate of releaseGates.gates) {
    assert.equal(gate.passed, false, gate.id);
    assert.equal(gate.owner, null, gate.id);
    assert.deepEqual(gate.evidenceRefs, [], gate.id);
    assert.ok(gate.status.startsWith("closed"), gate.id);
    assert.ok(gate.requiredEvidence.length > 0, gate.id);
  }
});

test("stable public errors match the shared retry and idempotency policy", () => {
  assert.deepEqual(contract.accountDeletionErrorPolicies, fixture.errors);
  assert.deepEqual(contract.internalDeletionErrorCodes, fixture.internalErrors);
});

test("Auth-only and legacy identities can self-delete without gaining membership", () => {
  for (const testCase of fixture.compatibilityCases) {
    const eligible = contract.selfDeletionEligible({
      authenticatedSameGeneration: testCase.hasAuth,
      hasProfile: testCase.hasProfile,
      hasMembership: testCase.hasMembership,
      legacyRole: testCase.legacyRole,
    });
    assert.equal(eligible, testCase.selfDeletionEligible, testCase.name);
    assert.equal(testCase.createsMembership, false, testCase.name);
  }
});

test("custody and stat privacy fixtures preserve account, tenant, and sporting boundaries", () => {
  for (const testCase of fixture.custodyCases) {
    assert.equal(contract.resolveCustodyOutcome(testCase), testCase.expected, testCase.name);
  }
  const facts = fixture.statPrivacyCases.find((entry) => entry.name === "deleteActorBinding");
  assert.equal(facts.preserveSportingFacts, true);
  assert.equal(facts.preserveRevisionBytes, true);
  assert.equal(facts.preserveCertifiedHash, true);
  assert.equal(facts.removeAccountBinding, true);
  const legacy = fixture.statPrivacyCases.find((entry) => entry.name === "legacyNameBearingKey");
  assert.equal(legacy.nameMatchAllowed, false);
  assert.equal(legacy.requiresRebuildSuppression, true);
  const minor = fixture.statPrivacyCases.find((entry) => entry.name === "unknownMinor");
  assert.equal(minor.defaultsToAdult, false);
  assert.equal(minor.publicNameAllowed, false);
  assert.equal(policyRegistry.policyTruths.pseudonymizationIsAnonymity, false);
  assert.equal(policyRegistry.policyTruths.accountDeletionDeletesTenantOrTeam, false);
});
