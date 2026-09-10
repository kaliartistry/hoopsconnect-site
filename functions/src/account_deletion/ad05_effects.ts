import {AdapterResultContract, validateAdapterResult} from
  "../domain/account_deletion_contract";
import {canonicalSha256} from "../domain/official_stats_contract";
import {
  ACCOUNT_DELETION_AD05_MAX_PAGE_ITEMS_V1,
  CandidateAd05ContinuationV1,
  CandidateAd05ExecutionBindingV1,
  CandidateAd05ItemReceiptV1,
  CandidateAd05ManifestItemV1,
  CandidateAd05SealedManifestV1,
  ad05ContinuationFingerprintV1,
  ad05FailV1,
  ad05ItemReceiptFingerprintV1,
  ad05ItemReceiptPathV1,
  ad05PrivateEvidenceRefV1,
  assertCandidateAd05ManifestBindingV1,
  parseCandidateAd05ContinuationV1,
  parseCandidateAd05ExecutionBindingV1,
  parseCandidateAd05ItemReceiptV1,
  parseCandidateAd05ManifestItemV1,
  parseCandidateAd05SealedManifestV1,
} from "./ad05_records";
import {
  CandidateAd05RemainingReferenceEvidenceV1,
  CandidateAd05RemainingReferenceVerifierV1,
  CandidateAd05ReceiptSetSummaryV1,
  deterministicAd05ManifestItemIdV1,
  requireCandidateAd05CanonicalManifestV1,
  verifyCandidateAd05RemainingReferencesV1,
} from "./ad05_inventory";
import {
  ad04CounterV1,
  ad04ExactKeysV1,
  ad04HashV1,
  ad04OpaqueIdV1,
  ad04RecordV1,
  sameAd04ScopeV1,
} from "./ad04_records";

export interface CandidateAd05TransactionV1 {
  read(path: string): Promise<unknown | null>;
  write(path: string, value: Readonly<Record<string, unknown>>): void;
}

export interface CandidateAd05TransactionRepositoryV1 {
  read(path: string): Promise<unknown | null>;
  runTransaction<T>(
    operation: (transaction: CandidateAd05TransactionV1) => Promise<T>,
  ): Promise<T>;
}

export interface CandidateAd05SourceMutationV1 {
  readonly sourcePathV1: string;
  readonly sourceRecordBeforeV1: unknown;
  writeSourceV1(value: Readonly<Record<string, unknown>>): void;
}

export interface CandidateAd05TransactionalDocumentEffectV1 {
  sourceRecordVersionV1(value: unknown): string;
  mutateBoundSourceV1(input: {
    binding: CandidateAd05ExecutionBindingV1;
    item: CandidateAd05ManifestItemV1;
    transaction: CandidateAd05SourceMutationV1;
  }): Promise<unknown> | unknown;
}

interface CandidateAd05MutationEvidenceV1 {
  schemaVersion: 1;
  sourceRecordVersionAfterV1: string;
  evidenceCodeV1: string;
}

export interface CandidateAd05ItemEffectResultV1 {
  stateV1: "committed" | "replayed";
  receiptV1: CandidateAd05ItemReceiptV1;
}

function writeRecord(value: object): Readonly<Record<string, unknown>> {
  return value as unknown as Readonly<Record<string, unknown>>;
}

function mutationEvidenceV1(value: unknown): CandidateAd05MutationEvidenceV1 {
  const data = ad04RecordV1(value);
  if (data === null || !ad04ExactKeysV1(data, [
    "schemaVersion", "sourceRecordVersionAfterV1", "evidenceCodeV1",
  ]) || data.schemaVersion !== 1) ad05FailV1("AD05_INVALID_RECORD");
  return Object.freeze({
    schemaVersion: 1,
    sourceRecordVersionAfterV1: ad04OpaqueIdV1(data.sourceRecordVersionAfterV1),
    evidenceCodeV1: ad04OpaqueIdV1(data.evidenceCodeV1),
  });
}

