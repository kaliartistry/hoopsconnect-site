# Auth Incarnation V2 Dormant Prerequisite

Status: local candidate only

`activationAllowed: false`

This packet defines and tests the authority boundary required before account
deletion lifecycle work can be rebuilt. It does not activate that boundary.
The deployed Functions exports, live Firestore Rules, live Storage Rules,
client provider tree, router, notification service, and Auth flows do not
reference these modules.

## Security contract

An Auth incarnation is identified by a cryptographically random 32-byte value
encoded as exactly 64 lowercase hexadecimal characters, `accountGenerationV2`
(`G`). Creation time is not an identity. The signed proof also carries
`accountLifecycleEpochV2` (`E`) and an exact project, tenant, and UID scope.

Protected authority is valid only when all of the following are true:

1. the token, lifecycle, and membership use the explicit V2 schema;
2. their project, nullable tenant, UID, `G`, and `E` values match exactly,
   including provider `aud` and Firebase `firebase.tenant` reconciliation;
3. lifecycle and membership are active;
4. `auth_time > reauthAfterSecV2` (equality is denied); and
5. the membership contains the required capability.

Storage uses one versioned projection carrying the same scope, `G`, `E`,
lifecycle state, membership state, freshness boundary, association, and
capabilities. The token must match that projection exactly. Token comparisons
add no document reads. The candidate Firestore policy reads lifecycle plus
membership; the candidate Storage policy reads one Firestore projection plus
the Storage resource. Generic candidate Storage paths are read-only; mutation
stays denied until a concrete object policy defines operation-specific grants.

Authority addressing is tenant-aware without a magic sentinel. Null-tenant
records use `accountLifecycleV2Root/{uid}`, `membershipsV2Root/{uid}`, and
`storageAuthorizationsV2Root/{uid}`. Concrete tenants use the corresponding
`*V2Tenants/{tenantId}/users/{uid}` lane. The same UID in two tenants therefore
cannot share a lifecycle, membership, or projection slot.

Every malformed, missing, inactive, or mismatched value fails closed. A V1
generation hash, receipt, suppression key, lifecycle record, or unbound
membership cannot substitute for any V2 value. Legacy privileged memberships
are never adopted or repaired by this packet.

## Trusted issuance boundary

The TypeScript seam accepts a future provider-authenticated creation or
enrollment issuer. Its production implementation is deliberately unavailable.
There is no callable, blocking hook, Auth trigger, claim write, lifecycle
writer, projection writer call site, migration, or exported handler. The only
successful issuer used by tests is an injected fake backed by Node's
cryptographic `randomBytes(32)`.

A future trusted flow must establish a pending, non-granting server binding
before it can issue signed proof. An ordinary callable, old ID token, or forced
refresh must never establish or replace `G`. Reenrollment must enforce the
strict freshness boundary. Production UID reuse is prohibited by default.
Out-of-band console or API replacement cannot be considered instantly safe;
fence-before-Auth-mutation remains mandatory.

## Dormant client gate

The pure client reducer permits protected listeners, capabilities, and FCM
registration only in `ready`. Each establishment is keyed by an attempt ID plus
exact project, nullable tenant, UID, `G`, and `E`. The evaluator-produced
binding carries that exact attempt ID, so an event cannot pair a new attempt
with an old binding even when every other identity field is unchanged. Refresh
creates a new attempt ID before new proof can restore readiness. Old
asynchronous completions, including same-UID/new-generation and same-identity
retry races, cannot affect the current attempt.
Refresh, proof-loss, deletion, sign-out, and account-switch sequences remain
non-granting until a matching validated proof transition. Nothing instantiates
this reducer in the production provider tree in this packet.

## Candidate policy fixtures

- `functions/test/fixtures/auth_incarnation_v2/firestore.rules`
- `functions/test/fixtures/auth_incarnation_v2/storage.rules`

These files are loaded directly by emulator tests. Their
`AUTH_INCARNATION_V2_TEST_ONLY_PROJECT=demo-hoopsconnect` marker and project
selector are test-only and are not a production selector.
`firebase.json` continues to reference only `firestore.rules` and
`storage.rules`.

## Green-base dormancy hashes

The static dormancy test recomputes Git blob IDs and requires the before and
after values to remain identical.

| Production surface | Before | Required after |
| --- | --- | --- |
| `functions/src/index.ts` | `78ebe0c51a1550132da8201b0f2e7b783260cb38` | same |
| `firestore.rules` | `9dc99cf1f7c597dd556898424b2911154abe3fc3` | same |
| `storage.rules` | `54d7ba69c6ae42dd1e7556b1e2ca2164a3c18d53` | same |
| `lib/main.dart` | `e362527e198c63d829fd81be72792239625619d5` | same |
| `lib/providers/auth_providers.dart` | `b7513cb1767b0943949ca40976bbd05f4a0effba` | same |
| `lib/app/router/app_router.dart` | `f4e0417b6a0a7d25f1edb4d27be4d0463c3467a4` | same |

## Activation gates

All account-deletion release gates remain closed. A later activation packet
must independently prove the trusted provider lifecycle, pending-binding
atomicity, claim propagation, fence-before-mutation operations, live Rules,
transactional lifecycle/membership/projection writes, client-root integration,
FCM cleanup, recovery procedures, and immutable exact-head security review.
