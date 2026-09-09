import {createHash} from "crypto";
import {
  AuthIncarnationScopeV2,
  parseAuthIncarnationScopeV2,
} from "./auth_incarnation_v2";
import {PersistedActiveMemberV2} from "./account_lifecycle_ad02_v2";

export type NotificationPreferenceV2 =
  | "ackReminders"
  | "statReminders"
  | "newPosts";

export interface NotificationRecipientBindingV2 extends AuthIncarnationScopeV2 {
  accountGenerationV2: string;
  accountLifecycleEpochV2: number;
}

export interface AuthorizedNotificationRecipientV2 {
  readonly binding: NotificationRecipientBindingV2;
  readonly associationId: string;
  readonly fcmTokens: readonly string[];
  readonly notificationPrefs: Readonly<Record<string, boolean>>;
}

export interface NotificationFcmRegistrationV2 {
  readonly binding: NotificationRecipientBindingV2;
  readonly associationId: string;
  readonly installationId: string;
  readonly token: string;
}

export interface NotificationTokenBindingV2 {
  readonly recipient: NotificationRecipientBindingV2;
  readonly token: string;
  readonly tokenHash: string;
}

export interface NotificationEffectClaimV2 {
  readonly schemaVersion: 2;
  readonly effectClaimId: string;
  readonly effectHash: string;
  readonly associationId: string;
  readonly capability: string;
  readonly preference: NotificationPreferenceV2 | null;
  readonly candidateFingerprint: string;
  readonly plannedChunkCount: number;
}

export interface NotificationAttemptClaimV2 {
  readonly schemaVersion: 2;
  readonly attemptId: string;
  readonly effectClaimId: string;
  readonly chunkIndex: number;
  readonly associationId: string;
  readonly capability: string;
  readonly preference: NotificationPreferenceV2 | null;
  readonly intended: readonly NotificationTokenBindingV2[];
}

export type NotificationClaimResultV2 = "created" | "matching" | "conflict";
export type NotificationReservationResultV2 =
  | {kind: "duplicate"}
  | {kind: "skipped"}
  | {kind: "reserved"; bindings: readonly NotificationTokenBindingV2[]};
export type NotificationDispatchResultV2 =
  | {kind: "duplicate"}
  | {kind: "skipped"}
  | {kind: "committed"; bindings: readonly NotificationTokenBindingV2[]};

/**
 * Every method is a durable boundary. A concrete adapter must atomically
 * revalidate lifecycle, membership, profile, and exact FCM installation
 * authority in reserveAttempt and commitDispatch. commitDispatch must acquire
 * the association deletion barrier in the same transaction;
 * completeAndRelease must release it only with a durable terminal outcome.
 */
export interface NotificationDeliveryStoreV2 {
  claimEffect(effect: NotificationEffectClaimV2): Promise<NotificationClaimResultV2>;
  reserveAttempt(attempt: NotificationAttemptClaimV2): Promise<NotificationReservationResultV2>;
  commitDispatch(attempt: NotificationAttemptClaimV2): Promise<NotificationDispatchResultV2>;
  markSubmitted(attemptId: string): Promise<void>;
  completeAndRelease(input: {
    attemptId: string;
    state: "succeeded" | "partial" | "failed";
    successCount: number;
    failureCount: number;
  }): Promise<void>;
}

export interface NotificationProviderResponseV2 {
  successCount: number;
  failureCount: number;
}

export interface NotificationProviderV2 {
  submit(input: {
    attemptId: string;
    chunkIndex: number;
    tokens: readonly string[];
  }): Promise<NotificationProviderResponseV2>;
}

export interface NotificationDeliveryHooksV2 {
  afterReservation?(attempt: NotificationAttemptClaimV2): Promise<void> | void;
  afterDispatchCommit?(attempt: NotificationAttemptClaimV2): Promise<void> | void;
  afterProviderInvocation?(attempt: NotificationAttemptClaimV2): Promise<void> | void;
}

export interface NotificationDeliverySummaryV2 {
  reserved: number;
  submitted: number;
  skipped: number;
  duplicates: number;
  succeeded: number;
  partial: number;
  failed: number;
}

const generationPattern = /^[a-f0-9]{64}$/;
const identifierPattern = /^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/;
const tokenPattern = /^[^\u0000-\u001f\u007f]{1,4096}$/;

function sha256(value: string): string {
  return createHash("sha256").update(value, "utf8").digest("hex");
}

function canonicalTenant(tenantId: string | null): string {
  return tenantId === null ? "root" : `tenant:${tenantId}`;
}

function canonicalTuple(parts: readonly (string | number | null)[]): string {
  return JSON.stringify(parts);
}

function bindingKey(binding: NotificationRecipientBindingV2): string {
  return canonicalTuple([
    binding.authProjectIdV2,
    canonicalTenant(binding.authTenantIdV2),
    binding.authUidV2,
    binding.accountGenerationV2,
    binding.accountLifecycleEpochV2,
  ]);
}

