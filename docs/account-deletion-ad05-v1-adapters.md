# Account deletion AD05-A adapter packet

Status: **dormant candidate; no policy approval, activation, export, deployment, or provider mutation**

AD05-A supplies private adapter records, trusted inventory boundaries, a generic
transactional-document exact-once kernel, and 27 AD04-compatible adapter
wrappers. It does not connect those wrappers to `functions/src/index.ts`, change
`firebase.json`, change deployed Firestore or Storage Rules, activate an AD01
retention decision, or implement any production provider, Storage-version,
device, processor, backup, public-export, or Auth mutation.

The exact implementation baseline is
`08b1522a7ddc26d64d8fa7e3572af6764d1a8888`. The normative AD01 registry still
has `policyVersion: null` and `activationApproved: false`. Every normative
wrapper therefore returns a nonterminal `blocked` AD04 result before it can
call an injected runtime. Synthetic approved policy values exist only in the
AD05 test fixture and the explicitly named test-only factory.

## Files and boundaries

- `ad05_records.ts` defines exact-schema private bindings, sealed manifests,
  manifest items, item receipts, continuations, deterministic fingerprints,
  and hashed private record paths. The binding includes exact Firebase project,
  tenant, UID string and UTF-16LE UID bytes, account generation, deleting
  lifecycle epoch/state, internal job, AD04 task/effect fingerprint, adapter and
  effect versions, policy decision/version/action, and manifest identity/version.
- `ad05_inventory.ts` accepts only a trusted adapter-owned inventory source or a
  previously parsed sealed manifest. Its input has no caller-supplied path,
  name, email, jersey number, similarity lookup, or reverse-index authority.
  Unknown schema, unclassified records, missing provenance, incomplete pages,
  missing independent reference coverage, duplicates, and binding drift fail
  closed. Item and manifest ordering and identities are deterministic SHA-256.
- `ad05_effects.ts` applies one transactional-document item by reading the bound
  source version and deterministic receipt in one transaction. An injected
  callback receives only a source-scoped write capability. The source write and
  immutable receipt commit together. Exact replay returns the receipt; any
  changed scope, generation, lifecycle, job, task, effect, adapter, version,
  policy, action, manifest item, or source version conflicts.

Every manifest consumer uses one binding assertion. The manifest ID must equal
the binding's source-manifest ID, and both the manifest version and inventory
source version must equal the binding's source-manifest version. The manifest
parser also requires its two version fields to agree. Re-signing a changed
manifest with the public SHA-256 function cannot bypass these comparisons.

Trusted inventory sealing creates the canonical manifest once at its private
manifest path. Exact retries are read-only replays; the same manifest ID and
version with different contents conflicts. Execution never auto-registers a
missing manifest. Before prefix-receipt checks, external verification, or
finalization, the supplied manifest must exactly match that stored canonical
record. Each item transaction repeats this check before reading a receipt or
source record and proves that the item is the exact member at its ordinal.

- `ad05_adapters.ts` declares exactly the 27 AD01/AD04 adapter IDs and their
  `retention.<adapterId>` decisions. Protection families are `T`
  (transactional document), `V` (versioned/object material), `E` (external or
  processor), `D` (device-local), and `R` (read/evidence verification). AD05-A
  has mechanical seams only for T and R. V, E, and D always return
  `unsupported`; a T or R row without a concrete injected runtime also returns
  `unsupported` under a synthetic approved test policy.

## Exact-once and recovery semantics

An item receipt key is deterministic for the AD04 task effect and sealed
manifest item. Before mutation, the transaction validates the complete binding,
the immutable item fingerprint, the source path hash, and the expected source
record version. The injected callback can write only that source path and must
return an after-version that matches the record it wrote. The receipt is then
written in the same transaction.

This closes the lost-response and lease-expiry gap: after commit, a second
worker sees the exact receipt and replays without invoking the callback. A
changed binding at the same receipt key conflicts. A crash before the
transaction changes nothing. A crash after commit but before returning an
updated cursor replays the committed item, then advances. The cursor binds its
next ordinal and next item ID to the sealed manifest, so it cannot skip an
uncommitted item. Pages are capped at 25 items and manifests at 100.

