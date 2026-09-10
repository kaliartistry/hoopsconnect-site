import {canonicalSha256} from "../domain/official_stats_contract";
import {
  CandidateAd05ItemEffectResultV1,
  CandidateAd05SourceMutationV1,
  CandidateAd05TransactionV1,
  CandidateAd05TransactionRepositoryV1,
  CandidateAd05TransactionalDocumentEffectV1,
  applyCandidateAd05TransactionalDocumentItemV1,
} from "./ad05_effects";
import {
  CandidateAd05ExecutionBindingV1,
  CandidateAd05ManifestItemV1,
  CandidateAd05SealedManifestV1,
  ad05ItemReceiptPathV1,
  ad05FailV1,
  parseCandidateAd05ManifestItemV1,
  parseCandidateAd05SealedManifestV1,
} from "./ad05_records";
import {ad04CounterV1, ad04HashV1, ad04OpaqueIdV1} from "./ad04_records";
import {
  deterministicAd05ManifestItemIdV1,
  requireCandidateAd05CanonicalManifestV1,
} from "./ad05_inventory";
import {
  ownerDepartureReceiptPathV2,
  parseOwnerDepartureReceiptV2,
} from "../domain/association_ownership_ad03_v2";
import {
  Ad05cAdapterIdV1,
  Ad05cEvidenceOnlyAdapterIdV1,
  Ad05cTransactionalAdapterIdV1,
  CandidateAd05cEvidenceRecordV1,
  CandidateAd05cFieldOwnedRecordV1,
  ad05cEvidenceOnlyAdapterIdsV1,
  ad05cEvidenceRecordFingerprintV1,
  ad05cFieldOwnedRecordFingerprintV1,
  ad05cTransactionalAdapterIdsV1,
  assertCandidateAd05cBindingV1,
  assertCandidateAd05cRecordMatchesBindingV1,
  parseCandidateAd05cEvidenceRecordV1,
  parseCandidateAd05cFieldOwnedRecordV1,
} from "./ad05_account_shared_workflow_records";

export interface CandidateAd05cDormantPlanV1 {
  stateV1: "blocked";
  evidenceCodeV1: "authoritative_policy_not_approved";
  writesAllowedV1: false;
}

export function createDormantCandidateAd05cPlanV1():
CandidateAd05cDormantPlanV1 {
  return Object.freeze({
    stateV1: "blocked",
    evidenceCodeV1: "authoritative_policy_not_approved",
    writesAllowedV1: false,
  });
}

const fieldSchemaByAdapterV1: Readonly<Record<
  Ad05cTransactionalAdapterIdV1, string
>> = Object.freeze({
  user_profile: "account_profile_field_owned_v1",
  memberships_capabilities: "account_membership_authority_v1",
  team_assignments: "account_team_assignment_v1",
  pending_invites: "account_pending_invite_v1",
  personal_ugc: "account_personal_ugc_v1",
});

const evidenceSchemaByAdapterV1: Readonly<Record<
  CandidateAd05cEvidenceRecordV1["adapterIdV1"], string
>> = Object.freeze({
  firebase_auth_identity: "firebase_auth_absence_v1",
  notification_inbox: "notification_inbox_absence_v1",
  historical_invites: "historical_invite_evidence_v1",
  authorization_evidence: "authorization_evidence_v1",
  official_notices: "official_notice_attribution_evidence_v1",
  acknowledgements: "acknowledgement_preservation_evidence_v1",
  event_attribution: "event_attribution_evidence_v1",
});

function assertItemBindsRecordV1(input: {
  itemV1: CandidateAd05ManifestItemV1;
  recordV1: CandidateAd05cFieldOwnedRecordV1 | CandidateAd05cEvidenceRecordV1;
  schemaIdV1: string;
}): CandidateAd05ManifestItemV1 {
  const item = parseCandidateAd05ManifestItemV1(input.itemV1);
  const record = input.recordV1;
  const associationHash = record.associationIdV1 === null ? null :
    canonicalSha256(record.associationIdV1);
  if (item.adapterIdV1 !== record.adapterIdV1 ||
      item.sourceSchemaIdV1 !== input.schemaIdV1 ||
      item.sourceSchemaVersionV1 !== "schema_v1" ||
      item.sourceRecordVersionV1 !== record.recordVersionV1 ||
      item.sourceDocumentPathHashV1 !== record.sourceDocumentPathHashV1 ||
      item.provenanceIdV1 !== record.provenanceIdV1 ||
      item.associationScopeHashV1 !== associationHash) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  return item;
}