function receiptMatchesV1(input: {
  receipt: CandidateAd05ItemReceiptV1;
  binding: CandidateAd05ExecutionBindingV1;
  manifestFingerprintV1: string;
  item: CandidateAd05ManifestItemV1;
}): boolean {
  const {receipt, binding, manifestFingerprintV1, item} = input;
  return sameAd04ScopeV1(receipt, binding) &&
    receipt.internalJobId === binding.internalJobId &&
    receipt.taskEffectIdV1 === binding.taskEffectIdV1 &&
    receipt.itemIdV1 === item.itemIdV1 &&
    receipt.bindingFingerprintV1 === binding.bindingFingerprintV1 &&
    receipt.manifestFingerprintV1 === manifestFingerprintV1 &&
    receipt.itemFingerprintV1 === item.itemFingerprintV1 &&
    receipt.adapterIdV1 === binding.adapterIdV1 &&
    receipt.effectVersionV1 === binding.effectVersionV1 &&
    receipt.policyDecisionIdV1 === binding.policyDecisionIdV1 &&
    receipt.policyVersionV1 === binding.policyVersionV1 &&
    receipt.actionV1 === binding.actionV1 &&
    receipt.classificationV1 === item.classificationV1 &&
    receipt.outcomeV1 === (item.classificationV1 === "applicable" ?
      "mutated" : "notApplicableVerified") &&
    receipt.sourceRecordVersionBeforeV1 === item.sourceRecordVersionV1;
}

function assertExactManifestMemberV1(
  manifest: CandidateAd05SealedManifestV1,
  item: CandidateAd05ManifestItemV1,
): void {
  const member = manifest.itemsV1[item.ordinalV1];
  if (member === undefined || member.itemIdV1 !== item.itemIdV1 ||
      member.itemFingerprintV1 !== item.itemFingerprintV1 ||
      canonicalSha256(member) !== canonicalSha256(item)) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
}

