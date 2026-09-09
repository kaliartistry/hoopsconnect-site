# HoopsConnect account-deletion contract (AD01)

Status: **contract only; disabled; not approved for activation**

Contract version: `account-deletion-contract-v1`

This packet defines the boundary that later implementation packets must satisfy. It does not add a callable, route, UI, Firestore rule, worker, scheduler, provider integration, or deployment. The Dart and TypeScript modules are intentionally outside live runtime entrypoints. No deletion path may be activated until every gate in `account-deletion-release-gates.md` is passed with named owners and evidence.

Normative machine-readable sources:

- `contracts/account_deletion/v1/contract_fixtures.json`
- `contracts/account_deletion/v1/retention_policy_registry.json`
- `contracts/account_deletion/v1/release_gates.json`
- `lib/models/account_deletion/account_deletion_contract.dart`
- `functions/src/domain/account_deletion_contract.ts`

The retention policy is specified in `account-deletion-retention-policy.md`. Official-stat identity, evidence, and privacy rules are specified in `planning/official-stat-account-deletion-addendum.md`. The existing `planning/official-stat-contract.md` remains unchanged.

The normative disposition matrix is the 27-row **“Exact disposition matrix”** in *HoopsConnect account deletion: architecture and Sol implementation handoff*, prepared September 8, 2026, SHA-256 `9a9d0150244fc124bbc8ab1697fba177a3c862de8b7099c5c684d02ed8537832`. The machine-readable fixture and retention registry pin that source, hash, and row count. Every later adapter implementation must preserve at least these matrix invariants:

- withdrawing or reassigning an acknowledgment obligation never rewrites a truthful prior acknowledgment outcome;
- deleting an invite issuer revokes pending invitations but does not invalidate another recipient's completed redemption;
- privacy filtering never silently labels an incomplete ranking as complete;
- legacy identity rekeying uses a controlled mapping, identity-bearing read hold, and rebuild suppression;
- reverse indexes accelerate discovery but never replace independent reference reconciliation.

## Safety boundary

Account deletion is a server-owned, irreversible saga. The authenticated account may request deletion of its own current Auth generation; it may not select another UID, perform disposition locally, or infer authority from a profile, role string, path, email, display name, membership fragment, or cached receipt.

The server must:

1. authenticate and recently reauthenticate the current Auth principal;
2. verify app attestation or use an explicitly approved recovery path;
3. derive the account generation from the server-side Auth namespace, UID, and Auth creation time;
4. prepare a versioned impact statement and short-lived intent;
5. accept only an exact, versioned request with explicit `deleteAccount` confirmation;
6. atomically bind the request to one internal job, lifecycle epoch, semantic fingerprint, operation envelope, and status alias;
7. transition the account to `deleting` before any external authority can be reissued;
8. inventory and execute every required adapter under an approved retention decision;
9. verify Auth absence, data disposition, public privacy, custody, provider treatment, and durable restore suppression;
10. transition to `deleted` and `complete` only when the full completion predicate succeeds.

Unknown fields, states, adapters, policy decisions, custody conditions, holds, provider outcomes, or required inventory are failures. They never default to deletion complete.

## Versioned wire schemas

All v1 records are plain maps with exact keys. Unknown fields and future schema markers are rejected at every level, including the completion envelope, its checkpoint map, every adapter result, and every provider checkpoint. TypeScript structural typing is not a substitute for runtime exact-shape validation.

Every numeric wire field (`schemaVersion`, lifecycle `epoch`, tombstone `deletionEpoch`, job `attempt`, and job `leaseGeneration`) uses the same mathematical safe-integer decoder in Dart VM, Dart compiled to JavaScript, and TypeScript. It accepts finite integer-valued JSON numbers in the inclusive range `[-9007199254740991, 9007199254740991]`, normalizes equivalent forms such as `1`, `1.0`, and `1e0`, and normalizes negative zero to zero. Strings, fractions, nonfinite values, and out-of-range values fail. Field-specific rules then require schema version 1 and nonnegative epochs/counters.

`prepareDeletion` accepts only:

```text
schemaVersion = 1
```

It returns a server-derived, versioned impact statement and intent in a later packet. A prepared intent must not grant authority and must expire.

