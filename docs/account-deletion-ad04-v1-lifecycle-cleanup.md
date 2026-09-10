# AD04 account deletion lifecycle cleanup candidate

Status: dormant, emulator-only candidate. Production activation, deployed handlers,
live provider calls, and live Rules changes remain closed.

## Boundary

AD04 composes the frozen AD01 public wire contract with AD02 account-incarnation
authority and AD03 ownership departure. It does not change AD01 schema version 1,
wire fields, fingerprints, or unknown-field rejection. It does not implement AD05
cleanup internals, application UI, public pages, or policy decisions.

All callable-looking entry points in this candidate require injected repositories,
identity or event verifiers, and fake or emulator provider adapters. None is exported
from `functions/src/index.ts`.

## Acceptance and recovery

Preparation persists a short-lived, generation-bound impact intent after a fresh,
revocation-checked identity and App Check verifier has established exact issuer,
audience, project, tenant, UID, Auth creation time, generation, and lifecycle epoch.

Acceptance uses one Firestore transaction. It revalidates the intent, AD02 lifecycle,
optional current membership, and any AD03 owner departure before writing the deleting
fence, minimum cleanup references, deterministic job, operation receipt, private
provider binding, status alias, status control, checkpoints, and complete outbox.
No external provider call occurs in that transaction.

AD04 does not narrow the provider-owned Firebase UID to the app's opaque-ID alphabet.
Legacy-compatible UIDs keep their existing AD02 document segment. Every other valid
AD01 UID is converted to a reserved, collision-free path segment from its exact
UTF-16LE bytes; the raw UID remains unchanged in scope and generation bindings. This
makes dots, `@`, slashes, and Unicode path-safe without accepting a caller-selected
path. An unprovisioned Auth-only identity can therefore enter and finish the Auth
deletion lane. Shared production AD02 adoption of this codec remains an explicit
closed integration gate; the current dormant AD02 grant path already rejects these
non-legacy UID shapes rather than granting unfenced access.

Every private job binding, provider binding, status control, operation receipt,
task, effect receipt, event receipt, task locator, and adapter call is bound to the
exact accepted lifecycle epoch in addition to project, tenant, UID, Auth generation,
and deterministic job/effect identity. A record from another lifecycle epoch cannot
authorize, satisfy, or resume an effect.

The operation envelope is exact. Replaying the same operation and envelope returns
its accepted result even after the intent or provider material expires. Changing the
same operation's request ID, status secret hash, or deletion semantics conflicts.
A separately authenticated operation for the same account generation converges on
the existing job and receives a distinct read-only status alias without changing the
winning operation.

Status reads require the opaque request ID plus its 32-byte secret. Missing, invalid,
or expired aliases return the same unavailable error. The response exposes only a
coarse phase, timestamps, message code, and provider outcome. It never exposes job
inventory, leases, adapter evidence, Auth data, or revocation material.

## Worker and effect safety

The deterministic outbox contains four ordered Firebase Auth tasks, one Apple
credential disposition task, one task for every AD01 required cleanup adapter, and a
completion reconciliation task. A bounded Firestore lease and monotonically
increasing fencing generation serialize workers. Effect receipts bind exact project,
tenant, UID, account generation, job, task kind, adapter, and fingerprint.

Workers inspect external state before mutating it and verify the result afterward.
For cleanup adapters, the mutating call's return value is never terminal evidence;
the worker performs a separate post-effect inspection. This makes a retry safe when
a process dies after the provider accepted an effect but before Firestore recorded
the checkpoint. Stale leases cannot overwrite newer work.
Transient failures back off from 60 seconds to 30 minutes; the twentieth failed
attempt requires attention and writes a server-private alert. An independently
authorized resume resets only the selected deterministic task. Exact-bound
nonterminal adapter evidence may advance after that resume, while terminal evidence
remains immutable. A task in `needsAttention` cannot be leased or invoke a provider
until that authorized resume returns it to pending. Unfinished jobs and status
controls have no automatic TTL.

Firebase Auth is staged as disable, revoke refresh tokens, delete exactly one user,
and verify absence. Every provider read and every mutating adapter boundary must
atomically compare the accepted account generation; a recreated UID is never
disabled or deleted. The installed Firebase Admin 13.10.0 type surface exposes
UID-only `updateUser`, `revokeRefreshTokens`, and `deleteUser` calls, so those calls
alone do not satisfy this precondition and no production Auth adapter is approved.
Auth deletion depends only on the durable authority fence and captured minimum
references, not on cleanup adapter completion. Cleanup may therefore remain pending
or require attention after Auth is absent, and the status reports that state
explicitly.

## Apple and cleanup adapters

Apple revocation material is referenced by an opaque, generation-bound identifier in
an isolated server-private collection. Raw authorization codes or refresh tokens are
never copied into jobs, tasks, logs, receipts, or status. A valid adapter verifies
revocation, then destroys the stored material and verifies both outcomes. Missing
material follows Apple TN3194: app-account deletion continues while the Apple
checkpoint truthfully records terminal manual-action guidance rather than claiming
revocation. Non-Apple accounts are terminal not-applicable; unknown relationships or
unavailable adapters require attention.
Verified Apple provider events are signature-verifier inputs, are replay-safe, and
must not predate the deletion acceptance binding. A future production verifier must
still prove current credential/material provenance in authorized staging.

AD04 defines the cleanup adapter protocol and verifies its exact result shape. It does
not implement the AD05 data-source adapters. Every required adapter result must be a
terminal, policy-version-matching result before completion. Missing, unsupported,
malformed, unknown, held-without-policy, or partial results block completion, but none
blocks the already fenced Auth deletion schedule.

## Safety net and orphan reconciliation

The candidate includes compatible version 1 interfaces for an Auth on-delete safety
net and a bounded scheduled orphan sweep. Both accept only verifier-produced events,
use deterministic account-generation jobs and replay receipts, and record observed
Auth absence without reconstructing Auth users. The sweep is limited to 100 verified
accounts per run. Neither handler is exported or scheduled in this change.

Completion requires verified Auth absence, terminal Firebase and Apple checkpoints,
all required adapter results, resolved custody, and the AD01 privacy and restoration
checks. Only then may reconciliation mark the durable job and AD02 lifecycle deleted.

## Activation decision

All AD04 activation and export constants are `false`, including the Firebase Auth
generation-conditional mutation proof gate and shared AD02 UID-path-codec proof gate.
The test-only Rules file denies all raw AD04 collections and is deliberately absent
from `firebase.json`. Production activation remains a later, explicit gate after a
safe Auth adapter/platform design, shared UID-path integration, AD05, and the
remaining architecture work are implemented and reviewed.
