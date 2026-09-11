# HoopsConnect AD02 dormant V2 lifecycle-fence matrix

Status: **isolated candidate only; activation prohibited**

`activationAllowed: false`

Integration base: `f873471420d6480557557154b568777842b2d926`

Historical evidence only: `codex/account-deletion-ad02-lifecycle-fence` at
`68312fd6e176aa84c7c422c90419300d601ef0a5`

AD02 consumes the merged Auth Incarnation V2 contract without exporting a
Function, changing a live Rule, installing a production provider/client
consumer, issuing `G`, writing a claim, migrating a record, accepting deletion,
or mutating Auth. The V1 deletion contract and its fixed fingerprints remain
unchanged and cannot substitute for V2 scope, `G`, or `E`.

## Authority boundary

Every granting candidate path requires exact equality across:

1. provider `aud` and configured project;
2. provider Firebase tenant and nullable `authTenantIdV2`;
3. provider UID and `authUidV2`;
4. random `accountGenerationV2` (`G`);
5. safe-integer `accountLifecycleEpochV2` (`E`);
6. active lifecycle and active membership;
7. `auth_time > reauthAfterSecV2`; and
8. the requested capability and association.

Root accounts and tenant accounts use different physical lanes. There is no
sentinel tenant and no fallback:

| Record | Root lane | Tenant lane |
| --- | --- | --- |
| Lifecycle | `accountLifecycleV2Root/{uid}` | `accountLifecycleV2Tenants/{tenantId}/users/{uid}` |
| Membership | `membershipsV2Root/{uid}` | `membershipsV2Tenants/{tenantId}/users/{uid}` |
| Storage projection | `storageAuthorizationsV2Root/{uid}` | `storageAuthorizationsV2Tenants/{tenantId}/users/{uid}` |
| Delivery profile | `accountProfilesV2Root/{uid}` | `accountProfilesV2Tenants/{tenantId}/users/{uid}` |
| FCM installation | `accountFcmRegistrationsV2Root/{uid}/installations/{slot0..slot7}` | `accountFcmRegistrationsV2Tenants/{tenantId}/users/{uid}/installations/{slot0..slot7}` |
| Protected Storage object | `candidateProtectedV2Root/{uid}/{G}/{associationId}/...` | `candidateProtectedV2Tenants/{tenantId}/users/{uid}/{G}/{associationId}/...` |
| Recreation suppression | `accountGenerationSuppressionsV2Root/{uid}` | `accountGenerationSuppressionsV2Tenants/{tenantId}/users/{uid}` |

The production issuer remains deliberately unavailable. Candidate pending
bootstrap evaluation accepts only the existing V2 pending-binding schema. It
does not generate `G`, promote a lifecycle to active, or write any record. Any
valid suppression row denies UID reuse regardless of a proposed new `G`.

## Requirement matrix