function validBinding(value: NotificationRecipientBindingV2): boolean {
  try {
    parseAuthIncarnationScopeV2({
      authProjectIdV2: value.authProjectIdV2,
      authTenantIdV2: value.authTenantIdV2,
      authUidV2: value.authUidV2,
    });
  } catch {
    return false;
  }
  return generationPattern.test(value.accountGenerationV2) &&
    Number.isSafeInteger(value.accountLifecycleEpochV2) &&
    value.accountLifecycleEpochV2 >= 0;
}

export function notificationRecipientFromActiveMemberV2(
  member: PersistedActiveMemberV2,
  registrations: readonly NotificationFcmRegistrationV2[],
): AuthorizedNotificationRecipientV2 {
  const binding: NotificationRecipientBindingV2 = Object.freeze({
    ...member.scope,
    accountGenerationV2: member.accountGenerationV2,
    accountLifecycleEpochV2: member.accountLifecycleEpochV2,
  });
  if (!validBinding(binding)) throw new TypeError("Invalid AD02 V2 recipient binding.");
  const expectedBindingKey = bindingKey(binding);
  const tokens = new Set<string>();
  for (const registration of registrations) {
    if (
      registration.associationId !== member.associationId ||
      !identifierPattern.test(registration.installationId) ||
      !tokenPattern.test(registration.token) ||
      !validBinding(registration.binding) ||
      bindingKey(registration.binding) !== expectedBindingKey
    ) {
      continue;
    }
    tokens.add(registration.token);
  }
  return Object.freeze({
    binding,
    associationId: member.associationId,
    fcmTokens: Object.freeze([...tokens]),
    notificationPrefs: Object.freeze({...member.profile.notificationPrefs}),
  });
}

function tokenBindings(
  associationId: string,
  recipients: readonly AuthorizedNotificationRecipientV2[],
  preference: NotificationPreferenceV2 | null,
): NotificationTokenBindingV2[] {
  const owners = new Map<string, AuthorizedNotificationRecipientV2>();
  const conflictingTokens = new Set<string>();
  for (const recipient of recipients) {
    if (
      recipient.associationId !== associationId ||
      !validBinding(recipient.binding) ||
      (preference !== null && recipient.notificationPrefs[preference] !== true)
    ) {
      continue;
    }
    for (const token of recipient.fcmTokens) {
      if (typeof token !== "string" || !tokenPattern.test(token) || conflictingTokens.has(token)) {
        continue;
      }
      const owner = owners.get(token);
      if (owner === undefined) {
        owners.set(token, recipient);
      } else if (bindingKey(owner.binding) !== bindingKey(recipient.binding)) {
        owners.delete(token);
        conflictingTokens.add(token);
      }
    }
  }
  return [...owners.entries()].map(([token, recipient]) => Object.freeze({
    recipient: Object.freeze({...recipient.binding}),
    token,
    tokenHash: sha256(token),
  })).sort((left, right) =>
    left.tokenHash.localeCompare(right.tokenHash) ||
    bindingKey(left.recipient).localeCompare(bindingKey(right.recipient)));
}

function immutableAttempt(
  effectClaimId: string,
  chunkIndex: number,
  associationId: string,
  capability: string,
  preference: NotificationPreferenceV2 | null,
  intended: readonly NotificationTokenBindingV2[],
): NotificationAttemptClaimV2 {
  return Object.freeze({
    schemaVersion: 2,
    attemptId: `v2_${sha256(`${effectClaimId}\u0000${chunkIndex}`)}`,
    effectClaimId,
    chunkIndex,
    associationId,
    capability,
    preference,
    intended: Object.freeze([...intended]),
  });
}

function subsetReturnedByStore(
  intended: readonly NotificationTokenBindingV2[],
  returned: readonly NotificationTokenBindingV2[],
): boolean {
  const allowed = new Map(intended.map((entry) => [
    `${entry.tokenHash}\u0000${bindingKey(entry.recipient)}`,
    entry,
  ]));
  const seen = new Set<string>();
  for (const entry of returned) {
    const key = `${entry.tokenHash}\u0000${bindingKey(entry.recipient)}`;
    const original = allowed.get(key);
    if (
      original === undefined ||
      entry.token !== original.token ||
      entry.tokenHash !== sha256(entry.token) ||
      seen.has(key)
    ) {
      return false;
    }
    seen.add(key);
  }
  return true;
}

function validProviderResponse(
  response: NotificationProviderResponseV2,
  tokenCount: number,
): boolean {
  return Number.isSafeInteger(response.successCount) &&
    Number.isSafeInteger(response.failureCount) &&
    response.successCount >= 0 &&
    response.failureCount >= 0 &&
    response.successCount + response.failureCount === tokenCount;
}

/**
 * Candidate state machine with conservative at-most-once retry semantics.
 * Existing or uncertain attempts are never resent. The provider is invoked
 * before `submitted` is claimed; failure to persist that claim leaves the
 * dispatch barrier in an explicitly uncertain state for AD04 reconciliation.
 */