Receipts are completion evidence for one versioned effect and are immutable.
A receipt also binds the exact canonical manifest fingerprint. Receipt replay,
cursor-prefix validation, and finalization reject a receipt from any alternate
manifest while retaining the stable receipt path that fences re-execution.
A later hold release or changed disposition requires a new effect/version; it
cannot rewrite an old receipt.

Item classification controls execution. An `applicable` item requires a policy
action other than `notApplicable`, invokes the transaction-owned callback, and
must advance the source record version. A `notApplicable` item never invokes
the mutation callback or writes its source. It atomically records a
`notApplicableVerified` receipt with equal before/after versions. Receipts bind
the classification and the explicit `mutated` or `notApplicableVerified`
outcome. A `notApplicable` adapter binding containing any applicable item fails
before execution. No implicit already-satisfied mutation outcome exists.

## Completion and AD04 wire compatibility

AD05 manifests, receipts, cursor state, source paths, versions, and provenance
stay private. Chunk progress returns `null`; it does not manufacture a
nonterminal AD04 public result. An AD04-compatible terminal adapter result is
possible only after all of the following:

1. an exact, complete, bounded, sealed manifest parses successfully;
2. every manifest item has an exact immutable receipt;
3. an independent full-reference verifier, not a reverse index, reports zero
   remaining references against that manifest;
4. a separate final verifier confirms source disposition, public privacy,
   restore suppression, and that unrelated associations remain unchanged; and
5. the policy action and hold boundary are internally consistent.

Missing receipts or remaining references return private progress (`null`).
Malformed or conflicting evidence fails closed. Normative policy attention is
returned as `blocked`; missing mechanical guarantees are returned as
`unsupported`. Only a fully verified result preserves the existing AD04 public
`AdapterResultContract` shape.

`firebase_auth_identity` is R-family evidence-only. Its runtime can only read
and verify exact-bound AD04 Auth checkpoint and effect-receipt evidence for the
same project, tenant, UID, generation, lifecycle epoch, job, task effect, and
policy version. It has no Auth mutation capability and cannot disable, revoke,
delete, or otherwise change an Auth user.

Completion evidence binds the deterministic ordered set of item-receipt
fingerprints and its latest commit time. Remaining-reference evidence names and
binds the inventory source, requires a distinct independent source plus an
independence proof, and must be verified no earlier than the latest receipt.
Final evidence binds both the receipt-set fingerprint and the fingerprinted
remaining-reference evidence, and its verification time must be no earlier
than either. Cached pre-mutation evidence therefore cannot close an adapter.

These fields are structural AD05-A fences, not activation proof. The sealed
classification and source version are still trusted assertions. Distinct
source IDs and an independence-proof ID do not themselves authenticate
operational independence, and caller-provided timestamps establish ordering
but not causal post-commit freshness. Activation remains blocked until concrete
schema-version classifiers, registered independent verifier implementations,
authoritative commit-version evidence, and causally post-commit scan evidence
are reviewed and approved. The fixture keeps all four obligations false.

## Test and release posture

The focused Node suite covers registry exactness, duplicate/missing/extra/future
schema rejection, dormancy, strict binding, trusted provenance, source-version
conflicts, atomic replay, lost response, crash recovery, cursor fencing,
cross-scope isolation, adversarially re-signed manifest drift, classification
and outcome consistency, receipt-set freshness, independent reconciliation,
final verification, immutable receipts, unsupported protection families, and
Auth evidence-only behavior. The emulator-only Rules file denies every client,
including a claimed super-admin, access to private AD05 manifests, receipts,
and continuations.

The dormancy suite pins production entrypoints, `firebase.json`, deployed Rules,
AD01 through AD04 sources, the retention registry, and all activation/export
flags. The emulator fixture is not referenced by `firebase.json`.

AD05-A does not close production obligations. Authoritative policy decisions,
real source inventories and schema coverage, per-row implementations, provider
and processor guarantees, Storage version handling, device consent/recovery,
backup expiry and restore suppression, public/export verification, Auth
generation-conditional mutation proof, production Rules, handlers, exports,
deployment, and store disclosure/release review all remain closed.