| Requirement | Candidate implementation | Evidence and limit |
| --- | --- | --- |
| Provider-bound authorization | `functions/src/domain/account_lifecycle_ad02_v2.ts` | Extracts only provider-verified V2 claims, calls the merged evaluator, and compares the resulting membership association with the request's exact expected association; creation time, V1 claims, profiles, and legacy memberships are never consulted. |
| Tenant-aware authority paths | Same module and candidate Rules | Root/tenant same-UID tests prove no lane fallback. |
| Stale token and recreation denial | V2 evaluator, candidate Rules, suppression parser | Old `G`/`E`, equal freshness boundary, inactive lifecycle, and suppressed pending recreation fail closed. Actual suppression writes remain AD04 work. |
| Minimized active-member directory | `buildActiveMemberDirectoryV2`; shared Dart parser | The builder rejects mixed project, tenant, or association inputs and rejects source query envelopes larger than the requested limit plus one, preserving a bounded `truncated` sentinel. Its DTO contains only schema, UID, display name, team ID, and division ID. Email, role, capabilities, FCM tokens, preferences, `G`, and `E` are absent. No production callable is exported. |
| Notification recipient and delivery ordering | `functions/src/domain/notification_delivery_ad02_v2.ts` | A batch has one exact project/tenant/association and rejects mixed lanes. Tokens come only from current exact-scope/G/E installation registrations, never a parallel profile token list. Missing preferences are not opt-in. Effect and attempt records bind project/tenant, exact immutable provider payload hash, project/tenant/UID/G/E recipient bindings, and token hashes; the provider receives that bound payload. Each chunk is revalidated at reservation and dispatch. Provider invocation precedes the durable `submitted` claim. A dispatch barrier is released only with a durable terminal outcome. Existing and uncertain attempts are never resent. Batches are capped at 200 recipients and eight tokens per recipient. |
| Client session attempts and consumers | `lib/services/account_lifecycle_candidate_adapter_v2.dart` | Uses the actual V2 gate. Only exact `ready` permits listeners, capabilities, and FCM. Attempt ID, monotonic high-water, opaque nonce, scope/G/E, refresh, switch, deletion, and sign-out races are tested with fakes. It is absent from the production provider tree. |
| Candidate routing | `lib/models/account_deletion/account_lifecycle_ad02_v2.dart` | Pure synthetic-state routing mirrors the agreed split contract: authenticated request at `/account/delete`, public read-only recovery at `/account/deletion/status`, and authenticated local-work reconciliation at `/account/deletion/reconcile-device`. A bound receipt hands deletion/deleted sessions to status before ordinary Auth redirects, without reading raw lifecycle authority or changing `GoRouter`. No production route is installed. |
| FCM registration and detach | Candidate client adapter and candidate Rules | Each account has eight fixed installation slots, exact-scope/G/E bound and used as the sole notification delivery source; recipient construction rejects a source envelope above eight rows before iteration. Token writes serialize. A stale completion is removed. Both sign-out and account switch acquire the client latch synchronously and require successful owner removal or token rotation before Auth may change. Detach verifies the exact prior provider attempt immediately before invoking an attempt-scoped sign-out callback. Failed Auth sign-out can restore the prior exact attempt only when registration restoration and two further exact-current Auth checks succeed; otherwise grants stay latched closed. Public gate views are live and cannot cache a retired grant. Deletion cannot be rolled back. No production token service changes. |
| Legacy derived writers | `evaluateLegacyDerivedWriterFenceV2`, `assertLegacyDerivedWriterFenceV2`, `commitCandidateDerivedWriteV2` | Source approval must carry original project/tenant/UID/G/E. Every candidate derived commit reconstructs the exact actor stamp and rechecks it inside its transaction; both the positive commit and revoked negative path are tested. A delayed trigger cannot attach `approvedBy` UID to whatever authority is current later. Production legacy writers are unchanged. |
| Firestore and Storage | Emulator-only AD02 fixtures | Firestore uses token plus lifecycle/membership, limits FCM registrations to fixed `slot0` through `slot7` document IDs, and stamps protected records with full project/tenant/UID/G/E ownership. Storage uses one exact V2 projection plus root/tenant/UID/G-separated physical object lanes. Raw authority/deletion/delivery records are private. Generic Storage mutation remains denied. `firebase.json` still references only live V1 Rules. |
| Transitive dormancy | `functions/test/account_lifecycle_ad02_v2_dormancy.test.js` | Pinned production blobs must match exact merged main, and recursive TypeScript/Dart import graphs must not reach candidate modules. Merely updating a baseline hash cannot hide a consumer. |
| Shared Dart/TypeScript semantics | `contracts/account_deletion/ad02/lifecycle_fixtures_v2.json` | Both runtimes validate the same activation, path, directory, route, and boundary declarations. |

## Notification uncertainty contract

The durable attempt states are:

```text
reserved -> dispatchCommitted -> submitted -> succeeded | partial | failed
       \-> skipped
```

`dispatchCommitted` atomically acquires the association deletion barrier after
the final authority/token recheck. The provider function is invoked before the
store may claim `submitted`. A crash before or after invocation therefore
leaves a truthful uncertain state and a held barrier. A retry reports the
existing attempt and never resends it. A provider rejection or malformed
response is also uncertain because submission may have been accepted before
the local failure became visible; neither releases the barrier. AD04 must
provide a provider-specific reconciler before deletion can wait on or release
these records in production.

## Explicitly rejected old behavior

- Auth creation time or UID as generation/session authority;
- ordinary callable claim issuance or forced-refresh establishment of `G`;
- Rules that compare only lifecycle and membership/projection to each other;
- `V1 || V2`, V1 fallback, or translation of a V1 hash, receipt, suppression
  key, role, profile, or membership into V2 authority;
- privileged legacy membership adoption or repair;
- raw lifecycle document access for routing; and
- delayed stats work that carries only `approvedBy` UID.

The old AD02 branch remains untouched and is not rebased or cherry-picked.

## Ownership that remains outside AD02

- **AD04** owns deletion acceptance, lifecycle/membership/projection fencing,
  suppression writes, delivery-barrier serialization, uncertain-attempt
  reconciliation, cleanup, and Auth deletion.
- **AD06** owns privacy epoch, public/raw/export identity suppression, and
  crash-safe custody across official-stat derived projections. The narrow
  actor fence in this packet does not satisfy G9 or official-stat deletion.
- A separate activation architecture must provide the trusted tenant-aware
  issuer, pending-binding transaction, AD01/V1 evidence linkage, migration and
  audit, sanitized lifecycle-status transport, production Rules, client-root
  integration, recovery, and exact-head release review.

Packet 06 normalized-calculator/canonical conformance and Packet 07 offline
journal/recovery conformance remain untouched and mandatory in the full test
matrix.
