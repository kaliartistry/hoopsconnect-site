import {
  AccountDeletionJobContract,
  AccountDeletionStatusAliasContract,
  RequestDeletion,
  accountDeletionVersions,
  accountGenerationHash,
  operationEnvelopeFingerprint,
  semanticFingerprint,
  statusSecretMatches,
  validateRequestDeletion,
} from "../domain/account_deletion_contract";
import {
  AccountLifecycleAuthorityV2,
  AuthIncarnationScopeV2,
  MembershipAuthorityV2,
  ValidatedActiveAuthorityV2,
  evaluateAccountAuthorizationV2,
  parseMembershipAuthorityV2,
} from "../domain/auth_incarnation_v2";
import {
  OwnerDepartureReceiptV2,
  applyOwnerDepartureInTransactionV2,
  associationOwnershipControlPathV2,
  parseAssociationOwnershipControlV2,
} from "../domain/association_ownership_ad03_v2";
import {canonicalSha256} from "../domain/official_stats_contract";
import {
  ACCOUNT_DELETION_AD04_FRESH_AUTH_MAX_AGE_SEC_V1,
  ACCOUNT_DELETION_AD04_INTENT_TTL_SEC_V1,
  ACCOUNT_DELETION_AD04_MAX_STATUS_ALIASES_V1,
  CandidateDeletionIntentV1,
  CandidateDeletionJobBindingV1,
  CandidateDeletionOperationReceiptV1,
  CandidateDeletionProviderBindingV1,
  CandidateDeletionRepositoryV1,
  CandidateDeletionTransactionV1,
  CandidateDeletionStatusV1,
  CandidateRevocationMaterialV1,
  DeletionProviderRelationshipV1,
  OwnerDepartureRequestRecordV1,
  ad04CounterV1,
  ad04ExactKeysV1,
  ad04FailV1,
  ad04HashV1,
  ad04OpaqueIdV1,
  ad04RecordV1,
  ad04ScopeV1,
  authNamespaceForScopeV1,
  candidateAccountLifecycleAuthorityPathV1,
  candidateMembershipAuthorityPathV1,
  deletionAdapterResultPathV1,
  deletionEffectReceiptPathV1,
  deletionIntentFingerprintV1,
  deletionIntentPathV1,
  deletionInternalJobIdV1,
  deletionJobBindingPathV1,
  deletionJobPathV1,
  deletionOperationReceiptIdV1,
  deletionOperationReceiptPathV1,
  deletionProviderBindingPathV1,
  deletionProviderCheckpointPathV1,
  deletionRevocationMaterialPathV1,
  deletionStatusAliasPathV1,
  deletionStatusControlPathV1,
  deletionTaskEffectIdV1,
  deletionTaskEffectFingerprintV1,
  deletionTaskPathV1,
  initialDeletionTasksV1,
  parseCandidateDeletionIntentV1,
  parseCandidateAccountLifecycleAuthorityV2ForDeletionV1,
  parseCandidateDeletionJobBindingV1,
  parseCandidateDeletionJobV1,
  parseCandidateDeletionProviderBindingV1,
  parseCandidateDeletionStatusControlV1,
  parseCandidateDeletionTaskV1,
  parseCandidateEffectReceiptV1,
  parseCandidateOperationReceiptV1,
  parseCandidateProviderCheckpointV1,
  parseCandidateRevocationMaterialV1,
  parseCandidateStatusAliasV1,
  sameAd04ScopeV1,
} from "./ad04_records";

export interface CandidateVerifiedIdentitySnapshotV1 extends AuthIncarnationScopeV2 {
  schemaVersion: 1;
  authCreatedAtIsoV1: string;
  accountGenerationV2: string;
  accountLifecycleEpochV2: number;
  authTimeSecV1: number;
  issuerV1: string;
  audienceV1: string;
  providerIdsV1: readonly string[];
  appleProviderSubjectHashV1: string | null;
  revocationCheckedV1: true;
  appAttestationVerifiedV1: true;
}

export interface CandidateDeletionIdentityVerifierV1 {
  verifyCurrentAccountV1(presentedCredential: unknown): Promise<unknown>;
}

export interface VerifiedDeletionPrincipalV1 extends AuthIncarnationScopeV2 {
  readonly schemaVersion: 1;
  readonly authCreatedAtV1: Date;
  readonly accountGenerationV2: string;
  readonly accountLifecycleEpochV2: number;
  readonly authTimeSecV1: number;
  readonly providerRelationshipV1: DeletionProviderRelationshipV1;
  readonly appleProviderSubjectHashV1: string | null;
  readonly verificationNonceV1: object;
}

export interface CandidateDeletionImpactV1 {
  schemaVersion: 1;
  policyVersion: string;
  impactVersion: string;
  custodyChoice: "ordinary" | "transferThenDelete" | "suspendToCustody";
  associationId: string | null;
  ownerDepartureRequestV2: OwnerDepartureRequestRecordV1 | null;
  candidateTestCustodyPolicyIdV2: string | null;
}

export interface AcceptedCandidateDeletionV1 {
  requestId: string;
  internalJobId: string;
  acceptedAt: string;
  state: "deleting";
  completionTargetText: string;
  nextPollAfterSeconds: number;
  bindingKind: "winningOperation" | "sameGenerationConvergence";
}

