import {firebaseUidUtf16LeBase64Url} from
  "../domain/account_deletion_contract";
import {canonicalSha256} from "../domain/official_stats_contract";
import {
  AccountDeletionAdapterId,
  Ad05DispositionActionV1,
  CandidateAd05ExecutionBindingV1,
  ad05FailV1,
  parseCandidateAd05ExecutionBindingV1,
} from "./ad05_records";
import {
  ad04CounterV1,
  ad04ExactKeysV1,
  ad04HashV1,
  ad04OpaqueIdV1,
  ad04RecordV1,
  ad04ScopeV1,
  sameAd04ScopeV1,
} from "./ad04_records";

export const ACCOUNT_DELETION_AD05C_ACTIVATION_ALLOWED_V1 = false;
export const ACCOUNT_DELETION_AD05C_PRODUCTION_EXPORT_ALLOWED_V1 = false;

export const ad05cAdapterIdsV1 = [
  "firebase_auth_identity",
  "user_profile",
  "memberships_capabilities",
  "notification_inbox",
  "team_assignments",
  "pending_invites",
  "historical_invites",
  "authorization_evidence",
  "personal_ugc",
  "official_notices",
  "acknowledgements",
  "event_attribution",
] as const satisfies readonly AccountDeletionAdapterId[];

export type Ad05cAdapterIdV1 = typeof ad05cAdapterIdsV1[number];

export const ad05cTransactionalAdapterIdsV1 = [
  "user_profile",
  "memberships_capabilities",
  "team_assignments",
  "pending_invites",
  "personal_ugc",
] as const satisfies readonly Ad05cAdapterIdV1[];

export type Ad05cTransactionalAdapterIdV1 =
  typeof ad05cTransactionalAdapterIdsV1[number];

export const ad05cEvidenceOnlyAdapterIdsV1 = [
  "firebase_auth_identity",
  "historical_invites",
  "authorization_evidence",
  "official_notices",
  "acknowledgements",
  "event_attribution",
] as const satisfies readonly Ad05cAdapterIdV1[];

export type Ad05cEvidenceOnlyAdapterIdV1 =
  typeof ad05cEvidenceOnlyAdapterIdsV1[number];

export const ad05cActionByAdapterV1: Readonly<Record<
  Ad05cAdapterIdV1, Ad05DispositionActionV1
>> = Object.freeze({
  firebase_auth_identity: "erase",
  user_profile: "erase",
  memberships_capabilities: "erase",
  notification_inbox: "erase",
  team_assignments: "detach",
  pending_invites: "erase",
  historical_invites: "restrictedRetention",
  authorization_evidence: "restrictedRetention",
  personal_ugc: "erase",
  official_notices: "detach",
  acknowledgements: "detach",
  event_attribution: "detach",
});

function exact(value: unknown, keys: readonly string[]): Record<string, unknown> {
  const record = ad04RecordV1(value);
  if (record === null || !ad04ExactKeysV1(record, keys)) {
    ad05FailV1("AD05_INVALID_RECORD");
  }
  return record;
}

function adapterId(value: unknown): Ad05cAdapterIdV1 {
  const candidate = ad04OpaqueIdV1(value);
  if (!ad05cAdapterIdsV1.includes(candidate as Ad05cAdapterIdV1)) {
    ad05FailV1("AD05_INVALID_RECORD");
  }
  return candidate as Ad05cAdapterIdV1;
}