`requestDeletion` requires:

```text
schemaVersion, intentId, policyVersion, impactVersion,
operationId, requestId, statusSecretHash,
confirmation = deleteAccount, custodyChoice
```

The only optional field is an opaque `providerRevocationRef`. The request must not accept `targetUid`, account-generation inputs, role, membership, email, display name, adapter results, lifecycle state, or provider result from the client.

`deletionStatus` requires only:

```text
schemaVersion = 1, requestId, statusSecret
```

The status endpoint returns one coarse phase: `processing`, `accountRemovedCleanupPending`, `attentionRequired`, or `complete`. It must use uniform errors and timing so request IDs are not enumerable.

## Account generation and authority fence

An account generation is the tuple:

```text
authNamespace + accountId + authCreatedAt
```

For canonical hashing, the exact Firebase UID UTF-16 code units are encoded little-endian as unpadded base64url in `accountIdUtf16LeBase64Url`; the UID is never Unicode-normalized, replacement-encoded, or narrowed to the app's opaque-ID alphabet. The lowercase SHA-256 hash then uses `official-stat-canonical-json-v1` over `authNamespace`, `accountIdUtf16LeBase64Url`, and `authCreatedAt`. A deleted UID that is later recreated is a new generation even if the string UID is reused. Generation metadata must be server sourced.

The account lifecycle is strictly:

```text
active -> deleting -> deleted
```

There is no reverse transition. Restoration means a separately authorized new account generation, never a transition back to `active`.

Every granting path must validate all four conditions at use time:

- lifecycle is `active`;
- account generation matches;
- lifecycle epoch matches;
- the required capability is present.

`deleting` and `deleted` deny new grants. Stale generations, stale epochs, role/path-only checks, legacy receipts, pending invites, device caches, command receipts, and notification recipients cannot restore authority. Fencing applies to Firestore reads and writes, callables, command and receipt replay, invite redemption, provisioning, Storage, notifications, public/raw compatibility paths, exports, and old clients.

## Deletion job state machine

The normal job path is:

```text
accepted -> fencingExternalAccess -> inventory -> disposition -> verify -> complete
```

`accepted`, `fencingExternalAccess`, `inventory`, `disposition`, and `verify` may enter `retryWait` or `needsAttention` where the fixture permits. Those two states require exactly one `resumeStage` from `fencingExternalAccess`, `inventory`, `disposition`, or `verify`; all other states forbid `resumeStage`. `complete` is terminal.

The job separately records nonnegative safe-integer `attempt` and `leaseGeneration` counters, `authorityFenceDurable`, `minimumCleanupReferencesCaptured`, and an Auth-deletion checkpoint (`notScheduled`, `scheduled`, `retryRequired`, `needsAttention`, or `complete`). As soon as the authority fence and the minimum cleanup references needed for resumable work are durable, single-user Auth deletion and absence verification must be scheduled independently. Unknown adapters, disputed retention classification, remaining custody work, or another cleanup failure cannot keep that checkpoint at `notScheduled`. Auth-task failures use their own retry/attention state while the account remains fenced. No numeric service deadline is chosen by AD01.

Transient failure uses `retryWait` with bounded backoff. A policy gap, custody conflict, unsupported required adapter, unresolved external action, or exhausted retry budget uses `needsAttention`. Neither state reopens account authority. Operators resume from the recorded stage; they do not create a second deletion job.

## Fingerprints and idempotency

The semantic fingerprint binds exactly:

```text
accountGeneration, accountIdUtf16LeBase64Url, authNamespace, confirmation,
custodyChoice, impactVersion, policyVersion, schemaVersion
```

The operation envelope binds exactly:

```text
operationId, requestId, semanticFingerprint, statusSecretHash
```

Both use the canonical JSON encoder and SHA-256. `authTime`, ID token bytes, `intentId`, provider revocation material, and transport metadata are deliberately excluded from semantic meaning. They remain separately validated and recorded where policy permits.

Idempotency outcomes are exact:

- no existing job + authenticated current active generation: `acceptNew`;
- same operation + same semantic and envelope fingerprints: `exactReplay`;
- same operation with changed secret, custody, policy, impact, or other bound input: `conflict`;
- a different operation from another authenticated device in the same account generation, before Auth is disabled: `attachStatusAlias`, even if its proposed preview or scope differs from the already accepted winner;
- another device after disable: `denyFenced` and use its existing receipt or verified recovery;
- a recreated or otherwise different generation never attaches to the old job.