export async function applyCandidateAd05TransactionalDocumentItemV1(input: {
  repository: CandidateAd05TransactionRepositoryV1;
  binding: CandidateAd05ExecutionBindingV1;
  manifest: CandidateAd05SealedManifestV1;
  item: CandidateAd05ManifestItemV1;
  effect: CandidateAd05TransactionalDocumentEffectV1;
  committedAtSecV1: number;
}): Promise<CandidateAd05ItemEffectResultV1> {
  const binding = parseCandidateAd05ExecutionBindingV1(input.binding);
  const manifest = parseCandidateAd05SealedManifestV1(input.manifest);
  const item = parseCandidateAd05ManifestItemV1(input.item);
  const committedAtSecV1 = ad04CounterV1(input.committedAtSecV1);
  assertCandidateAd05ManifestBindingV1({binding, manifest});
  assertExactManifestMemberV1(manifest, item);
  const expectedItemIdV1 = deterministicAd05ManifestItemIdV1({
    binding,
    record: {
      schemaVersion: 1,
      adapterIdV1: item.adapterIdV1,
      sourceSchemaIdV1: item.sourceSchemaIdV1,
      sourceSchemaVersionV1: item.sourceSchemaVersionV1,
      sourceDocumentPathV1: item.sourceDocumentPathV1,
      sourceRecordVersionV1: item.sourceRecordVersionV1,
      provenanceIdV1: item.provenanceIdV1,
      associationScopeHashV1: item.associationScopeHashV1,
      classificationV1: item.classificationV1,
    },
  });
  if (item.adapterIdV1 !== binding.adapterIdV1 ||
      item.itemIdV1 !== expectedItemIdV1) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  const receiptPath = ad05ItemReceiptPathV1({binding, itemIdV1: item.itemIdV1});
  return input.repository.runTransaction(async (transaction) => {
    const canonicalManifest = await requireCandidateAd05CanonicalManifestV1({
      repository: transaction,
      binding,
      manifest,
    });
    assertExactManifestMemberV1(canonicalManifest, item);
    const [receiptRaw, sourceRaw] = await Promise.all([
      transaction.read(receiptPath),
      transaction.read(item.sourceDocumentPathV1),
    ]);
    if (receiptRaw !== null) {
      const receipt = parseCandidateAd05ItemReceiptV1(receiptRaw);
      if (!receiptMatchesV1({
        receipt,
        binding,
        manifestFingerprintV1: canonicalManifest.manifestFingerprintV1,
        item,
      })) {
        ad05FailV1("AD05_BINDING_CONFLICT");
      }
      return Object.freeze({stateV1: "replayed" as const, receiptV1: receipt});
    }
    if (sourceRaw === null ||
        ad04OpaqueIdV1(input.effect.sourceRecordVersionV1(sourceRaw)) !==
        item.sourceRecordVersionV1) {
      ad05FailV1("AD05_BINDING_CONFLICT");
    }
    if (binding.actionV1 === "notApplicable" &&
        item.classificationV1 === "applicable") {
      ad05FailV1("AD05_BINDING_CONFLICT");
    }
    if (item.classificationV1 === "notApplicable") {
      const withoutFingerprint: Omit<CandidateAd05ItemReceiptV1,
        "receiptFingerprintV1"> = {
        schemaVersion: 1,
        authProjectIdV2: binding.authProjectIdV2,
        authTenantIdV2: binding.authTenantIdV2,
        authUidV2: binding.authUidV2,
        internalJobId: binding.internalJobId,
        taskEffectIdV1: binding.taskEffectIdV1,
        itemIdV1: item.itemIdV1,
        bindingFingerprintV1: binding.bindingFingerprintV1,
        manifestFingerprintV1: canonicalManifest.manifestFingerprintV1,
        itemFingerprintV1: item.itemFingerprintV1,
        adapterIdV1: binding.adapterIdV1,
        effectVersionV1: binding.effectVersionV1,
        policyDecisionIdV1: binding.policyDecisionIdV1,
        policyVersionV1: binding.policyVersionV1,
        actionV1: binding.actionV1,
        classificationV1: "notApplicable",
        outcomeV1: "notApplicableVerified",
        sourceRecordVersionBeforeV1: item.sourceRecordVersionV1,
        sourceRecordVersionAfterV1: item.sourceRecordVersionV1,
        evidenceCodeV1: "source_item_not_applicable_verified",
        committedAtSecV1,
      };
      const receipt = parseCandidateAd05ItemReceiptV1({
        ...withoutFingerprint,
        receiptFingerprintV1: ad05ItemReceiptFingerprintV1(withoutFingerprint),
      });
      transaction.write(receiptPath, writeRecord(receipt));
      return Object.freeze({stateV1: "committed" as const, receiptV1: receipt});
    }
    let sourceWritten = false;
    let sourceRecordAfterV1: Readonly<Record<string, unknown>> | null = null;
    const restrictedTransaction: CandidateAd05SourceMutationV1 = Object.freeze({
      sourcePathV1: item.sourceDocumentPathV1,
      sourceRecordBeforeV1: sourceRaw,
      writeSourceV1: (value: Readonly<Record<string, unknown>>) => {
        if (sourceWritten) ad05FailV1("AD05_BINDING_CONFLICT");
        sourceWritten = true;
        sourceRecordAfterV1 = value;
        transaction.write(item.sourceDocumentPathV1, value);
      },
    });
    const evidence = mutationEvidenceV1(await input.effect.mutateBoundSourceV1({
      binding,
      item,
      transaction: restrictedTransaction,
    }));
    if (!sourceWritten || sourceRecordAfterV1 === null ||
        ad04OpaqueIdV1(input.effect.sourceRecordVersionV1(sourceRecordAfterV1)) !==
        evidence.sourceRecordVersionAfterV1 ||
        evidence.sourceRecordVersionAfterV1 === item.sourceRecordVersionV1) {
      ad05FailV1("AD05_BINDING_CONFLICT");
    }
    const withoutFingerprint: Omit<CandidateAd05ItemReceiptV1,
      "receiptFingerprintV1"> = {
      schemaVersion: 1,
      authProjectIdV2: binding.authProjectIdV2,
      authTenantIdV2: binding.authTenantIdV2,
      authUidV2: binding.authUidV2,
      internalJobId: binding.internalJobId,
      taskEffectIdV1: binding.taskEffectIdV1,
      itemIdV1: item.itemIdV1,
      bindingFingerprintV1: binding.bindingFingerprintV1,
      manifestFingerprintV1: canonicalManifest.manifestFingerprintV1,
      itemFingerprintV1: item.itemFingerprintV1,
      adapterIdV1: binding.adapterIdV1,
      effectVersionV1: binding.effectVersionV1,
      policyDecisionIdV1: binding.policyDecisionIdV1,
      policyVersionV1: binding.policyVersionV1,
      actionV1: binding.actionV1,
      classificationV1: "applicable",
      outcomeV1: "mutated",
      sourceRecordVersionBeforeV1: item.sourceRecordVersionV1,
      sourceRecordVersionAfterV1: evidence.sourceRecordVersionAfterV1,
      evidenceCodeV1: evidence.evidenceCodeV1,
      committedAtSecV1,
    };
    const receipt = parseCandidateAd05ItemReceiptV1({
      ...withoutFingerprint,
      receiptFingerprintV1: ad05ItemReceiptFingerprintV1(withoutFingerprint),
    });
    transaction.write(receiptPath, writeRecord(receipt));
    return Object.freeze({stateV1: "committed" as const, receiptV1: receipt});
  });
}