async function assertPersistedCustodyV1(input: {
  recordV1: CandidateAd05cFieldOwnedRecordV1;
  transactionV1: CandidateAd05TransactionV1;
}): Promise<void> {
  const record = input.recordV1;
  const custodyRequired = record.adapterIdV1 === "memberships_capabilities" ||
    record.adapterIdV1 === "team_assignments";
  if (!custodyRequired) {
    if (record.custodyStateV1 !== "notRequired") {
      ad05FailV1("AD05_BINDING_CONFLICT");
    }
    return;
  }
  if (record.custodyStateV1 === "notRequired" ||
      record.associationIdV1 === null ||
      record.custodyDepartureOperationIdV2 === null ||
      record.custodyProofFingerprintV1 === null) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  const receiptPath = ownerDepartureReceiptPathV2({
    authProjectIdV2: record.authProjectIdV2,
    authTenantIdV2: record.authTenantIdV2,
    associationId: record.associationIdV1,
  }, record.custodyDepartureOperationIdV2);
  const receiptRaw = await input.transactionV1.read(receiptPath);
  if (receiptRaw === null) ad05FailV1("AD05_BINDING_CONFLICT");
  let receipt;
  try {
    receipt = parseOwnerDepartureReceiptV2(receiptRaw);
  } catch {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  const completed = record.custodyStateV1 === "ownerDepartureComplete" &&
    (receipt.outcomeV2 === "ordinary" ||
      receipt.outcomeV2 === "transferThenDelete") &&
    receipt.custodyStateV2 === "operating";
  const suspended = record.custodyStateV1 === "custodySuspended" &&
    ((receipt.outcomeV2 === "suspendToCustody" &&
      receipt.custodyStateV2 === "suspendedToCustody") ||
     (receipt.outcomeV2 ===
        "policyBlockedButDeletionMustReceiveOperationalResolution" &&
      receipt.custodyStateV2 === "custodyRequired"));
  if (receipt.authProjectIdV2 !== record.authProjectIdV2 ||
      receipt.authTenantIdV2 !== record.authTenantIdV2 ||
      receipt.authUidV2 !== record.authUidV2 ||
      receipt.associationId !== record.associationIdV1 ||
      receipt.accountGenerationV2 !== record.generationHash ||
      receipt.accountLifecycleEpochV2 !== record.acceptedLifecycleEpochV2 ||
      receipt.departureOperationIdV2 !==
        record.custodyDepartureOperationIdV2 ||
      canonicalSha256(receipt) !== record.custodyProofFingerprintV1 ||
      (!completed && !suspended)) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
}

function assertExactManifestMemberV1(input: {
  bindingV1: CandidateAd05ExecutionBindingV1;
  manifestV1: CandidateAd05SealedManifestV1;
  itemV1: CandidateAd05ManifestItemV1;
}): void {
  const member = input.manifestV1.itemsV1[input.itemV1.ordinalV1];
  const expectedItemId = deterministicAd05ManifestItemIdV1({
    binding: input.bindingV1,
    record: {
      schemaVersion: 1,
      adapterIdV1: input.itemV1.adapterIdV1,
      sourceSchemaIdV1: input.itemV1.sourceSchemaIdV1,
      sourceSchemaVersionV1: input.itemV1.sourceSchemaVersionV1,
      sourceDocumentPathV1: input.itemV1.sourceDocumentPathV1,
      sourceRecordVersionV1: input.itemV1.sourceRecordVersionV1,
      provenanceIdV1: input.itemV1.provenanceIdV1,
      associationScopeHashV1: input.itemV1.associationScopeHashV1,
      classificationV1: input.itemV1.classificationV1,
    },
  });
  if (member === undefined ||
      member.itemIdV1 !== input.itemV1.itemIdV1 ||
      member.itemFingerprintV1 !== input.itemV1.itemFingerprintV1 ||
      canonicalSha256(member) !== canonicalSha256(input.itemV1) ||
      input.itemV1.itemIdV1 !== expectedItemId) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
}

function dispositionForAdapterV1(
  adapterIdV1: Ad05cTransactionalAdapterIdV1,
): CandidateAd05cFieldOwnedRecordV1["dispositionStateV1"] {
  if (adapterIdV1 === "memberships_capabilities" ||
      adapterIdV1 === "pending_invites") return "revoked";
  if (adapterIdV1 === "team_assignments") return "detached";
  return "erased";
}

function createFieldOwnedEffectV1(input: {
  bindingV1: CandidateAd05ExecutionBindingV1;
  sourceRecordVersionAfterV1: string;
}): CandidateAd05TransactionalDocumentEffectV1 {
  const binding = assertCandidateAd05cBindingV1(input.bindingV1);
  if (!ad05cTransactionalAdapterIdsV1.includes(
    binding.adapterIdV1 as Ad05cTransactionalAdapterIdV1,
  )) ad05FailV1("AD05_UNSUPPORTED");
  const adapter = binding.adapterIdV1 as Ad05cTransactionalAdapterIdV1;
  const afterVersion = ad04OpaqueIdV1(input.sourceRecordVersionAfterV1);
  return Object.freeze({
    sourceRecordVersionV1: (value: unknown) =>
      parseCandidateAd05cFieldOwnedRecordV1(value).recordVersionV1,
    mutateBoundSourceV1: ({item, transaction}: {
      binding: CandidateAd05ExecutionBindingV1;
      item: CandidateAd05ManifestItemV1;
      transaction: CandidateAd05SourceMutationV1;
    }) => {
      const before = parseCandidateAd05cFieldOwnedRecordV1(
        transaction.sourceRecordBeforeV1,
      );
      assertCandidateAd05cRecordMatchesBindingV1({
        bindingV1: binding,
        recordV1: before,
      });
      assertItemBindsRecordV1({
        itemV1: item,
        recordV1: before,
        schemaIdV1: fieldSchemaByAdapterV1[adapter],
      });
      if (before.dispositionStateV1 !== "active" ||
          before.accountBindingPresentV1 !== true ||
          afterVersion === before.recordVersionV1) {
        ad05FailV1("AD05_BINDING_CONFLICT");
      }
      const {recordFingerprintV1: _priorFingerprintV1, ...beforeCore} = before;
      const core = {
        ...beforeCore,
        accountBindingPresentV1: false,
        grantingAuthorityV1: false,
        dispositionStateV1: dispositionForAdapterV1(adapter),
        recordVersionV1: afterVersion,
      } as Omit<CandidateAd05cFieldOwnedRecordV1, "recordFingerprintV1">;
      const after = parseCandidateAd05cFieldOwnedRecordV1({
        ...core,
        recordFingerprintV1: ad05cFieldOwnedRecordFingerprintV1(core),
      });
      transaction.writeSourceV1(
        after as unknown as Readonly<Record<string, unknown>>,
      );
      return Object.freeze({
        schemaVersion: 1,
        sourceRecordVersionAfterV1: afterVersion,
        evidenceCodeV1: `ad05c_${adapter}_${after.dispositionStateV1}`,
      });
    },
  });
}

export async function applyTestOnlySyntheticCandidateAd05cItemV1(input: {
  repository: CandidateAd05TransactionRepositoryV1;
  bindingV1: CandidateAd05ExecutionBindingV1;
  manifestV1: CandidateAd05SealedManifestV1;
  itemV1: CandidateAd05ManifestItemV1;
  sourceRecordVersionAfterV1: string;
  committedAtSecV1: number;
}): Promise<CandidateAd05ItemEffectResultV1> {
  const binding = assertCandidateAd05cBindingV1(input.bindingV1);
  if (!ad05cTransactionalAdapterIdsV1.includes(
    binding.adapterIdV1 as Ad05cTransactionalAdapterIdV1,
  )) ad05FailV1("AD05_UNSUPPORTED");
  const manifest = parseCandidateAd05SealedManifestV1(input.manifestV1);
  const item = parseCandidateAd05ManifestItemV1(input.itemV1);
  if (item.classificationV1 !== "applicable") {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  const guardedRepository: CandidateAd05TransactionRepositoryV1 = {
    read: (path: string) => input.repository.read(path),
    runTransaction: <T>(operation: (
      transaction: CandidateAd05TransactionV1,
    ) => Promise<T>) => input.repository.runTransaction(async (transaction) => {
      const existingReceipt = await transaction.read(ad05ItemReceiptPathV1({
        binding,
        itemIdV1: item.itemIdV1,
      }));
      if (existingReceipt !== null) return operation(transaction);
      const sourceRaw = await transaction.read(item.sourceDocumentPathV1);
      if (sourceRaw === null) ad05FailV1("AD05_BINDING_CONFLICT");
      const source = parseCandidateAd05cFieldOwnedRecordV1(sourceRaw);
      assertCandidateAd05cRecordMatchesBindingV1({
        bindingV1: binding,
        recordV1: source,
      });
      assertItemBindsRecordV1({
        itemV1: item,
        recordV1: source,
        schemaIdV1: fieldSchemaByAdapterV1[
          binding.adapterIdV1 as Ad05cTransactionalAdapterIdV1
        ],
      });
      await assertPersistedCustodyV1({
        recordV1: source,
        transactionV1: transaction,
      });
      return operation(transaction);
    }),
  };
  return applyCandidateAd05TransactionalDocumentItemV1({
    repository: guardedRepository,
    binding,
    manifest,
    item,
    effect: createFieldOwnedEffectV1({
      bindingV1: binding,
      sourceRecordVersionAfterV1: input.sourceRecordVersionAfterV1,
    }),
    committedAtSecV1: ad04CounterV1(input.committedAtSecV1),
  });
}

export interface CandidateAd05cEvidenceResultV1 {
  stateV1: "verified";
  adapterIdV1: CandidateAd05cEvidenceRecordV1["adapterIdV1"];
  evidenceIdV1: string;
  evidenceFingerprintV1: string;
  mutationRequestedV1: false;
  grantingAuthorityV1: false;
  sharedFactsPreservedV1: true;
}

export async function verifyTestOnlySyntheticCandidateAd05cEvidenceV1(input: {
  repository: CandidateAd05TransactionRepositoryV1;
  bindingV1: CandidateAd05ExecutionBindingV1;
  manifestV1: CandidateAd05SealedManifestV1;
  itemV1: CandidateAd05ManifestItemV1;
  evidenceV1: CandidateAd05cEvidenceRecordV1;
}): Promise<CandidateAd05cEvidenceResultV1> {
  const binding = assertCandidateAd05cBindingV1(input.bindingV1);
  const manifest = parseCandidateAd05SealedManifestV1(input.manifestV1);
  const item = parseCandidateAd05ManifestItemV1(input.itemV1);
  const canonicalManifest = await requireCandidateAd05CanonicalManifestV1({
    repository: input.repository,
    binding,
    manifest,
  });
  assertExactManifestMemberV1({
    bindingV1: binding,
    manifestV1: canonicalManifest,
    itemV1: item,
  });
  const evidence = parseCandidateAd05cEvidenceRecordV1(input.evidenceV1);
  assertCandidateAd05cRecordMatchesBindingV1({
    bindingV1: binding,
    recordV1: evidence,
  });
  assertItemBindsRecordV1({
    itemV1: item,
    recordV1: evidence,
    schemaIdV1: evidenceSchemaByAdapterV1[evidence.adapterIdV1],
  });
  const notificationAbsence = evidence.adapterIdV1 === "notification_inbox";
  if (notificationAbsence !== (item.classificationV1 === "notApplicable") ||
      (!notificationAbsence && !ad05cEvidenceOnlyAdapterIdsV1.includes(
        evidence.adapterIdV1 as Ad05cEvidenceOnlyAdapterIdV1,
      ))) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  return Object.freeze({
    stateV1: "verified",
    adapterIdV1: evidence.adapterIdV1,
    evidenceIdV1: evidence.evidenceIdV1,
    evidenceFingerprintV1: evidence.evidenceFingerprintV1,
    mutationRequestedV1: false,
    grantingAuthorityV1: false,
    sharedFactsPreservedV1: true,
  });
}

export function candidateAd05cMechanicalSupportV1(
  adapterIdV1: Ad05cAdapterIdV1,
): Readonly<{stateV1: "ready" | "evidenceOnly" | "notApplicableOnly"}> {
  if (adapterIdV1 === "notification_inbox") {
    return Object.freeze({stateV1: "notApplicableOnly"});
  }
  if (ad05cEvidenceOnlyAdapterIdsV1.includes(
    adapterIdV1 as Ad05cEvidenceOnlyAdapterIdV1,
  )) return Object.freeze({stateV1: "evidenceOnly"});
  if (ad05cTransactionalAdapterIdsV1.includes(
    adapterIdV1 as Ad05cTransactionalAdapterIdV1,
  )) return Object.freeze({stateV1: "ready"});
  ad05FailV1("AD05_UNSUPPORTED");
}

export function candidateAd05cEvidenceFingerprintMatchesV1(
  evidenceV1: CandidateAd05cEvidenceRecordV1,
): boolean {
  const parsed = parseCandidateAd05cEvidenceRecordV1(evidenceV1);
  const {evidenceFingerprintV1, ...core} = parsed;
  return ad04HashV1(evidenceFingerprintV1) ===
    ad05cEvidenceRecordFingerprintV1(core);
}