The same `operationId` remains strict: any changed semantic or envelope field is a conflict. A different operation's alias converges only on the winning job's immutable accepted semantic fingerprint; it cannot replace custody, policy, impact, disposition, or any other accepted scope and grants no mutation authority.

No retry may repeat destructive work merely because the original response was lost. If a submitted operation has persisted request/status material and then receives an authentication, recent-authentication, or app-attestation failure, the client must resolve its saved read-only status capability first. Acceptance may have committed before the response was lost and Auth was removed. Until status proves otherwise the result is `AD_ACCEPTANCE_UNKNOWN`, not “not accepted”; recovered acceptance yields `AD_ALREADY_ACCEPTED`, and an unresolved capability yields `AD_STATUS_UNAVAILABLE`. New authentication or separately approved recovery is selected only after status resolution establishes that it is appropriate. Adapter operations must be idempotent under the internal job ID and must record evidence sufficient to distinguish not-started, applied, awaiting verification, and terminal outcomes.

## Status capability

The client generates a cryptographically random 32-byte value and sends only the lowercase hexadecimal SHA-256 digest of the decoded secret bytes with `requestDeletion`. The clear secret itself uses canonical unpadded base64url, remains in the client receipt, and is presented only to `deletionStatus`.

Each alias binds exactly `schemaVersion`, `requestId`, `internalJobId`, `generationHash`, the winning `acceptedSemanticFingerprint`, `bindingKind`, fixed purpose `readOnlyDeletionStatus`, `statusSecretHash`, `createdAt`, and an approved `expiryPolicyDecisionId`. `bindingKind` distinguishes the winning operation from same-generation convergence. The server never stores the clear secret. Hash comparison must be constant-time.

This bearer capability permits only `readOwnCoarseDeletionStatus`. It cannot initiate or cancel deletion, restore an account, grant authority, mutate a job, expose inventory, or recover official-stat journals. Status retention and expiry remain a closed policy decision.

## Inventory adapters, results, and holds

The inventory version is `account-deletion-adapter-inventory-v1`. Every adapter in the fixture is required to produce exactly one result. Extra or duplicate adapter IDs fail verification.

Each result records:

- `schemaVersion = 1`;
- named `adapterId`;
- `applicability`: `applicable`, `notApplicable`, or `unknown`;
- `state`: `pending`, `blocked`, `complete`, `notApplicable`, or `unsupported`;
- disposition: `erase`, `detach`, `pseudonymize`, `restrictedRetention`, `accessRevokedAwaitingExpiry`, `notApplicable`, or `unresolved`;
- approved policy decision state and version;
- hold state: `none`, `activeApproved`, `releasePending`, or `unknown`;
- safe evidence code and internal evidence reference;
- `holdBoundaryAt`, which is a finite timestamp for restricted retention and otherwise null.

`unknown`, `pending`, `blocked`, `unsupported`, `unresolved`, an unapproved policy, or a missing required adapter prevents completion. `notApplicable` is terminal only when applicability, result, and disposition all say `notApplicable` and evidence explains why. `restrictedRetention` is terminal only under an `activeApproved` hold with named authority, scope, readers, duration/trigger, and review path.

Pseudonymization is not anonymity, and a hash is not anonymous by default. An action that leaves a stable link to the person remains personal-data treatment and must be approved as such.

## Custody and last recoverable owner

Deleting an account never deletes an association, tenant, team, game, or unrelated person's record merely because the account is an owner or contributor.

For an ordinary member, `custodyChoice=ordinary` is eligible. For the last recoverable owner:

- a verified transfer permits `transferThenDelete`;
- a named, independent custody and recovery operator permits `suspendToCustody` while deletion continues;
- if neither exists, the request must still receive a tracked operational resolution, but activation is blocked and the job enters `needsAttention` with `CUSTODY_CONFLICT`.

The system must not force a user to keep an account solely to preserve shared records. It also must not orphan shared data into an irrecoverable tenant. A future implementation must prove transfer and suspension rehearsals before G3 can pass.