export function initialCandidateAd05ContinuationV1(input: {
  binding: CandidateAd05ExecutionBindingV1;
  manifest: CandidateAd05SealedManifestV1;
}): CandidateAd05ContinuationV1 {
  const binding = parseCandidateAd05ExecutionBindingV1(input.binding);
  const manifest = parseCandidateAd05SealedManifestV1(input.manifest);
  assertCandidateAd05ManifestBindingV1({binding, manifest});
  return continuationForOrdinalV1(binding, manifest, 0);
}

function continuationForOrdinalV1(
  binding: CandidateAd05ExecutionBindingV1,
  manifest: CandidateAd05SealedManifestV1,
  ordinalV1: number,
): CandidateAd05ContinuationV1 {
  if (ordinalV1 < 0 || ordinalV1 > manifest.itemsV1.length) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  const withoutFingerprint: Omit<CandidateAd05ContinuationV1,
    "continuationFingerprintV1"> = {
    schemaVersion: 1,
    bindingFingerprintV1: binding.bindingFingerprintV1,
    manifestFingerprintV1: manifest.manifestFingerprintV1,
    nextOrdinalV1: ordinalV1,
    nextItemIdV1: manifest.itemsV1[ordinalV1]?.itemIdV1 ?? null,
    committedItemCountV1: ordinalV1,
    completeV1: ordinalV1 === manifest.itemsV1.length,
  };
  return parseCandidateAd05ContinuationV1({
    ...withoutFingerprint,
    continuationFingerprintV1: ad05ContinuationFingerprintV1(withoutFingerprint),
  });
}