const verifiedPrincipalsV1 = new WeakSet<object>();
const providerIdPattern = /^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/;
const isoPattern = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;
const firebaseIssuerPattern =
  /^https:\/\/securetoken\.google\.com\/[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/;

function validIso(value: unknown): string {
  if (typeof value !== "string" || !isoPattern.test(value) ||
      !Number.isFinite(new Date(value).getTime()) || new Date(value).toISOString() !== value) {
    ad04FailV1("AD04_AUTHORITY_DENIED");
  }
  return value;
}

function providerIds(value: unknown): readonly string[] {
  if (!Array.isArray(value) || value.length === 0 || value.length > 8 ||
      !value.every((entry) => typeof entry === "string" && providerIdPattern.test(entry)) ||
      new Set(value).size !== value.length) ad04FailV1("AD04_AUTHORITY_DENIED");
  return Object.freeze([...value].sort());
}

function firebaseIssuerV1(value: unknown): string {
  if (typeof value !== "string" || !firebaseIssuerPattern.test(value)) {
    ad04FailV1("AD04_AUTHORITY_DENIED");
  }
  return value;
}

function parseVerifiedIdentitySnapshotV1(value: unknown): CandidateVerifiedIdentitySnapshotV1 {
  const data = ad04RecordV1(value);
  const keys = [
    "schemaVersion", "authProjectIdV2", "authTenantIdV2", "authUidV2",
    "authCreatedAtIsoV1", "accountGenerationV2", "accountLifecycleEpochV2",
    "authTimeSecV1", "issuerV1", "audienceV1", "providerIdsV1",
    "appleProviderSubjectHashV1", "revocationCheckedV1",
    "appAttestationVerifiedV1",
  ];
  if (data === null || !ad04ExactKeysV1(data, keys) || data.schemaVersion !== 1 ||
      data.revocationCheckedV1 !== true || data.appAttestationVerifiedV1 !== true) {
    ad04FailV1("AD04_AUTHORITY_DENIED");
  }
  const scope = ad04ScopeV1({
    authProjectIdV2: data.authProjectIdV2,
    authTenantIdV2: data.authTenantIdV2,
    authUidV2: data.authUidV2,
  });
  return Object.freeze({
    schemaVersion: 1,
    ...scope,
    authCreatedAtIsoV1: validIso(data.authCreatedAtIsoV1),
    accountGenerationV2: ad04HashV1(data.accountGenerationV2),
    accountLifecycleEpochV2: ad04CounterV1(data.accountLifecycleEpochV2),
    authTimeSecV1: ad04CounterV1(data.authTimeSecV1),
    issuerV1: firebaseIssuerV1(data.issuerV1),
    audienceV1: ad04OpaqueIdV1(data.audienceV1),
    providerIdsV1: providerIds(data.providerIdsV1),
    appleProviderSubjectHashV1: data.appleProviderSubjectHashV1 === null
      ? null : ad04HashV1(data.appleProviderSubjectHashV1),
    revocationCheckedV1: true,
    appAttestationVerifiedV1: true,
  });
}

export async function establishVerifiedDeletionPrincipalV1(input: {
  verifier: CandidateDeletionIdentityVerifierV1;
  presentedCredential: unknown;
  configuredProjectId: string;
  nowSecV1: number;
}): Promise<VerifiedDeletionPrincipalV1> {
  const configuredProjectId = ad04OpaqueIdV1(input.configuredProjectId);
  const nowSecV1 = ad04CounterV1(input.nowSecV1);
  const snapshot = parseVerifiedIdentitySnapshotV1(
    await input.verifier.verifyCurrentAccountV1(input.presentedCredential),
  );
  const authCreatedAtV1 = new Date(snapshot.authCreatedAtIsoV1);
  const expectedGeneration = accountGenerationHash({
    authNamespace: authNamespaceForScopeV1(snapshot),
    accountId: snapshot.authUidV2,
    authCreatedAt: authCreatedAtV1,
  });
  if (snapshot.authProjectIdV2 !== configuredProjectId ||
      snapshot.audienceV1 !== configuredProjectId ||
      snapshot.issuerV1 !== `https://securetoken.google.com/${configuredProjectId}` ||
      snapshot.authTimeSecV1 > nowSecV1 ||
      nowSecV1 - snapshot.authTimeSecV1 >
        ACCOUNT_DELETION_AD04_FRESH_AUTH_MAX_AGE_SEC_V1 ||
      snapshot.accountGenerationV2 !== expectedGeneration ||
      (snapshot.providerIdsV1.includes("apple.com") &&
       snapshot.appleProviderSubjectHashV1 === null) ||
      (!snapshot.providerIdsV1.includes("apple.com") &&
       snapshot.appleProviderSubjectHashV1 !== null)) {
    ad04FailV1("AD04_AUTHORITY_DENIED");
  }
  const principal: VerifiedDeletionPrincipalV1 = Object.freeze({
    schemaVersion: 1,
    authProjectIdV2: snapshot.authProjectIdV2,
    authTenantIdV2: snapshot.authTenantIdV2,
    authUidV2: snapshot.authUidV2,
    authCreatedAtV1,
    accountGenerationV2: snapshot.accountGenerationV2,
    accountLifecycleEpochV2: snapshot.accountLifecycleEpochV2,
    authTimeSecV1: snapshot.authTimeSecV1,
    providerRelationshipV1: snapshot.providerIdsV1.includes("apple.com")
      ? "apple" : "nonApple",
    appleProviderSubjectHashV1: snapshot.appleProviderSubjectHashV1,
    verificationNonceV1: {},
  });
  verifiedPrincipalsV1.add(principal);
  return principal;
}

function assertVerifiedPrincipalV1(principal: VerifiedDeletionPrincipalV1): void {
  if (!verifiedPrincipalsV1.has(principal)) ad04FailV1("AD04_AUTHORITY_DENIED");
}

function parseImpactV1(value: unknown): CandidateDeletionImpactV1 {
  const data = ad04RecordV1(value);
  const keys = [
    "schemaVersion", "policyVersion", "impactVersion", "custodyChoice",
    "associationId", "ownerDepartureRequestV2", "candidateTestCustodyPolicyIdV2",
  ];
  if (data === null || !ad04ExactKeysV1(data, keys) || data.schemaVersion !== 1 ||
      !["ordinary", "transferThenDelete", "suspendToCustody"].includes(
        data.custodyChoice as string,
      )) ad04FailV1("AD04_INVALID_REQUEST");
  const associationId = data.associationId === null
    ? null : ad04OpaqueIdV1(data.associationId);
  const ownerRequest = parseOwnerDepartureForImpactV1(data.ownerDepartureRequestV2);
  if ((associationId === null) !== (ownerRequest === null) ||
      (ownerRequest !== null && (ownerRequest.associationId !== associationId ||
        ownerRequest.custodyChoiceV2 !== data.custodyChoice))) {
    ad04FailV1("AD04_INVALID_REQUEST");
  }
  return Object.freeze({
    schemaVersion: 1,
    policyVersion: ad04OpaqueIdV1(data.policyVersion),
    impactVersion: ad04OpaqueIdV1(data.impactVersion),
    custodyChoice: data.custodyChoice as CandidateDeletionImpactV1["custodyChoice"],
    associationId,
    ownerDepartureRequestV2: ownerRequest,
    candidateTestCustodyPolicyIdV2: data.candidateTestCustodyPolicyIdV2 === null
      ? null : ad04OpaqueIdV1(data.candidateTestCustodyPolicyIdV2),
  });
}

function parseOwnerDepartureForImpactV1(value: unknown): OwnerDepartureRequestRecordV1 | null {
  if (value === null) return null;
  const data = ad04RecordV1(value);
  const keys = [
    "associationOwnershipSchemaVersionV2", "associationId", "departureOperationIdV2",
    "expectedControlVersionV2", "custodyChoiceV2", "transferIntentIdV2",
    "custodyCaseIdV2",
  ];
  if (data === null || !ad04ExactKeysV1(data, keys) ||
      data.associationOwnershipSchemaVersionV2 !== 2 ||
      !["ordinary", "transferThenDelete", "suspendToCustody"].includes(
        data.custodyChoiceV2 as string,
      )) ad04FailV1("AD04_INVALID_REQUEST");
  const result: OwnerDepartureRequestRecordV1 = Object.freeze({
    associationOwnershipSchemaVersionV2: 2,
    associationId: ad04OpaqueIdV1(data.associationId),
    departureOperationIdV2: ad04OpaqueIdV1(data.departureOperationIdV2),
    expectedControlVersionV2: ad04CounterV1(data.expectedControlVersionV2),
    custodyChoiceV2: data.custodyChoiceV2 as OwnerDepartureRequestRecordV1["custodyChoiceV2"],
    transferIntentIdV2: data.transferIntentIdV2 === null
      ? null : ad04OpaqueIdV1(data.transferIntentIdV2),
    custodyCaseIdV2: data.custodyCaseIdV2 === null
      ? null : ad04OpaqueIdV1(data.custodyCaseIdV2),
  });
  if ((result.custodyChoiceV2 === "ordinary" &&
       (result.transferIntentIdV2 !== null || result.custodyCaseIdV2 !== null)) ||
      (result.custodyChoiceV2 === "transferThenDelete" &&
       (result.transferIntentIdV2 === null || result.custodyCaseIdV2 !== null)) ||
      (result.custodyChoiceV2 === "suspendToCustody" &&
       result.custodyCaseIdV2 === null)) ad04FailV1("AD04_INVALID_REQUEST");
  return result;
}

function parseLifecycleOrNull(value: unknown): AccountLifecycleAuthorityV2 | null {
  if (value === null) return null;
  try {
    return parseCandidateAccountLifecycleAuthorityV2ForDeletionV1(value);
  } catch {
    ad04FailV1("AD04_AUTHORITY_DENIED");
  }
}

function parseMembershipOrNull(value: unknown): MembershipAuthorityV2 | null {
  if (value === null) return null;
  try {
    return parseMembershipAuthorityV2(value);
  } catch {
    return null;
  }
}

function principalGenerationInput(principal: VerifiedDeletionPrincipalV1) {
  return {
    authNamespace: authNamespaceForScopeV1(principal),
    accountId: principal.authUidV2,
    authCreatedAt: principal.authCreatedAtV1,
  };
}

export async function prepareCandidateAccountDeletionV1(input: {
  repository: CandidateDeletionRepositoryV1;
  principal: VerifiedDeletionPrincipalV1;
  request: unknown;
  impact: unknown;
  intentId: string;
  nowSecV1: number;
}): Promise<CandidateDeletionIntentV1> {
  assertVerifiedPrincipalV1(input.principal);
  const request = input.request;
  const requestData = ad04RecordV1(request);
  if (requestData === null || !ad04ExactKeysV1(requestData, ["schemaVersion"]) ||
      requestData.schemaVersion !== 1) ad04FailV1("AD04_INVALID_REQUEST");
  const impact = parseImpactV1(input.impact);
  const intentId = ad04OpaqueIdV1(input.intentId);
  const nowSecV1 = ad04CounterV1(input.nowSecV1);
  if (input.principal.authTimeSecV1 > nowSecV1 ||
      nowSecV1 - input.principal.authTimeSecV1 >
        ACCOUNT_DELETION_AD04_FRESH_AUTH_MAX_AGE_SEC_V1) {
    ad04FailV1("AD04_REAUTH_REQUIRED");
  }
  const withoutFingerprint = {
    schemaVersion: 1 as const,
    intentId,
    authProjectIdV2: input.principal.authProjectIdV2,
    authTenantIdV2: input.principal.authTenantIdV2,
    authUidV2: input.principal.authUidV2,
    generationHash: input.principal.accountGenerationV2,
    expectedLifecycleEpochV2: input.principal.accountLifecycleEpochV2,
    policyVersion: impact.policyVersion,
    impactVersion: impact.impactVersion,
    custodyChoice: impact.custodyChoice,
    associationId: impact.associationId,
    ownerDepartureRequestV2: impact.ownerDepartureRequestV2,
    candidateTestCustodyPolicyIdV2: impact.candidateTestCustodyPolicyIdV2,
    providerRelationshipV1: input.principal.providerRelationshipV1,
    preparedAtSecV1: nowSecV1,
    expiresAtSecV1: nowSecV1 + ACCOUNT_DELETION_AD04_INTENT_TTL_SEC_V1,
  };
  const intent = parseCandidateDeletionIntentV1({
    ...withoutFingerprint,
    intentFingerprintV1: deletionIntentFingerprintV1(withoutFingerprint),
  });
  return input.repository.runTransaction(async (transaction) => {
    const [existingRaw, lifecycleRaw] = await Promise.all([
      transaction.read(deletionIntentPathV1(intentId)),
      transaction.read(candidateAccountLifecycleAuthorityPathV1(input.principal)),
    ]);
    if (existingRaw !== null) {
      const existing = parseCandidateDeletionIntentV1(existingRaw);
      if (existing.intentFingerprintV1 !== intent.intentFingerprintV1) {
        ad04FailV1("AD04_OPERATION_CONFLICT");
      }
      return existing;
    }
    const lifecycle = parseLifecycleOrNull(lifecycleRaw);
    if (lifecycle !== null && (!sameAd04ScopeV1(lifecycle, input.principal) ||
        lifecycle.accountGenerationV2 !== input.principal.accountGenerationV2 ||
        lifecycle.accountLifecycleEpochV2 !== input.principal.accountLifecycleEpochV2 ||
        lifecycle.lifecycleStateV2 !== "active" ||
        input.principal.authTimeSecV1 <= lifecycle.reauthAfterSecV2)) {
      ad04FailV1("AD04_AUTHORITY_DENIED");
    }
    transaction.write(deletionIntentPathV1(intentId), intent as unknown as
      Readonly<Record<string, unknown>>);
    return intent;
  });
}

function acceptedResultV1(input: {
  requestId: string;
  internalJobId: string;
  acceptedAtSecV1: number;
  bindingKind: "winningOperation" | "sameGenerationConvergence";
}): AcceptedCandidateDeletionV1 {
  return Object.freeze({
    requestId: input.requestId,
    internalJobId: input.internalJobId,
    acceptedAt: new Date(input.acceptedAtSecV1 * 1000).toISOString(),
    state: "deleting",
    completionTargetText: "Account removal is processing; cleanup completion is separately verified.",
    nextPollAfterSeconds: 5,
    bindingKind: input.bindingKind,
  });
}

function receiptMatchesV1(input: {
  receipt: CandidateDeletionOperationReceiptV1;
  request: RequestDeletion;
  scope: AuthIncarnationScopeV2;
  generationHash: string;
  semanticHash: string;
  envelopeHash: string;
  internalJobId: string;
  acceptedLifecycleEpochV2: number;
}): boolean {
  const receipt = input.receipt;
  return receipt.receiptIdV1 === deletionOperationReceiptIdV1({
    scope: input.scope,
    generationHash: input.generationHash,
    operationId: input.request.operationId,
  }) && sameAd04ScopeV1(receipt, input.scope) &&
    receipt.generationHash === input.generationHash &&
    receipt.acceptedLifecycleEpochV2 === input.acceptedLifecycleEpochV2 &&
    receipt.operationId === input.request.operationId &&
    receipt.requestId === input.request.requestId &&
    receipt.internalJobId === input.internalJobId &&
    receipt.submittedSemanticFingerprint === input.semanticHash &&
    receipt.submittedEnvelopeFingerprint === input.envelopeHash;
}

function aliasMatchesRequestV1(input: {
  alias: AccountDeletionStatusAliasContract;
  request: RequestDeletion;
  internalJobId: string;
  generationHash: string;
  acceptedSemanticFingerprint: string;
  bindingKind: "winningOperation" | "sameGenerationConvergence";
}): boolean {
  return input.alias.requestId === input.request.requestId &&
    input.alias.internalJobId === input.internalJobId &&
    input.alias.generationHash === input.generationHash &&
    input.alias.acceptedSemanticFingerprint === input.acceptedSemanticFingerprint &&
    input.alias.bindingKind === input.bindingKind &&
    input.alias.statusSecretHash === input.request.statusSecretHash &&
    input.alias.purpose === "readOnlyDeletionStatus";
}

function makeStatusAliasV1(input: {
  request: RequestDeletion;
  internalJobId: string;
  generationHash: string;
  acceptedSemanticFingerprint: string;
  bindingKind: "winningOperation" | "sameGenerationConvergence";
  nowSecV1: number;
}): AccountDeletionStatusAliasContract {
  const value: AccountDeletionStatusAliasContract = {
    schemaVersion: 1,
    requestId: input.request.requestId,
    internalJobId: input.internalJobId,
    generationHash: input.generationHash,
    acceptedSemanticFingerprint: input.acceptedSemanticFingerprint,
    bindingKind: input.bindingKind,
    purpose: "readOnlyDeletionStatus",
    statusSecretHash: input.request.statusSecretHash,
    createdAt: new Date(input.nowSecV1 * 1000),
    expiryPolicyDecisionId: "retention.deletion_operational_residue",
  };
  return parseCandidateStatusAliasV1(value);
}

function makeStatusControlV1(input: {
  request: RequestDeletion;
  internalJobId: string;
  generationHash: string;
  acceptedLifecycleEpochV2: number;
}) {
  return parseCandidateDeletionStatusControlV1({
    schemaVersion: 1,
    requestId: input.request.requestId,
    internalJobId: input.internalJobId,
    generationHash: input.generationHash,
    acceptedLifecycleEpochV2: input.acceptedLifecycleEpochV2,
    stateV1: "active",
    expiresAtSecV1: null,
    expiryPolicyDecisionId: "retention.deletion_operational_residue",
  });
}

function makeOperationReceiptV1(input: {
  request: RequestDeletion;
  scope: AuthIncarnationScopeV2;
  internalJobId: string;
  generationHash: string;
  semanticHash: string;
  envelopeHash: string;
  acceptedSemanticFingerprint: string;
  acceptedLifecycleEpochV2: number;
  bindingKind: "winningOperation" | "sameGenerationConvergence";
  acceptedAtSecV1: number;
}): CandidateDeletionOperationReceiptV1 {
  return parseCandidateOperationReceiptV1({
    schemaVersion: 1,
    receiptIdV1: deletionOperationReceiptIdV1({
      scope: input.scope,
      generationHash: input.generationHash,
      operationId: input.request.operationId,
    }),
    operationId: input.request.operationId,
    requestId: input.request.requestId,
    internalJobId: input.internalJobId,
    ...input.scope,
    generationHash: input.generationHash,
    acceptedLifecycleEpochV2: input.acceptedLifecycleEpochV2,
    submittedSemanticFingerprint: input.semanticHash,
    submittedEnvelopeFingerprint: input.envelopeHash,
    acceptedSemanticFingerprint: input.acceptedSemanticFingerprint,
    bindingKind: input.bindingKind,
    acceptedAtSecV1: input.acceptedAtSecV1,
  });
}

async function requireCanonicalAcceptedOutboxV1(input: {
  transaction: CandidateDeletionTransactionV1;
  scope: AuthIncarnationScopeV2;
  internalJobId: string;
  generationHash: string;
  acceptedLifecycleEpochV2: number;
  job: AccountDeletionJobContract;
  binding: CandidateDeletionJobBindingV1;
}): Promise<void> {
  const expectedTasks = initialDeletionTasksV1({
    scope: input.scope,
    internalJobId: input.internalJobId,
    generationHash: input.generationHash,
    acceptedLifecycleEpochV2: input.acceptedLifecycleEpochV2,
    nowSecV1: 0,
  });
  const [providerBindingRaw, firebaseRaw, appleRaw, ...taskAndReceiptRows] =
    await Promise.all([
      input.transaction.read(deletionProviderBindingPathV1(input.internalJobId)),
      input.transaction.read(deletionProviderCheckpointPathV1(
        input.internalJobId,
        "firebaseAuth",
      )),
      input.transaction.read(deletionProviderCheckpointPathV1(
        input.internalJobId,
        "appleCredential",
      )),
      ...expectedTasks.map((task) => input.transaction.read(
        deletionTaskPathV1(input.internalJobId, task.effectIdV1),
      )),
      ...expectedTasks.map((task) => input.transaction.read(
        deletionEffectReceiptPathV1(input.internalJobId, task.effectIdV1),
      )),
    ]);
  const taskRows = taskAndReceiptRows.slice(0, expectedTasks.length);
  const receiptRows = taskAndReceiptRows.slice(expectedTasks.length);
  if (providerBindingRaw === null || firebaseRaw === null || appleRaw === null ||
      taskRows.some((row) => row === null)) ad04FailV1("AD04_OPERATION_CONFLICT");
  try {
    const providerBinding = parseCandidateDeletionProviderBindingV1(providerBindingRaw);
    const firebase = parseCandidateProviderCheckpointV1(firebaseRaw);
    const apple = parseCandidateProviderCheckpointV1(appleRaw);
    if (input.job.internalJobId !== input.internalJobId ||
        input.job.generationHash !== input.generationHash ||
        input.job.policyVersion !== input.binding.policyVersion ||
        !input.job.authorityFenceDurable ||
        !input.job.minimumCleanupReferencesCaptured ||
        !sameAd04ScopeV1(input.binding, input.scope) ||
        input.binding.internalJobId !== input.internalJobId ||
        input.binding.generationHash !== input.generationHash ||
        input.binding.acceptedLifecycleEpochV2 !== input.acceptedLifecycleEpochV2 ||
        !sameAd04ScopeV1(providerBinding, input.scope) ||
        providerBinding.internalJobId !== input.internalJobId ||
        providerBinding.generationHash !== input.generationHash ||
        providerBinding.acceptedLifecycleEpochV2 !== input.acceptedLifecycleEpochV2 ||
        providerBinding.recordedAtSecV1 !== input.binding.acceptedAtSecV1 ||
        firebase.provider !== "firebaseAuth" || apple.provider !== "appleCredential") {
      ad04FailV1("AD04_OPERATION_CONFLICT");
    }
    taskRows.forEach((row, index) => {
      const actual = parseCandidateDeletionTaskV1(row);
      const expected = expectedTasks[index];
      if (!sameAd04ScopeV1(actual, expected) ||
          actual.internalJobId !== expected.internalJobId ||
          actual.generationHash !== expected.generationHash ||
          actual.acceptedLifecycleEpochV2 !== expected.acceptedLifecycleEpochV2 ||
          actual.effectIdV1 !== expected.effectIdV1 ||
          actual.effectFingerprintV1 !== expected.effectFingerprintV1 ||
          actual.kindV1 !== expected.kindV1 ||
          actual.adapterIdV1 !== expected.adapterIdV1 ||
          actual.adapterVersionV1 !== expected.adapterVersionV1 ||
          actual.createdAtSecV1 !== input.binding.acceptedAtSecV1) {
        ad04FailV1("AD04_OPERATION_CONFLICT");
      }
      const receiptRaw = receiptRows[index];
      if ((actual.stateV1 === "complete") !== (receiptRaw !== null)) {
        ad04FailV1("AD04_OPERATION_CONFLICT");
      }
      if (receiptRaw !== null) {
        const receipt = parseCandidateEffectReceiptV1(receiptRaw);
        if (!sameAd04ScopeV1(receipt, actual) ||
            receipt.internalJobId !== actual.internalJobId ||
            receipt.generationHash !== actual.generationHash ||
            receipt.acceptedLifecycleEpochV2 !== actual.acceptedLifecycleEpochV2 ||
            receipt.effectIdV1 !== actual.effectIdV1 ||
            receipt.effectFingerprintV1 !== actual.effectFingerprintV1 ||
            receipt.kindV1 !== actual.kindV1 ||
            receipt.adapterIdV1 !== actual.adapterIdV1 ||
            receipt.recordedAtSecV1 !== actual.completedAtSecV1) {
          ad04FailV1("AD04_OPERATION_CONFLICT");
        }
      }
    });
  } catch {
    ad04FailV1("AD04_OPERATION_CONFLICT");
  }
}

function validatedAuthorityForDepartureV1(input: {
  principal: VerifiedDeletionPrincipalV1;
  lifecycleRaw: unknown;
  membershipRaw: unknown;
  associationId: string;
}): ValidatedActiveAuthorityV2 {
  const decision = evaluateAccountAuthorizationV2({
    sessionAttemptIdV2: `ad04-${input.principal.accountGenerationV2.slice(0, 32)}`,
    sessionAttemptEpochV2: 1,
    sessionAttemptNonceV2: input.principal.verificationNonceV1,
    expectedScope: ad04ScopeV1(input.principal),
    tokenProof: {
      authIncarnationSchemaVersionV2: 2,
      ...ad04ScopeV1(input.principal),
      accountGenerationV2: input.principal.accountGenerationV2,
      accountLifecycleEpochV2: input.principal.accountLifecycleEpochV2,
      authTimeSec: input.principal.authTimeSecV1,
    },
    lifecycle: input.lifecycleRaw,
    membership: input.membershipRaw,
    requiredCapability: "association.manage",
  });
  if (!decision.authorized || decision.binding.associationId !== input.associationId) {
    ad04FailV1("AD04_IMPACT_CHANGED");
  }
  return decision.binding;
}

function controlListsPrincipalV1(input: {
  controlRaw: unknown;
  principal: VerifiedDeletionPrincipalV1;
  associationId: string;
}): boolean {
  if (input.controlRaw === null) return false;
  let control;
  try {
    control = parseAssociationOwnershipControlV2(input.controlRaw);
  } catch {
    ad04FailV1("AD04_IMPACT_CHANGED");
  }
  if (control.authProjectIdV2 !== input.principal.authProjectIdV2 ||
      control.authTenantIdV2 !== input.principal.authTenantIdV2 ||
      control.associationId !== input.associationId) {
    ad04FailV1("AD04_IMPACT_CHANGED");
  }
  return control.recoverableOwnersV2.some((owner) =>
    owner.authProjectIdV2 === input.principal.authProjectIdV2 &&
    owner.authTenantIdV2 === input.principal.authTenantIdV2 &&
    owner.authUidV2 === input.principal.authUidV2 &&
    owner.accountGenerationV2 === input.principal.accountGenerationV2 &&
    owner.accountLifecycleEpochV2 === input.principal.accountLifecycleEpochV2,
  );
}

function requireNewAcceptanceLifecycleV1(input: {
  lifecycleRaw: unknown;
  principal: VerifiedDeletionPrincipalV1;
}): {current: AccountLifecycleAuthorityV2 | null; deletingEpochV2: number} {
  const current = parseLifecycleOrNull(input.lifecycleRaw);
  if (current !== null) {
    if (!sameAd04ScopeV1(current, input.principal) ||
        current.accountGenerationV2 !== input.principal.accountGenerationV2 ||
        current.accountLifecycleEpochV2 !== input.principal.accountLifecycleEpochV2 ||
        current.lifecycleStateV2 !== "active" ||
        input.principal.authTimeSecV1 <= current.reauthAfterSecV2) {
      ad04FailV1("AD04_AUTHORITY_DENIED");
    }
  }
  if (input.principal.accountLifecycleEpochV2 >= Number.MAX_SAFE_INTEGER) {
    ad04FailV1("AD04_AUTHORITY_DENIED");
  }
  return {current, deletingEpochV2: input.principal.accountLifecycleEpochV2 + 1};
}

function validateRevocationMaterialV1(input: {
  raw: unknown | null;
  request: RequestDeletion;
  principal: VerifiedDeletionPrincipalV1;
  nowSecV1: number;
}): CandidateRevocationMaterialV1 | null {
  if (input.principal.providerRelationshipV1 !== "apple") {
    if (input.request.providerRevocationRef !== undefined) {
      ad04FailV1("AD04_INVALID_REQUEST");
    }
    return null;
  }
  if (input.request.providerRevocationRef === undefined) return null;
  if (input.raw === null) ad04FailV1("AD04_INVALID_REQUEST");
  const material = parseCandidateRevocationMaterialV1(input.raw);
  if (!sameAd04ScopeV1(material, input.principal) ||
      material.generationHash !== input.principal.accountGenerationV2 ||
      material.providerRevocationRefV1 !== input.request.providerRevocationRef ||
      material.providerSubjectHashV1 !== input.principal.appleProviderSubjectHashV1 ||
      material.accountLifecycleEpochV2 !== input.principal.accountLifecycleEpochV2 ||
      material.stateV1 !== "available" || material.expiresAtSecV1 < input.nowSecV1) {
    ad04FailV1("AD04_INVALID_REQUEST");
  }
  return material;
}

function makeProviderBindingV1(input: {
  principal: VerifiedDeletionPrincipalV1;
  internalJobId: string;
  request: RequestDeletion;
  nowSecV1: number;
  acceptedLifecycleEpochV2: number;
}): CandidateDeletionProviderBindingV1 {
  const relationship = input.principal.providerRelationshipV1;
  return parseCandidateDeletionProviderBindingV1({
    schemaVersion: 1,
    internalJobId: input.internalJobId,
    ...ad04ScopeV1(input.principal),
    generationHash: input.principal.accountGenerationV2,
    acceptedLifecycleEpochV2: input.acceptedLifecycleEpochV2,
    providerRelationshipV1: relationship,
    appleProviderSubjectHashV1: input.principal.appleProviderSubjectHashV1,
    providerRevocationRefV1: input.request.providerRevocationRef ?? null,
    materialStateV1: relationship === "apple"
      ? (input.request.providerRevocationRef === undefined ? "missing" : "available")
      : relationship === "nonApple" ? "notApplicable" : "unknown",
    recordedAtSecV1: input.nowSecV1,
  });
}

export async function acceptCandidateAccountDeletionV1(input: {
  repository: CandidateDeletionRepositoryV1;
  principal: VerifiedDeletionPrincipalV1;
  request: unknown;
  nowSecV1: number;
}): Promise<AcceptedCandidateDeletionV1> {
  assertVerifiedPrincipalV1(input.principal);
  let request: RequestDeletion;
  try {
    request = validateRequestDeletion(input.request);
  } catch {
    ad04FailV1("AD04_INVALID_REQUEST");
  }
  const nowSecV1 = ad04CounterV1(input.nowSecV1);
  if (input.principal.authTimeSecV1 > nowSecV1 ||
      nowSecV1 - input.principal.authTimeSecV1 >
        ACCOUNT_DELETION_AD04_FRESH_AUTH_MAX_AGE_SEC_V1) {
    ad04FailV1("AD04_REAUTH_REQUIRED");
  }
  if (input.principal.accountLifecycleEpochV2 === Number.MAX_SAFE_INTEGER) {
    ad04FailV1("AD04_AUTHORITY_DENIED");
  }
  const acceptedLifecycleEpochV2 = input.principal.accountLifecycleEpochV2 + 1;
  const generationInput = principalGenerationInput(input.principal);
  const semanticHash = semanticFingerprint(request, generationInput);
  const envelopeHash = operationEnvelopeFingerprint(request, semanticHash);
  const scope = ad04ScopeV1(input.principal);
  const internalJobId = deletionInternalJobIdV1(scope, input.principal.accountGenerationV2);
  const receiptId = deletionOperationReceiptIdV1({
    scope,
    generationHash: input.principal.accountGenerationV2,
    operationId: request.operationId,
  });
  return input.repository.runTransaction(async (transaction) => {
    const [receiptRaw, jobRaw, bindingRaw, aliasRaw, statusControlRaw] = await Promise.all([
      transaction.read(deletionOperationReceiptPathV1(receiptId)),
      transaction.read(deletionJobPathV1(internalJobId)),
      transaction.read(deletionJobBindingPathV1(internalJobId)),
      transaction.read(deletionStatusAliasPathV1(request.requestId)),
      transaction.read(deletionStatusControlPathV1(request.requestId)),
    ]);
    if (receiptRaw !== null) {
      const receipt = parseCandidateOperationReceiptV1(receiptRaw);
      if (!receiptMatchesV1({
        receipt,
        request,
        scope,
        generationHash: input.principal.accountGenerationV2,
        semanticHash,
        envelopeHash,
        internalJobId,
        acceptedLifecycleEpochV2,
      }) || jobRaw === null || bindingRaw === null || aliasRaw === null) {
        ad04FailV1("AD04_OPERATION_CONFLICT");
      }
      const job = parseCandidateDeletionJobV1(jobRaw);
      const binding = parseCandidateDeletionJobBindingV1(bindingRaw);
      const alias = parseCandidateStatusAliasV1(aliasRaw);
      if (job.internalJobId !== internalJobId ||
          job.generationHash !== input.principal.accountGenerationV2 ||
          !sameAd04ScopeV1(binding, scope) || statusControlRaw === null ||
          binding.internalJobId !== internalJobId ||
          binding.generationHash !== input.principal.accountGenerationV2 ||
          binding.acceptedSemanticFingerprint !== receipt.acceptedSemanticFingerprint ||
          !aliasMatchesRequestV1({
            alias,
            request,
            internalJobId,
            generationHash: input.principal.accountGenerationV2,
            acceptedSemanticFingerprint: receipt.acceptedSemanticFingerprint,
            bindingKind: receipt.bindingKind,
          })) ad04FailV1("AD04_OPERATION_CONFLICT");
      const statusControl = parseCandidateDeletionStatusControlV1(statusControlRaw);
      if (statusControl.requestId !== request.requestId ||
          statusControl.internalJobId !== internalJobId ||
          statusControl.generationHash !== input.principal.accountGenerationV2 ||
          statusControl.acceptedLifecycleEpochV2 !== acceptedLifecycleEpochV2 ||
          statusControl.expiryPolicyDecisionId !== alias.expiryPolicyDecisionId ||
          binding.acceptedLifecycleEpochV2 !== acceptedLifecycleEpochV2 ||
          receipt.acceptedAtSecV1 !== binding.acceptedAtSecV1 ||
          alias.createdAt.getTime() !== receipt.acceptedAtSecV1 * 1000 ||
          (receipt.bindingKind === "winningOperation" &&
           receipt.acceptedSemanticFingerprint !== semanticHash) ||
          (receipt.bindingKind === "winningOperation"
            ? binding.winningOperationId !== request.operationId
            : binding.winningOperationId === request.operationId)) {
        ad04FailV1("AD04_OPERATION_CONFLICT");
      }
      await requireCanonicalAcceptedOutboxV1({
        transaction,
        scope,
        internalJobId,
        generationHash: input.principal.accountGenerationV2,
        acceptedLifecycleEpochV2,
        job,
        binding,
      });
      return acceptedResultV1({
        requestId: request.requestId,
        internalJobId,
        acceptedAtSecV1: receipt.acceptedAtSecV1,
        bindingKind: receipt.bindingKind,
      });
    }
    if (jobRaw !== null || bindingRaw !== null) {
      if (jobRaw === null || bindingRaw === null || aliasRaw !== null ||
          statusControlRaw !== null) {
        ad04FailV1("AD04_OPERATION_CONFLICT");
      }
      const job = parseCandidateDeletionJobV1(jobRaw);
      const binding = parseCandidateDeletionJobBindingV1(bindingRaw);
      if (job.internalJobId !== internalJobId ||
          job.generationHash !== input.principal.accountGenerationV2 ||
          !sameAd04ScopeV1(binding, scope) ||
          binding.internalJobId !== internalJobId ||
          binding.generationHash !== input.principal.accountGenerationV2 ||
          binding.acceptedLifecycleEpochV2 !== acceptedLifecycleEpochV2 ||
          !job.authorityFenceDurable || !job.minimumCleanupReferencesCaptured ||
          binding.statusAliasCountV1 >= ACCOUNT_DELETION_AD04_MAX_STATUS_ALIASES_V1) {
        ad04FailV1("AD04_OPERATION_CONFLICT");
      }
      await requireCanonicalAcceptedOutboxV1({
        transaction,
        scope,
        internalJobId,
        generationHash: input.principal.accountGenerationV2,
        acceptedLifecycleEpochV2,
        job,
        binding,
      });
      const alias = makeStatusAliasV1({
        request,
        internalJobId,
        generationHash: input.principal.accountGenerationV2,
        acceptedSemanticFingerprint: binding.acceptedSemanticFingerprint,
        bindingKind: "sameGenerationConvergence",
        nowSecV1,
      });
      const receipt = makeOperationReceiptV1({
        request,
        scope,
        internalJobId,
        generationHash: input.principal.accountGenerationV2,
        semanticHash,
        envelopeHash,
        acceptedSemanticFingerprint: binding.acceptedSemanticFingerprint,
        acceptedLifecycleEpochV2,
        bindingKind: "sameGenerationConvergence",
        acceptedAtSecV1: binding.acceptedAtSecV1,
      });
      const statusControl = makeStatusControlV1({
        request,
        internalJobId,
        generationHash: input.principal.accountGenerationV2,
        acceptedLifecycleEpochV2,
      });
      transaction.write(deletionStatusAliasPathV1(request.requestId), alias as unknown as
        Readonly<Record<string, unknown>>);
      transaction.write(deletionOperationReceiptPathV1(receiptId), receipt as unknown as
        Readonly<Record<string, unknown>>);
      transaction.write(deletionStatusControlPathV1(request.requestId),
        statusControl as unknown as Readonly<Record<string, unknown>>);
      transaction.write(deletionJobBindingPathV1(internalJobId), {
        ...binding,
        statusAliasCountV1: binding.statusAliasCountV1 + 1,
      });
      return acceptedResultV1({
        requestId: request.requestId,
        internalJobId,
        acceptedAtSecV1: binding.acceptedAtSecV1,
        bindingKind: "sameGenerationConvergence",
      });
    }
    if (aliasRaw !== null || statusControlRaw !== null) {
      ad04FailV1("AD04_OPERATION_CONFLICT");
    }

    const intentRaw = await transaction.read(deletionIntentPathV1(request.intentId));
    if (intentRaw === null) ad04FailV1("AD04_IMPACT_CHANGED");
    const intent = parseCandidateDeletionIntentV1(intentRaw);
    if (!sameAd04ScopeV1(intent, scope) ||
        intent.generationHash !== input.principal.accountGenerationV2 ||
        intent.expectedLifecycleEpochV2 !== input.principal.accountLifecycleEpochV2 ||
        intent.policyVersion !== request.policyVersion ||
        intent.impactVersion !== request.impactVersion ||
        intent.custodyChoice !== request.custodyChoice ||
        intent.providerRelationshipV1 !== input.principal.providerRelationshipV1) {
      ad04FailV1("AD04_IMPACT_CHANGED");
    }
    if (nowSecV1 > intent.expiresAtSecV1) ad04FailV1("AD04_INTENT_EXPIRED");

    const materialPath = request.providerRevocationRef === undefined
      ? null : deletionRevocationMaterialPathV1(request.providerRevocationRef);
    const tasks = initialDeletionTasksV1({
      scope,
      internalJobId,
      generationHash: input.principal.accountGenerationV2,
      acceptedLifecycleEpochV2,
      nowSecV1,
    });
    const [lifecycleRaw, membershipRaw, materialRaw, providerBindingRaw,
      firebaseCheckpointRaw, appleCheckpointRaw, ...taskSlots] = await Promise.all([
      transaction.read(candidateAccountLifecycleAuthorityPathV1(scope)),
      transaction.read(candidateMembershipAuthorityPathV1(scope)),
      materialPath === null ? Promise.resolve(null) : transaction.read(materialPath),
      transaction.read(deletionProviderBindingPathV1(internalJobId)),
      transaction.read(deletionProviderCheckpointPathV1(internalJobId, "firebaseAuth")),
      transaction.read(deletionProviderCheckpointPathV1(internalJobId, "appleCredential")),
      ...tasks.map((task) => transaction.read(
        deletionTaskPathV1(internalJobId, task.effectIdV1),
      )),
      ...tasks.map((task) => transaction.read(
        deletionEffectReceiptPathV1(internalJobId, task.effectIdV1),
      )),
      ...tasks.filter((task) => task.adapterIdV1 !== null).map((task) =>
        transaction.read(deletionAdapterResultPathV1(
          internalJobId,
          task.adapterIdV1!,
        )),
      ),
    ]);
    if (providerBindingRaw !== null || firebaseCheckpointRaw !== null ||
        appleCheckpointRaw !== null || taskSlots.some((slot) => slot !== null)) {
      ad04FailV1("AD04_OPERATION_CONFLICT");
    }
    validateRevocationMaterialV1({
      raw: materialRaw,
      request,
      principal: input.principal,
      nowSecV1,
    });
    const lifecycle = requireNewAcceptanceLifecycleV1({
      lifecycleRaw,
      principal: input.principal,
    });
    const membership = parseMembershipOrNull(membershipRaw);
    const membershipStateRequiresAttention = membershipRaw !== null && membership === null;
    const validMembership = membership !== null &&
      sameAd04ScopeV1(membership, scope) &&
      membership.accountGenerationV2 === input.principal.accountGenerationV2 &&
      membership.accountLifecycleEpochV2 === input.principal.accountLifecycleEpochV2 &&
      membership.membershipStatusV2 === "active";
    let controlRaw: unknown | null = null;
    if (validMembership) {
      controlRaw = await transaction.read(associationOwnershipControlPathV2({
        authProjectIdV2: scope.authProjectIdV2,
        authTenantIdV2: scope.authTenantIdV2,
        associationId: membership.associationId,
      }));
    }
    if (validMembership && membership.capabilities.includes("association.manage") &&
        controlRaw === null) {
      ad04FailV1("AD04_IMPACT_CHANGED");
    }
    const isOwner = validMembership && controlListsPrincipalV1({
      controlRaw,
      principal: input.principal,
      associationId: membership.associationId,
    });
    if ((intent.ownerDepartureRequestV2 !== null) !== isOwner ||
        (intent.ownerDepartureRequestV2 !== null &&
         (!validMembership || intent.associationId !== membership.associationId))) {
      ad04FailV1("AD04_IMPACT_CHANGED");
    }

    let custodyReceipt: OwnerDepartureReceiptV2 | null = null;
    if (intent.ownerDepartureRequestV2 !== null && validMembership) {
      const authority = validatedAuthorityForDepartureV1({
        principal: input.principal,
        lifecycleRaw,
        membershipRaw,
        associationId: membership.associationId,
      });
      custodyReceipt = await applyOwnerDepartureInTransactionV2({
        transaction,
        departingAuthority: authority,
        request: intent.ownerDepartureRequestV2,
        nowSecV2: nowSecV1,
        candidateTestCustodyPolicyIdV2: intent.candidateTestCustodyPolicyIdV2,
      });
    }

    const deletingLifecycle = {
      authIncarnationSchemaVersionV2: 2 as const,
      ...scope,
      accountGenerationV2: input.principal.accountGenerationV2,
      accountLifecycleEpochV2: lifecycle.deletingEpochV2,
      lifecycleStateV2: "deleting" as const,
      reauthAfterSecV2: nowSecV1,
    };
    const custodyRequiresAttention = membershipStateRequiresAttention ||
      custodyReceipt?.requiresOperationalAttentionV2 === true;
    const job: AccountDeletionJobContract = parseCandidateDeletionJobV1({
      schemaVersion: 1,
      internalJobId,
      generationHash: input.principal.accountGenerationV2,
      state: "accepted",
      resumeStage: null,
      policyVersion: request.policyVersion,
      inventoryVersion: accountDeletionVersions.inventoryVersion,
      attempt: 0,
      leaseGeneration: 0,
      authorityFenceDurable: true,
      minimumCleanupReferencesCaptured: true,
      authDeletionCheckpointState: "scheduled",
      authAbsent: false,
      dataDispositionVerified: false,
      publicPrivacyVerified: false,
      custodyRecorded: !custodyRequiresAttention,
      providerDispositionRecorded: false,
      restoreSuppressionDurable: false,
      safeErrorCode: null,
    });
    const binding: CandidateDeletionJobBindingV1 =
      parseCandidateDeletionJobBindingV1({
        schemaVersion: 1,
        internalJobId,
        ...scope,
        generationHash: input.principal.accountGenerationV2,
        authCreatedAtIsoV1: input.principal.authCreatedAtV1.toISOString(),
        acceptedLifecycleEpochV2: lifecycle.deletingEpochV2,
        acceptedSemanticFingerprint: semanticHash,
        winningOperationId: request.operationId,
        policyVersion: request.policyVersion,
        impactVersion: request.impactVersion,
        custodyChoice: request.custodyChoice,
        associationId: intent.associationId,
        custodyOutcomeV1: custodyReceipt?.outcomeV2 ??
          (membershipStateRequiresAttention
            ? "policyBlockedButDeletionMustReceiveOperationalResolution"
            : "ordinary"),
        custodyRequiresAttentionV1: custodyRequiresAttention,
        acceptedAtSecV1: nowSecV1,
        statusAliasCountV1: 1,
      });
    const providerBinding = makeProviderBindingV1({
      principal: input.principal,
      internalJobId,
      request,
      nowSecV1,
      acceptedLifecycleEpochV2,
    });
    const alias = makeStatusAliasV1({
      request,
      internalJobId,
      generationHash: input.principal.accountGenerationV2,
      acceptedSemanticFingerprint: semanticHash,
      bindingKind: "winningOperation",
      nowSecV1,
    });
    const receipt = makeOperationReceiptV1({
      request,
      scope,
      internalJobId,
      generationHash: input.principal.accountGenerationV2,
      acceptedLifecycleEpochV2,
      semanticHash,
      envelopeHash,
      acceptedSemanticFingerprint: semanticHash,
      bindingKind: "winningOperation",
      acceptedAtSecV1: nowSecV1,
    });
    const statusControl = makeStatusControlV1({
      request,
      internalJobId,
      generationHash: input.principal.accountGenerationV2,
      acceptedLifecycleEpochV2,
    });
    transaction.write(candidateAccountLifecycleAuthorityPathV1(scope), deletingLifecycle);
    if (validMembership && membership !== null) {
      transaction.write(candidateMembershipAuthorityPathV1(scope), {
        ...membership,
        accountLifecycleEpochV2: lifecycle.deletingEpochV2,
        membershipStatusV2: "revoked",
        capabilities: [],
      });
    }
    transaction.write(deletionJobPathV1(internalJobId), job as unknown as
      Readonly<Record<string, unknown>>);
    transaction.write(deletionJobBindingPathV1(internalJobId), binding as unknown as
      Readonly<Record<string, unknown>>);
    transaction.write(deletionProviderBindingPathV1(internalJobId), providerBinding as unknown as
      Readonly<Record<string, unknown>>);
    transaction.write(deletionStatusAliasPathV1(request.requestId), alias as unknown as
      Readonly<Record<string, unknown>>);
    transaction.write(deletionStatusControlPathV1(request.requestId),
      statusControl as unknown as Readonly<Record<string, unknown>>);
    transaction.write(deletionOperationReceiptPathV1(receiptId), receipt as unknown as
      Readonly<Record<string, unknown>>);
    transaction.write(deletionProviderCheckpointPathV1(internalJobId, "firebaseAuth"), {
      schemaVersion: 1,
      provider: "firebaseAuth",
      state: "pending",
      evidenceCode: "accepted_auth_work_scheduled",
      checkedAt: new Date(nowSecV1 * 1000),
    });
    transaction.write(deletionProviderCheckpointPathV1(internalJobId, "appleCredential"), {
      schemaVersion: 1,
      provider: "appleCredential",
      state: "pending",
      evidenceCode: "accepted_provider_work_scheduled",
      checkedAt: new Date(nowSecV1 * 1000),
    });
    for (const task of tasks) {
      transaction.write(deletionTaskPathV1(internalJobId, task.effectIdV1), task as unknown as
        Readonly<Record<string, unknown>>);
    }
    return acceptedResultV1({
      requestId: request.requestId,
      internalJobId,
      acceptedAtSecV1: nowSecV1,
      bindingKind: "winningOperation",
    });
  });
}

function providerOutcomeV1(
  checkpoint: ReturnType<typeof parseCandidateProviderCheckpointV1>,
): CandidateDeletionStatusV1["providerOutcome"] {
  if (checkpoint.state === "complete") return "revoked";
  if (checkpoint.state === "notApplicable") return "not_applicable";
  if (checkpoint.state === "manualActionGuidance") return "manual_action_guidance";
  return "pending";
}

export async function getCandidateAccountDeletionStatusV1(input: {
  repository: CandidateDeletionRepositoryV1;
  request: unknown;
  nowSecV1: number;
}): Promise<CandidateDeletionStatusV1> {
  const data = ad04RecordV1(input.request);
  if (data === null || !ad04ExactKeysV1(data, [
    "schemaVersion", "requestId", "statusSecret",
  ]) || data.schemaVersion !== 1) ad04FailV1("AD04_STATUS_UNAVAILABLE");
  let requestId: string;
  try {
    requestId = ad04OpaqueIdV1(data.requestId);
  } catch {
    ad04FailV1("AD04_STATUS_UNAVAILABLE");
  }
  const nowSecV1 = ad04CounterV1(input.nowSecV1);
  const [aliasRaw, statusControlRaw] = await Promise.all([
    input.repository.read(deletionStatusAliasPathV1(requestId)),
    input.repository.read(deletionStatusControlPathV1(requestId)),
  ]);
  if (aliasRaw === null || statusControlRaw === null) {
    ad04FailV1("AD04_STATUS_UNAVAILABLE");
  }
  let alias: AccountDeletionStatusAliasContract;
  try {
    alias = parseCandidateStatusAliasV1(aliasRaw);
    if (typeof data.statusSecret !== "string" ||
        !statusSecretMatches(data.statusSecret, alias.statusSecretHash)) {
      ad04FailV1("AD04_STATUS_UNAVAILABLE");
    }
  } catch {
    ad04FailV1("AD04_STATUS_UNAVAILABLE");
  }
  let statusControl: ReturnType<typeof parseCandidateDeletionStatusControlV1>;
  try {
    statusControl = parseCandidateDeletionStatusControlV1(statusControlRaw);
  } catch {
    ad04FailV1("AD04_STATUS_UNAVAILABLE");
  }
  if (alias.requestId !== requestId ||
      statusControl.requestId !== requestId ||
      statusControl.internalJobId !== alias.internalJobId ||
      statusControl.generationHash !== alias.generationHash ||
      statusControl.expiryPolicyDecisionId !== alias.expiryPolicyDecisionId ||
      statusControl.stateV1 !== "active" ||
      (statusControl.expiresAtSecV1 !== null &&
       statusControl.expiresAtSecV1 <= nowSecV1)) {
    ad04FailV1("AD04_STATUS_UNAVAILABLE");
  }
  const [jobRaw, bindingRaw, providerBindingRaw, appleRaw] = await Promise.all([
    input.repository.read(deletionJobPathV1(alias.internalJobId)),
    input.repository.read(deletionJobBindingPathV1(alias.internalJobId)),
    input.repository.read(deletionProviderBindingPathV1(alias.internalJobId)),
    input.repository.read(deletionProviderCheckpointPathV1(
      alias.internalJobId,
      "appleCredential",
    )),
  ]);
  if (jobRaw === null || bindingRaw === null || providerBindingRaw === null ||
      appleRaw === null) {
    ad04FailV1("AD04_STATUS_UNAVAILABLE");
  }
  let job: AccountDeletionJobContract;
  let binding: CandidateDeletionJobBindingV1;
  let providerBinding: CandidateDeletionProviderBindingV1;
  let apple: ReturnType<typeof parseCandidateProviderCheckpointV1>;
  try {
    job = parseCandidateDeletionJobV1(jobRaw);
    binding = parseCandidateDeletionJobBindingV1(bindingRaw);
    providerBinding = parseCandidateDeletionProviderBindingV1(providerBindingRaw);
    apple = parseCandidateProviderCheckpointV1(appleRaw);
  } catch {
    ad04FailV1("AD04_STATUS_UNAVAILABLE");
  }
  if (job.internalJobId !== alias.internalJobId ||
      job.generationHash !== alias.generationHash ||
      job.policyVersion !== binding.policyVersion ||
      !job.authorityFenceDurable || !job.minimumCleanupReferencesCaptured ||
      binding.internalJobId !== alias.internalJobId ||
      binding.generationHash !== alias.generationHash ||
      binding.acceptedSemanticFingerprint !== alias.acceptedSemanticFingerprint ||
      binding.acceptedLifecycleEpochV2 !== statusControl.acceptedLifecycleEpochV2 ||
      binding.acceptedAtSecV1 > nowSecV1 ||
      alias.createdAt.getTime() < binding.acceptedAtSecV1 * 1000 ||
      alias.createdAt.getTime() > nowSecV1 * 1000 ||
      providerBinding.internalJobId !== alias.internalJobId ||
      providerBinding.generationHash !== alias.generationHash ||
      providerBinding.acceptedLifecycleEpochV2 !== statusControl.acceptedLifecycleEpochV2 ||
      providerBinding.recordedAtSecV1 !== binding.acceptedAtSecV1 ||
      !sameAd04ScopeV1(providerBinding, binding) ||
      apple.provider !== "appleCredential" || apple.checkedAt.getTime() > nowSecV1 * 1000) {
    ad04FailV1("AD04_STATUS_UNAVAILABLE");
  }
  const phase = job.state === "complete"
    ? "complete"
    : job.state === "needsAttention"
      ? "attentionRequired"
      : job.authAbsent
        ? "accountRemovedCleanupPending"
        : "processing";
  let completedAt: string | undefined;
  if (job.state === "complete") {
    const expectedEffectIdV1 = deletionTaskEffectIdV1({
      internalJobId: alias.internalJobId,
      generationHash: alias.generationHash,
      acceptedLifecycleEpochV2: binding.acceptedLifecycleEpochV2,
      kindV1: "reconcileCompletion",
      adapterIdV1: null,
    });
    const expectedEffectFingerprintV1 = deletionTaskEffectFingerprintV1({
      scope: binding,
      internalJobId: alias.internalJobId,
      generationHash: alias.generationHash,
      acceptedLifecycleEpochV2: binding.acceptedLifecycleEpochV2,
      kindV1: "reconcileCompletion",
      adapterIdV1: null,
      adapterVersionV1: "account-deletion-reconcile-v1",
    });
    const completionRaw = await input.repository.read(deletionEffectReceiptPathV1(
      alias.internalJobId,
      expectedEffectIdV1,
    ));
    if (completionRaw === null) ad04FailV1("AD04_STATUS_UNAVAILABLE");
    let receipt;
    try {
      receipt = parseCandidateEffectReceiptV1(completionRaw);
    } catch {
      ad04FailV1("AD04_STATUS_UNAVAILABLE");
    }
    if (!sameAd04ScopeV1(receipt, binding) ||
        receipt.internalJobId !== alias.internalJobId ||
        receipt.generationHash !== alias.generationHash ||
        receipt.acceptedLifecycleEpochV2 !== binding.acceptedLifecycleEpochV2 ||
        receipt.effectIdV1 !== expectedEffectIdV1 ||
        receipt.effectFingerprintV1 !== expectedEffectFingerprintV1 ||
        receipt.kindV1 !== "reconcileCompletion" || receipt.adapterIdV1 !== null) {
      ad04FailV1("AD04_STATUS_UNAVAILABLE");
    }
    completedAt = new Date(receipt.recordedAtSecV1 * 1000).toISOString();
  }
  return Object.freeze({
    requestId,
    phase,
    acceptedAt: new Date(binding.acceptedAtSecV1 * 1000).toISOString(),
    ...(completedAt === undefined ? {} : {completedAt}),
    ...(phase === "complete" ? {} : {nextPollAfterSeconds: 15}),
    retainedCategoryCodes: Object.freeze([]),
    providerOutcome: providerOutcomeV1(apple),
    messageCode: phase === "processing"
      ? "AD_DELETION_REQUESTED"
      : phase === "accountRemovedCleanupPending"
        ? "AD_ACCOUNT_REMOVED_CLEANUP_PENDING"
        : phase === "attentionRequired"
          ? "AD_CLEANUP_ATTENTION_REQUIRED"
          : "AD_ACCOUNT_DELETION_COMPLETE",
  });
}

export function candidateRevocationMaterialV1(input: {
  scope: AuthIncarnationScopeV2;
  generationHash: string;
  accountLifecycleEpochV2: number;
  providerRevocationRefV1: string;
  providerSubjectHashV1: string;
  materialFingerprintV1: string;
  expiresAtSecV1: number;
}): CandidateRevocationMaterialV1 {
  return parseCandidateRevocationMaterialV1({
    schemaVersion: 1,
    providerRevocationRefV1: input.providerRevocationRefV1,
    ...ad04ScopeV1(input.scope),
    generationHash: input.generationHash,
    accountLifecycleEpochV2: input.accountLifecycleEpochV2,
    providerV1: "appleCredential",
    providerSubjectHashV1: input.providerSubjectHashV1,
    materialFingerprintV1: input.materialFingerprintV1,
    stateV1: "available",
    expiresAtSecV1: input.expiresAtSecV1,
  });
}

export function candidateImpactFingerprintV1(input: CandidateDeletionImpactV1): string {
  return canonicalSha256(input);
}

export function candidateJobStatusCoreV1(job: unknown): AccountDeletionJobContract {
  return parseCandidateDeletionJobV1(job);
}

export function candidateProviderBindingCoreV1(
  value: unknown,
): CandidateDeletionProviderBindingV1 {
  return parseCandidateDeletionProviderBindingV1(value);
}

export function candidateStatusAliasCoreV1(value: unknown): AccountDeletionStatusAliasContract {
  return parseCandidateStatusAliasV1(value);
}

export function candidateAdapterResultPathV1(jobId: string, adapterId: string): string {
  return deletionAdapterResultPathV1(jobId, adapterId);
}