## Auth-only and legacy compatibility

A currently authenticated Auth generation can request self-deletion even when the user profile is missing, there is no membership, a membership is malformed, or a legacy profile contains a role string. This path must not create a membership, bootstrap an owner, accept legacy role authority, or skip inventory.

Conversely, a public submission with a profile or role but no current Auth proof is not self-deletion authority. It must use a separately approved verified recovery or non-account rights process.

Legacy and old-client paths remain subject to the same generation and lifecycle fences. Missing legacy data is recorded as `notApplicable` only after adapter-specific proof; it is never inferred from a missing current-schema profile.

## Provider checkpoints

Provider checkpoints are exact version-1 records and use finite `checkedAt` timestamps. `firebaseAuth` must reach `complete` with verified Auth absence. `appleCredential` may reach:

- `complete` after verified revocation/disposition;
- `notApplicable` only with evidence that no Apple relationship applies;
- `manualActionGuidance` when required historical Apple revocation material is truthfully unavailable and the approved operational fallback has been delivered and recorded;
- `retryRequired`, `pending`, or `unknown`, which are nonterminal.

`manualActionGuidance` is not a false claim that revocation occurred. It is a terminally recorded disclosure that HoopsConnect removed its account while the user may need to manage the Apple relationship directly. The exact guidance, proof, eligibility, and retention require G6 policy and operational approval.

## Tombstone and restore suppression

The minimal tombstone schema contains only:

```text
schemaVersion, generationHmac, deletionEpoch, policyVersion,
suppressionKeyVersion, acceptedAt, completedAt, minimumReplayCutoff
```

It must not contain UID, email, name, raw generation hash, adapter inventory, official-stat journal, provider token, or clear status secret. `generationHmac` uses a separately managed keyed scheme, not a plain hash. The approved retention registry must define key custody, rotation, duration, readers, erasure, and compromise response.

Before any restored backup, PITR image, object version, export, migration import, or processor replay serves traffic, the suppression ledger must be applied and every deleted generation re-disposed. A restore cannot recreate authority, identity bindings, public projections, device recipients, or deleted personal content.

Every non-null lifecycle, tombstone, provider, or hold timestamp must represent a finite instant. Completion cannot precede acceptance, and the minimum replay cutoff cannot precede acceptance.

## Completion predicate

Deletion is complete only when all of the following are true:

- Firebase Auth absence is verified;
- data-disposition verification is true;
- public-privacy verification is true;
- custody outcome is recorded;
- provider disposition is recorded;
- restore suppression is durable;
- every inventory adapter has one approved terminal result;
- every applicable restricted retention has an approved active hold;
- all provider checkpoints are terminal;
- there is no unknown required state.

Auth removal alone is not completion. If Auth is absent while cleanup remains, status is `accountRemovedCleanupPending`; failures requiring intervention are `attentionRequired`. Only the full predicate yields account lifecycle `deleted`, job state `complete`, and status phase `complete`.

## Stable error surface

The stable external codes and their transport, retry, and idempotency classes live in the shared fixture and both runtime modules. They include authentication/reauthentication, identity mismatch, attestation, invalid request, expired or changed impact, operation conflict/replay, custody/policy readiness, rate limiting, ambiguous availability, status recovery, and accepted review states.

Internal-only codes are `AUTH_DELETE_RETRY`, `MEDIA_VERSION_CONFLICT`, `RETENTION_CLASS_UNKNOWN`, `REFERENCE_REMAINS`, `CUSTODY_CONFLICT`, and `UNSUPPORTED_REQUIRED_ADAPTER`. Public errors must not reveal whether an arbitrary request ID, UID, email, tenant, adapter row, or provider relationship exists.

## Compatibility and reversibility

Later packets may add versioned fields only through a new schema version and cross-runtime fixtures. They may not reinterpret a v1 field, weaken unknown-field rejection, change v1 fingerprints, or make a previously nonterminal state terminal.

The only reversible artifacts in AD01 are code and documentation on this branch. The irreversible operation remains disabled. Any discovered conflict with the official-stat canonical encoding, certified hashes, identity evidence, provider requirements, or retention authority must stop activation and be escalated rather than silently adapted.