export async function applyCandidateAd05TransactionalDocumentPageV1(input: {
  repository: CandidateAd05TransactionRepositoryV1;
  binding: CandidateAd05ExecutionBindingV1;
  manifest: CandidateAd05SealedManifestV1;
  continuation: CandidateAd05ContinuationV1;
  effect: CandidateAd05TransactionalDocumentEffectV1;
  committedAtSecV1: number;
  pageLimitV1?: number;
  afterItemCommitV1?(itemIdV1: string): Promise<void> | void;
}): Promise<CandidateAd05ContinuationV1> {
  const binding = parseCandidateAd05ExecutionBindingV1(input.binding);
  const manifest = parseCandidateAd05SealedManifestV1(input.manifest);
  let continuation = parseCandidateAd05ContinuationV1(input.continuation);
  const pageLimitV1 = input.pageLimitV1 === undefined ?
    ACCOUNT_DELETION_AD05_MAX_PAGE_ITEMS_V1 : ad04CounterV1(input.pageLimitV1);
  assertCandidateAd05ManifestBindingV1({binding, manifest});
  await requireCandidateAd05CanonicalManifestV1({
    repository: input.repository,
    binding,
    manifest,
  });
  if (pageLimitV1 < 1 || pageLimitV1 > ACCOUNT_DELETION_AD05_MAX_PAGE_ITEMS_V1 ||
      continuation.bindingFingerprintV1 !== binding.bindingFingerprintV1 ||
      continuation.manifestFingerprintV1 !== manifest.manifestFingerprintV1 ||
      continuation.nextOrdinalV1 > manifest.itemsV1.length ||
      continuation.nextItemIdV1 !==
        (manifest.itemsV1[continuation.nextOrdinalV1]?.itemIdV1 ?? null)) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  // A cursor is only a bounded hint. Receipts, not a caller-recomputable
  // cursor fingerprint, prove that every earlier item committed.
  for (const committedItem of manifest.itemsV1.slice(0, continuation.nextOrdinalV1)) {
    const raw = await input.repository.read(ad05ItemReceiptPathV1({
      binding, itemIdV1: committedItem.itemIdV1,
    }));
    if (raw === null || !receiptMatchesV1({
      receipt: parseCandidateAd05ItemReceiptV1(raw),
      binding,
      manifestFingerprintV1: manifest.manifestFingerprintV1,
      item: committedItem,
    })) ad05FailV1("AD05_BINDING_CONFLICT");
  }
  const stop = Math.min(manifest.itemsV1.length,
    continuation.nextOrdinalV1 + pageLimitV1);
  while (continuation.nextOrdinalV1 < stop) {
    const item = manifest.itemsV1[continuation.nextOrdinalV1];
    await applyCandidateAd05TransactionalDocumentItemV1({
      repository: input.repository,
      binding,
      manifest,
      item,
      effect: input.effect,
      committedAtSecV1: input.committedAtSecV1,
    });
    await input.afterItemCommitV1?.(item.itemIdV1);
    continuation = continuationForOrdinalV1(
      binding, manifest, continuation.nextOrdinalV1 + 1,
    );
  }
  return continuation;
}

export interface CandidateAd05FinalVerificationV1 {
  schemaVersion: 1;
  manifestFingerprintV1: string;
  receiptSetFingerprintV1: string;
  remainingEvidenceFingerprintV1: string;
  sourceDispositionVerifiedV1: true;
  publicPrivacyVerifiedV1: true;
  restoreSuppressionVerifiedV1: true;
  unrelatedAssociationUnchangedV1: true;
  evidenceCodeV1: string;
  evidenceIdV1: string;
  verifiedAtSecV1: number;
  evidenceFingerprintV1: string;
}

export interface CandidateAd05FinalVerifierV1 {
  verifyFinalStateV1(input: {
    binding: CandidateAd05ExecutionBindingV1;
    manifest: CandidateAd05SealedManifestV1;
    receiptSet: CandidateAd05ReceiptSetSummaryV1;
    remainingReferenceEvidence: CandidateAd05RemainingReferenceEvidenceV1;
  }): Promise<unknown>;
}

export function ad05FinalVerificationFingerprintV1(
  evidence: Omit<CandidateAd05FinalVerificationV1, "evidenceFingerprintV1">,
): string {
  return canonicalSha256({
    contract: "account-deletion-ad05-final-verification-v1",
    ...evidence,
  });
}