export async function sendAuthorizedNotificationChunksV2(input: {
  effectId: string;
  associationId: string;
  capability: string;
  recipients: readonly AuthorizedNotificationRecipientV2[];
  store: NotificationDeliveryStoreV2;
  provider: NotificationProviderV2;
  preference?: NotificationPreferenceV2;
  hooks?: NotificationDeliveryHooksV2;
}): Promise<NotificationDeliverySummaryV2> {
  if (
    typeof input.effectId !== "string" ||
    input.effectId.length === 0 ||
    input.effectId.length > 512 ||
    typeof input.associationId !== "string" ||
    input.associationId.length === 0 ||
    typeof input.capability !== "string" ||
    input.capability.length === 0
  ) {
    throw new TypeError("Invalid AD02 V2 notification request.");
  }
  const preference = input.preference ?? null;
  const entries = tokenBindings(input.associationId, input.recipients, preference);
  const summary: NotificationDeliverySummaryV2 = {
    reserved: 0,
    submitted: 0,
    skipped: 0,
    duplicates: 0,
    succeeded: 0,
    partial: 0,
    failed: 0,
  };
  if (entries.length === 0) return summary;

  const effectNamespace = canonicalTuple([
    input.associationId,
    input.capability,
    preference ?? "",
    input.effectId,
  ]);
  const effectClaimId = `v2_${sha256(effectNamespace)}`;
  const candidateFingerprint = sha256(entries.map((entry) =>
    `${bindingKey(entry.recipient)}:${entry.tokenHash}`).join("\n"));
  const plannedChunkCount = Math.ceil(entries.length / 500);
  const effect: NotificationEffectClaimV2 = Object.freeze({
    schemaVersion: 2,
    effectClaimId,
    effectHash: sha256(input.effectId),
    associationId: input.associationId,
    capability: input.capability,
    preference,
    candidateFingerprint,
    plannedChunkCount,
  });
  const effectResult = await input.store.claimEffect(effect);
  if (effectResult === "conflict") {
    summary.duplicates = plannedChunkCount;
    return summary;
  }
  if (effectResult !== "created" && effectResult !== "matching") {
    throw new Error("Invalid AD02 V2 effect-claim result.");
  }

  for (let offset = 0, chunkIndex = 0; offset < entries.length; offset += 500, chunkIndex += 1) {
    const attempt = immutableAttempt(
      effectClaimId,
      chunkIndex,
      input.associationId,
      input.capability,
      preference,
      entries.slice(offset, offset + 500),
    );
    const reservation = await input.store.reserveAttempt(attempt);
    if (reservation.kind === "duplicate") {
      summary.duplicates += 1;
      continue;
    }
    if (reservation.kind === "skipped") {
      summary.skipped += 1;
      continue;
    }
    if (
      reservation.bindings.length === 0 ||
      !subsetReturnedByStore(attempt.intended, reservation.bindings)
    ) {
      throw new Error("AD02 V2 notification reservation expanded or changed authority.");
    }
    summary.reserved += 1;
    await input.hooks?.afterReservation?.(attempt);

    const dispatch = await input.store.commitDispatch(attempt);
    if (dispatch.kind === "duplicate") {
      summary.duplicates += 1;
      continue;
    }
    if (dispatch.kind === "skipped") {
      summary.skipped += 1;
      continue;
    }
    if (
      dispatch.bindings.length === 0 ||
      !subsetReturnedByStore(reservation.bindings, dispatch.bindings)
    ) {
      throw new Error("AD02 V2 notification dispatch expanded or changed authority.");
    }
    await input.hooks?.afterDispatchCommit?.(attempt);

    const providerInput = Object.freeze({
      attemptId: attempt.attemptId,
      chunkIndex,
      tokens: Object.freeze(dispatch.bindings.map((entry) => entry.token)),
    });
    let providerPromise: Promise<
      {ok: true; response: NotificationProviderResponseV2} |
      {ok: false; error: unknown}
    >;
    try {
      providerPromise = input.provider.submit(providerInput).then(
        (response) => ({ok: true as const, response}),
        (error: unknown) => ({ok: false as const, error}),
      );
    } catch (error) {
      providerPromise = Promise.resolve({ok: false as const, error});
    }
    await input.hooks?.afterProviderInvocation?.(attempt);
    await input.store.markSubmitted(attempt.attemptId);
    summary.submitted += 1;

    const settled = await providerPromise;
    if (!settled.ok) {
      throw settled.error instanceof Error
        ? settled.error
        : new Error("AD02 V2 notification provider outcome is uncertain.");
    }
    if (!validProviderResponse(settled.response, dispatch.bindings.length)) {
      throw new Error("AD02 V2 notification provider returned an invalid uncertain outcome.");
    }
    const successCount = settled.response.successCount;
    const failureCount = settled.response.failureCount;
    const state: "succeeded" | "partial" | "failed" = failureCount === 0
      ? "succeeded"
      : successCount === 0 ? "failed" : "partial";
    await input.store.completeAndRelease({
      attemptId: attempt.attemptId,
      state,
      successCount,
      failureCount,
    });
    summary[state] += 1;
  }
  return summary;
}