export function assertCandidateAd05cBindingV1(
  value: unknown,
): CandidateAd05ExecutionBindingV1 {
  const binding = parseCandidateAd05ExecutionBindingV1(value);
  const id = adapterId(binding.adapterIdV1);
  if (binding.actionV1 !== ad05cActionByAdapterV1[id] ||
      binding.policyVersionV1 !== "synthetic_policy_v1") {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  return binding;
}

export type Ad05cCustodyStateV1 =
  "notRequired" | "ownerDepartureComplete" | "custodySuspended";
export type Ad05cDispositionStateV1 =
  "active" | "erased" | "detached" | "revoked";

export interface CandidateAd05cFieldOwnedRecordV1 {
  schemaVersion: 1;
  adapterIdV1: Ad05cTransactionalAdapterIdV1;
  authProjectIdV2: string;
  authTenantIdV2: string | null;
  authUidV2: string;
  authUidUtf16LeBase64UrlV1: string;
  generationHash: string;
  acceptedLifecycleEpochV2: number;
  lifecycleStateV1: "deleting";
  internalJobId: string;
  associationIdV1: string | null;
  generationProvenanceVerifiedV1: true;
  liveMixedDocumentV1: false;
  custodyStateV1: Ad05cCustodyStateV1;
  custodyProofFingerprintV1: string | null;
  accountBindingPresentV1: boolean;
  grantingAuthorityV1: boolean;
  sharedFactsPreservedV1: true;
  completedOutcomesPreservedV1: true;
  dispositionStateV1: Ad05cDispositionStateV1;
  recordVersionV1: string;
  recordFingerprintV1: string;
}

export function ad05cFieldOwnedRecordFingerprintV1(value: Omit<
  CandidateAd05cFieldOwnedRecordV1, "recordFingerprintV1"
>): string {
  return canonicalSha256({
    contract: "account-deletion-ad05c-field-owned-record-v1",
    ...value,
  });
}

function custodyState(value: unknown): Ad05cCustodyStateV1 {
  if (value !== "notRequired" && value !== "ownerDepartureComplete" &&
      value !== "custodySuspended") ad05FailV1("AD05_INVALID_RECORD");
  return value;
}

function dispositionState(value: unknown): Ad05cDispositionStateV1 {
  if (value !== "active" && value !== "erased" && value !== "detached" &&
      value !== "revoked") ad05FailV1("AD05_INVALID_RECORD");
  return value;
}

export function parseCandidateAd05cFieldOwnedRecordV1(
  value: unknown,
): CandidateAd05cFieldOwnedRecordV1 {
  const data = exact(value, [
    "schemaVersion", "adapterIdV1", "authProjectIdV2", "authTenantIdV2",
    "authUidV2", "authUidUtf16LeBase64UrlV1", "generationHash",
    "acceptedLifecycleEpochV2", "lifecycleStateV1", "internalJobId",
    "associationIdV1", "generationProvenanceVerifiedV1",
    "liveMixedDocumentV1", "custodyStateV1", "custodyProofFingerprintV1",
    "accountBindingPresentV1", "grantingAuthorityV1",
    "sharedFactsPreservedV1", "completedOutcomesPreservedV1",
    "dispositionStateV1", "recordVersionV1", "recordFingerprintV1",
  ]);
  const parsedAdapter = adapterId(data.adapterIdV1);
  if (!ad05cTransactionalAdapterIdsV1.includes(
    parsedAdapter as Ad05cTransactionalAdapterIdV1,
  ) || data.schemaVersion !== 1 || data.lifecycleStateV1 !== "deleting" ||
      data.generationProvenanceVerifiedV1 !== true ||
      data.liveMixedDocumentV1 !== false ||
      typeof data.accountBindingPresentV1 !== "boolean" ||
      typeof data.grantingAuthorityV1 !== "boolean" ||
      data.sharedFactsPreservedV1 !== true ||
      data.completedOutcomesPreservedV1 !== true) {
    ad05FailV1("AD05_INVALID_RECORD");
  }
  const scope = ad04ScopeV1(data);
  const custody = custodyState(data.custodyStateV1);
  const custodyProof = data.custodyProofFingerprintV1 === null ? null :
    ad04HashV1(data.custodyProofFingerprintV1);
  if ((custody === "notRequired") !== (custodyProof === null)) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  const candidate: CandidateAd05cFieldOwnedRecordV1 = Object.freeze({
    schemaVersion: 1,
    adapterIdV1: parsedAdapter as Ad05cTransactionalAdapterIdV1,
    ...scope,
    authUidUtf16LeBase64UrlV1: ad04OpaqueIdV1(
      data.authUidUtf16LeBase64UrlV1,
    ),
    generationHash: ad04HashV1(data.generationHash),
    acceptedLifecycleEpochV2: ad04CounterV1(data.acceptedLifecycleEpochV2),
    lifecycleStateV1: "deleting",
    internalJobId: ad04OpaqueIdV1(data.internalJobId),
    associationIdV1: data.associationIdV1 === null ? null :
      ad04OpaqueIdV1(data.associationIdV1),
    generationProvenanceVerifiedV1: true,
    liveMixedDocumentV1: false,
    custodyStateV1: custody,
    custodyProofFingerprintV1: custodyProof,
    accountBindingPresentV1: data.accountBindingPresentV1,
    grantingAuthorityV1: data.grantingAuthorityV1,
    sharedFactsPreservedV1: true,
    completedOutcomesPreservedV1: true,
    dispositionStateV1: dispositionState(data.dispositionStateV1),
    recordVersionV1: ad04OpaqueIdV1(data.recordVersionV1),
    recordFingerprintV1: ad04HashV1(data.recordFingerprintV1),
  });
  if (candidate.authUidUtf16LeBase64UrlV1 !==
      firebaseUidUtf16LeBase64Url(candidate.authUidV2) ||
      (candidate.dispositionStateV1 === "active") !==
        candidate.accountBindingPresentV1 ||
      (candidate.dispositionStateV1 !== "active" &&
        candidate.grantingAuthorityV1)) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  const {recordFingerprintV1, ...fingerprintInput} = candidate;
  if (recordFingerprintV1 !==
      ad05cFieldOwnedRecordFingerprintV1(fingerprintInput)) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  return candidate;
}

export type Ad05cEvidenceStateV1 =
  "exactGenerationAbsent" | "restrictedRetentionVerified" |
  "sharedAttributionDetached" | "completedAcknowledgementPreserved" |
  "verifiedNotApplicable";

export interface CandidateAd05cEvidenceRecordV1 {
  schemaVersion: 1;
  adapterIdV1: Ad05cEvidenceOnlyAdapterIdV1 | "notification_inbox";
  authProjectIdV2: string;
  authTenantIdV2: string | null;
  authUidV2: string;
  authUidUtf16LeBase64UrlV1: string;
  generationHash: string;
  acceptedLifecycleEpochV2: number;
  lifecycleStateV1: "deleting";
  internalJobId: string;
  associationIdV1: string | null;
  generationProvenanceVerifiedV1: true;
  evidenceStateV1: Ad05cEvidenceStateV1;
  mutationAllowedV1: false;
  grantingAuthorityV1: false;
  sharedFactsPreservedV1: true;
  evidenceIdV1: string;
  verifiedAtSecV1: number;
  recordVersionV1: string;
  evidenceFingerprintV1: string;
}

export function ad05cEvidenceRecordFingerprintV1(value: Omit<
  CandidateAd05cEvidenceRecordV1, "evidenceFingerprintV1"
>): string {
  return canonicalSha256({
    contract: "account-deletion-ad05c-evidence-record-v1",
    ...value,
  });
}

function evidenceState(value: unknown): Ad05cEvidenceStateV1 {
  if (value !== "exactGenerationAbsent" &&
      value !== "restrictedRetentionVerified" &&
      value !== "sharedAttributionDetached" &&
      value !== "completedAcknowledgementPreserved" &&
      value !== "verifiedNotApplicable") ad05FailV1("AD05_INVALID_RECORD");
  return value;
}

export function parseCandidateAd05cEvidenceRecordV1(
  value: unknown,
): CandidateAd05cEvidenceRecordV1 {
  const data = exact(value, [
    "schemaVersion", "adapterIdV1", "authProjectIdV2", "authTenantIdV2",
    "authUidV2", "authUidUtf16LeBase64UrlV1", "generationHash",
    "acceptedLifecycleEpochV2", "lifecycleStateV1", "internalJobId",
    "associationIdV1", "generationProvenanceVerifiedV1", "evidenceStateV1",
    "mutationAllowedV1", "grantingAuthorityV1", "sharedFactsPreservedV1",
    "evidenceIdV1", "verifiedAtSecV1", "recordVersionV1",
    "evidenceFingerprintV1",
  ]);
  const parsedAdapter = adapterId(data.adapterIdV1);
  if ((!ad05cEvidenceOnlyAdapterIdsV1.includes(
    parsedAdapter as Ad05cEvidenceOnlyAdapterIdV1,
  ) && parsedAdapter !== "notification_inbox") ||
      data.schemaVersion !== 1 || data.lifecycleStateV1 !== "deleting" ||
      data.generationProvenanceVerifiedV1 !== true ||
      data.mutationAllowedV1 !== false || data.grantingAuthorityV1 !== false ||
      data.sharedFactsPreservedV1 !== true) {
    ad05FailV1("AD05_INVALID_RECORD");
  }
  const scope = ad04ScopeV1(data);
  const state = evidenceState(data.evidenceStateV1);
  const candidate: CandidateAd05cEvidenceRecordV1 = Object.freeze({
    schemaVersion: 1,
    adapterIdV1: parsedAdapter as CandidateAd05cEvidenceRecordV1["adapterIdV1"],
    ...scope,
    authUidUtf16LeBase64UrlV1: ad04OpaqueIdV1(
      data.authUidUtf16LeBase64UrlV1,
    ),
    generationHash: ad04HashV1(data.generationHash),
    acceptedLifecycleEpochV2: ad04CounterV1(data.acceptedLifecycleEpochV2),
    lifecycleStateV1: "deleting",
    internalJobId: ad04OpaqueIdV1(data.internalJobId),
    associationIdV1: data.associationIdV1 === null ? null :
      ad04OpaqueIdV1(data.associationIdV1),
    generationProvenanceVerifiedV1: true,
    evidenceStateV1: state,
    mutationAllowedV1: false,
    grantingAuthorityV1: false,
    sharedFactsPreservedV1: true,
    evidenceIdV1: ad04OpaqueIdV1(data.evidenceIdV1),
    verifiedAtSecV1: ad04CounterV1(data.verifiedAtSecV1),
    recordVersionV1: ad04OpaqueIdV1(data.recordVersionV1),
    evidenceFingerprintV1: ad04HashV1(data.evidenceFingerprintV1),
  });
  const expectedState: Readonly<Record<
    CandidateAd05cEvidenceRecordV1["adapterIdV1"], Ad05cEvidenceStateV1
  >> = {
    firebase_auth_identity: "exactGenerationAbsent",
    historical_invites: "restrictedRetentionVerified",
    authorization_evidence: "restrictedRetentionVerified",
    official_notices: "sharedAttributionDetached",
    acknowledgements: "completedAcknowledgementPreserved",
    event_attribution: "sharedAttributionDetached",
    notification_inbox: "verifiedNotApplicable",
  };
  if (candidate.authUidUtf16LeBase64UrlV1 !==
      firebaseUidUtf16LeBase64Url(candidate.authUidV2) ||
      state !== expectedState[candidate.adapterIdV1]) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  const {evidenceFingerprintV1, ...fingerprintInput} = candidate;
  if (evidenceFingerprintV1 !==
      ad05cEvidenceRecordFingerprintV1(fingerprintInput)) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  return candidate;
}

export function assertCandidateAd05cRecordMatchesBindingV1(input: {
  bindingV1: CandidateAd05ExecutionBindingV1;
  recordV1: CandidateAd05cFieldOwnedRecordV1 | CandidateAd05cEvidenceRecordV1;
}): void {
  const binding = assertCandidateAd05cBindingV1(input.bindingV1);
  const record = input.recordV1.adapterIdV1 === "notification_inbox" ||
      ad05cEvidenceOnlyAdapterIdsV1.includes(
        input.recordV1.adapterIdV1 as Ad05cEvidenceOnlyAdapterIdV1,
      ) ? parseCandidateAd05cEvidenceRecordV1(input.recordV1) :
    parseCandidateAd05cFieldOwnedRecordV1(input.recordV1);
  if (record.adapterIdV1 !== binding.adapterIdV1 ||
      !sameAd04ScopeV1(record, binding) ||
      record.authUidUtf16LeBase64UrlV1 !==
        binding.authUidUtf16LeBase64UrlV1 ||
      record.generationHash !== binding.generationHash ||
      record.acceptedLifecycleEpochV2 !== binding.acceptedLifecycleEpochV2 ||
      record.internalJobId !== binding.internalJobId) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
}