function finalVerificationV1(value: unknown): CandidateAd05FinalVerificationV1 {
  const data = ad04RecordV1(value);
  if (data === null || !ad04ExactKeysV1(data, [
    "schemaVersion", "manifestFingerprintV1", "receiptSetFingerprintV1",
    "remainingEvidenceFingerprintV1", "sourceDispositionVerifiedV1",
    "publicPrivacyVerifiedV1", "restoreSuppressionVerifiedV1",
    "unrelatedAssociationUnchangedV1", "evidenceCodeV1", "evidenceIdV1",
    "verifiedAtSecV1", "evidenceFingerprintV1",
  ]) || data.schemaVersion !== 1 || data.sourceDispositionVerifiedV1 !== true ||
      data.publicPrivacyVerifiedV1 !== true ||
      data.restoreSuppressionVerifiedV1 !== true ||
      data.unrelatedAssociationUnchangedV1 !== true) {
    ad05FailV1("AD05_INCOMPLETE_INVENTORY");
  }
  const candidate: CandidateAd05FinalVerificationV1 = Object.freeze({
    schemaVersion: 1,
    manifestFingerprintV1: ad04HashV1(data.manifestFingerprintV1),
    receiptSetFingerprintV1: ad04HashV1(data.receiptSetFingerprintV1),
    remainingEvidenceFingerprintV1: ad04HashV1(
      data.remainingEvidenceFingerprintV1,
    ),
    sourceDispositionVerifiedV1: true,
    publicPrivacyVerifiedV1: true,
    restoreSuppressionVerifiedV1: true,
    unrelatedAssociationUnchangedV1: true,
    evidenceCodeV1: ad04OpaqueIdV1(data.evidenceCodeV1),
    evidenceIdV1: ad04OpaqueIdV1(data.evidenceIdV1),
    verifiedAtSecV1: ad04CounterV1(data.verifiedAtSecV1),
    evidenceFingerprintV1: ad04HashV1(data.evidenceFingerprintV1),
  });
  const {evidenceFingerprintV1, ...fingerprintInput} = candidate;
  if (ad05FinalVerificationFingerprintV1(fingerprintInput) !==
      evidenceFingerprintV1) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  return candidate;
}

export function ad05ReceiptSetFingerprintV1(input: {
  bindingFingerprintV1: string;
  manifestFingerprintV1: string;
  receiptFingerprintsV1: readonly string[];
}): string {
  return canonicalSha256({
    contract: "account-deletion-ad05-receipt-set-v1",
    bindingFingerprintV1: input.bindingFingerprintV1,
    manifestFingerprintV1: input.manifestFingerprintV1,
    receiptFingerprintsV1: input.receiptFingerprintsV1,
  });
}

function receiptSetSummaryV1(input: {
  binding: CandidateAd05ExecutionBindingV1;
  manifest: CandidateAd05SealedManifestV1;
  receipts: readonly CandidateAd05ItemReceiptV1[];
}): CandidateAd05ReceiptSetSummaryV1 {
  if (input.receipts.length !== input.manifest.itemCountV1) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  return Object.freeze({
    schemaVersion: 1,
    bindingFingerprintV1: input.binding.bindingFingerprintV1,
    manifestFingerprintV1: input.manifest.manifestFingerprintV1,
    itemCountV1: input.receipts.length,
    receiptSetFingerprintV1: ad05ReceiptSetFingerprintV1({
      bindingFingerprintV1: input.binding.bindingFingerprintV1,
      manifestFingerprintV1: input.manifest.manifestFingerprintV1,
      receiptFingerprintsV1: input.receipts.map((receipt) =>
        receipt.receiptFingerprintV1),
    }),
    latestReceiptCommittedAtSecV1: input.receipts.reduce(
      (latest, receipt) => Math.max(latest, receipt.committedAtSecV1), 0,
    ),
  });
}

/** Returns null for private progress. It never fabricates a nonterminal AD04 result. */
export async function finalizeCandidateAd05TransactionalAdapterV1(input: {
  repository: CandidateAd05TransactionRepositoryV1;
  binding: CandidateAd05ExecutionBindingV1;
  manifest: CandidateAd05SealedManifestV1;
  remainingReferenceVerifier: CandidateAd05RemainingReferenceVerifierV1;
  finalVerifier: CandidateAd05FinalVerifierV1;
  holdBoundaryAtV1?: Date | null;
}): Promise<AdapterResultContract | null> {
  const binding = parseCandidateAd05ExecutionBindingV1(input.binding);
  const manifest = parseCandidateAd05SealedManifestV1(input.manifest);
  assertCandidateAd05ManifestBindingV1({binding, manifest});
  await requireCandidateAd05CanonicalManifestV1({
    repository: input.repository,
    binding,
    manifest,
  });
  const receipts: CandidateAd05ItemReceiptV1[] = [];
  for (const item of manifest.itemsV1) {
    const raw = await input.repository.read(ad05ItemReceiptPathV1({
      binding, itemIdV1: item.itemIdV1,
    }));
    if (raw === null) return null;
    const receipt = parseCandidateAd05ItemReceiptV1(raw);
    if (!receiptMatchesV1({
      receipt,
      binding,
      manifestFingerprintV1: manifest.manifestFingerprintV1,
      item,
    })) {
      ad05FailV1("AD05_BINDING_CONFLICT");
    }
    receipts.push(receipt);
  }
  const receiptSet = receiptSetSummaryV1({binding, manifest, receipts});
  const remaining = await verifyCandidateAd05RemainingReferencesV1({
    repository: input.repository,
    binding,
    manifest,
    receiptSet,
    verifier: input.remainingReferenceVerifier,
  });
  if (remaining.remainingReferenceCountV1 !== 0) return null;
  const final = finalVerificationV1(await input.finalVerifier.verifyFinalStateV1({
    binding,
    manifest,
    receiptSet,
    remainingReferenceEvidence: remaining,
  }));
  if (final.manifestFingerprintV1 !== manifest.manifestFingerprintV1 ||
      final.receiptSetFingerprintV1 !== receiptSet.receiptSetFingerprintV1 ||
      final.remainingEvidenceFingerprintV1 !== remaining.evidenceFingerprintV1 ||
      final.verifiedAtSecV1 < receiptSet.latestReceiptCommittedAtSecV1 ||
      final.verifiedAtSecV1 < remaining.verifiedAtSecV1) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  const holdBoundaryAt = input.holdBoundaryAtV1 ?? null;
  if ((binding.actionV1 === "restrictedRetention") !== (holdBoundaryAt instanceof Date) ||
      (holdBoundaryAt !== null && !Number.isFinite(holdBoundaryAt.getTime()))) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  return validateAdapterResult({
    schemaVersion: 1,
    adapterId: binding.adapterIdV1,
    applicability: binding.actionV1 === "notApplicable" ?
      "notApplicable" : "applicable",
    state: binding.actionV1 === "notApplicable" ? "notApplicable" : "complete",
    disposition: binding.actionV1,
    policyDecisionState: "approved",
    policyDecisionId: binding.policyDecisionIdV1,
    policyVersion: binding.policyVersionV1,
    holdState: binding.actionV1 === "restrictedRetention" ? "activeApproved" : "none",
    evidenceCode: final.evidenceCodeV1,
    evidenceRef: ad05PrivateEvidenceRefV1({
      finalEvidenceIdV1: final.evidenceIdV1,
      remainingEvidenceIdV1: remaining.evidenceIdV1,
      manifestFingerprintV1: manifest.manifestFingerprintV1,
    }),
    holdBoundaryAt,
  });
}
