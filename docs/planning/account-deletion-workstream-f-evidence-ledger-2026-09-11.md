# Workstream F account-deletion candidate evidence ledger

Status: **dormant implementation candidate; G1-G11 remain closed**

Candidate base: `6e74ba13faf316da2c506c2cafcfca985dd774cc`

Candidate branch: `codex/qa-lifecycle-candidate`

The normative record remains
`contracts/account_deletion/v1/release_gates.json`. This ledger does not assign
an owner, add a normative evidence reference, mark a gate passed, or permit
activation. Every normative gate still has `owner: null`, `evidenceRefs: []`,
and `passed: false`; `activationAllowed` remains `false`.

## Reconciliation of the existing deletion packets

| Packet | Reused boundary | Candidate addition in Workstream F | Still required before integration or activation |
| --- | --- | --- | --- |
| AD01 | Frozen request, status, retention and G1-G11 contracts | Strict client-side G1-G11 parser pins every exact gate name, closed status and ordered required-evidence list; a passed gate requires one ordered immutable evidence reference per requirement | Authoritative policy owners and evidence; no AD01 fixture or policy registry was changed |
| AD02 | Dormant generation/lifecycle fence and client route evaluator | The dormant route evaluator mirrors A's split contract: `/account/delete`, public `/account/deletion/status`, and `/account/deletion/reconcile-device`; an exact accepted, complete or acceptance-unknown receipt hands even an ordinary signed-out cold start to status before Auth redirects, while stale and mismatched receipts do not | Trusted issuer, migration, production Rules and shared-root integration remain closed |
| AD03 | Dormant transfer and suspend-to-custody transaction | Impact review distinguishes ordinary departure, verified transfer, prepared custody suspension and unresolved last-owner custody. The unresolved case is submittable: AD04 accepts and fences it, reports `processing` while personal deletion advances, then `accountRemovedCleanupPending`, and finally `attentionRequired` / `AD_CLEANUP_ATTENTION_REQUIRED` after required cleanup while shared authority remains fenced | Named operators, production command authority, rehearsals and integration into all membership/capability transactions |
| AD04 | Dormant prepare, accept, worker, status, provider-event and orphan-reconciliation orchestration | Synthetic-only gateway, strict provisional impact parser, exact accepted/status parsers, saved request receipt, status-first ambiguous-response recovery and truthful client phases | Approved production exports, App Check/identity verifier, live repositories, Auth adapter, worker scheduling, monitoring and shared UID-path decision |
| AD05-A | Exact 27-row registry, sealed inventory/receipt kernel and T/R-family candidate adapters | No duplicate adapter implementation | Approved retention rows, authoritative inventories, registered live classifiers/verifiers and concrete V/E/D/provider implementations |
| AD05-B | Identity suppression prerequisite and account-person claim candidate | UI and state language preserve official sporting history and do not call account deletion identity erasure | AD06 privacy epoch, guardian/minor policy, live raw/public/export coverage, versioned identity material treatment and restore/rebuild proof |
| AD05-C | Account-owned versus shared-workflow candidate adapters | Consequence and custody copy keep shared league records separate from the account | Live mixed-profile design, complete source ownership/provenance, real provider/processor adapters and residue verification |
| AD05-D | Synthetic Storage/media evidence vocabulary | No Storage operation or terminal-media claim | Live version/derivative inventory, token/CDN/cache closure, bucket retention/hold policy, restore suppression and an idempotent provider-backed worker |
| AD05-E | Synthetic FCM/preference and uncertain-delivery evidence | Local cleanup result reports notification detachment separately from server completion | AD02/AD04 uncertain-dispatch reconciler, live token/preference migration, provider semantics, production Rules/handlers and AD07 device behavior |
| AD06 | Reserved by the existing architecture for privacy epoch and derived/public suppression | Not implemented here | Reviewed privacy-epoch contract and integration that cannot alter certified official-stat bytes or hashes |
| AD07 | Reserved by the existing architecture for per-device journal quarantine, consent and teardown | Device-local interface requires an exact manifest/consent and blocks discard when a receipt is unknown | D/F contract for the real offline journal, secure device-scoped consent, cross-device recovery and teardown proof |

## Candidate client evidence

The candidate client is deliberately standalone and dependency-injected:

- `account_deletion_candidate_controller.dart` accepts synthetic or emulator
  dependencies only and rejects live-looking dependencies while its activation
  constant is false.
- Reauthentication is explicit for password, Google and Apple. Provider
  cancellation returns to the reachable screen and sends no deletion request.
- Apple material is represented only by an opaque server reference. Missing
  material produces truthful guidance and can never be displayed as verified
  revocation.
- A request receipt is persisted before transport. A lost response enters an
  acceptance-unknown state and checks the same request through its saved
  read-only secret before any retry or reauthentication.
- Frozen retry classes are enforced. Identity mismatch, invalid request and
  operation conflict are terminally non-retryable; custody/policy readiness
  requires an operator. Those terminal outcomes retain a durable rejection
  fence across restart. Expired or changed impact requires a new preparation;
  rate-limit/temporary retries reuse the exact saved operation and request IDs.
- `processing`, `Auth removed / cleanup pending`, `attention required`, and
  `complete` are separate states. Only the fully verified server result is
  presented as complete. Unresolved custody uses this exact observable AD04
  progression; the client does not invent a `CUSTODY_CONFLICT` status phase or
  message code.
- Reauthentication, prepare and submission share one unforgeable operation
  binding across exact project, nullable tenant, UID, account generation,
  lifecycle enforcement epoch and session-attempt ID/epoch/nonce. Provider,
  prepared-impact and accepted-request results carry that binding. A switch at
  any asynchronous boundary stops the flow, clears staged provider material,
  sends no later request, and never applies cleanup under the new account.
- Local journal inspection happens before submission. Receipt-unknown work
  cannot be discarded; any consent is bound to one exact manifest on one
  device. The local-work summary, saved receipt and cleanup call all bind exact
  project, nullable tenant, `accountId`, `accountGeneration`, lifecycle epoch
  and `deviceSessionId`; cross-account,
  recreated-generation and other-device receipts cannot read status or clear
  current data. Server deletion and device cleanup are reported independently.
- The responsive screen is tested at 375, 768 and 1440 logical pixels, with a
  phone pass at 200 percent text scaling. It is not routed, imported by an auth
  root, or reachable from `main.dart`.

These are candidate review aids, not authoritative provider, staging, privacy,
restore, public-route or store evidence.

## G1-G11 status and exact remaining decisions

| Gate | Normative status | Candidate-only review aid | Decision or proof still missing |
| --- | --- | --- | --- |
| G1 controller and retention | closedPendingAuthoritativeDecision | Strict policy/gate parsing and retained-category language | Name the controller and decision maker; approve every retention row and disclosure version |
| G2 player and minor rights | closedPendingAuthoritativeDecision | Official history is kept distinct from the account; public completion is not inferred | Approve account-person claims, guardian/non-account requests, field-level publication and ranking privacy treatment |
| G3 recoverable ownership | closedPendingOperationalProof | Last-owner unresolved custody accepts only through `suspendToCustody`; actual AD04 status advances through `AD_DELETION_REQUESTED` and `AD_ACCOUNT_REMOVED_CLEANUP_PENDING` before remaining `attentionRequired` with `AD_CLEANUP_ATTENTION_REQUIRED`, while personal deletion continues and shared operations remain fenced | Name custody/recovery/infrastructure owners and rehearse transfer plus last-owner suspension |
| G4 legacy migration inventory | closedPendingOperationalProof | Strict generation-bound client and packet contracts are reused | Produce a fresh authorized Auth/profile/membership inventory, generation migration, owner bootstrap and source/media classification with suppression-first proof |
| G5 complete fencing | closedPendingImplementationAndProof | Dormancy test proves this client candidate is unreachable; AD02-AD05 candidates provide test-only fences | Integrate and prove production Rules, commands/receipts, provisioning, notifications, Storage, legacy/public reads and old-client denial |
| G6 provider configuration | closedPendingOperationalProof | Provider-aware reauth/revocation seams and truthful unknown/manual states | Pin compatible SDKs and Apple identifiers; approve material custody; prove provider events, App Check, domains/CSP, indexes and least-privilege workers in authorized staging |
| G7 deadline and operations | closedPendingAuthoritativeDecision | Processing and operator-attention states do not claim completion | Approve completion timing, staffing, alerts, backlog capacity, delivery, processor workflow and outage handling |
| G8 restore and retained copies | closedPendingOperationalProof | Client never equates Auth absence with cleanup completion | Approve backup/PITR/object/log/processor retention and key custody; prove durable suppression and restore-before-traffic rehearsal |
| G9 official-stat integration | closedPendingReview | Consequence copy and local-work model preserve official facts and receipt ambiguity | Approve the identity/evidence/privacy addendum; build the legacy privacy adapter; prove no certified-hash conflict and no raw/export/public bypass |
| G10 end-to-end evidence | closedPendingOperationalProof | Unit/widget tests cover password/Google/Apple outcomes, response ambiguity, same-operation retry, concurrent taps, accepted unresolved custody, exact AD04 wire progression, cleanup retry, ordinary signed-out receipt handoff, stale/mismatched receipts, and account switches at reauth/prepare/submit/cleanup boundaries | Pass the complete applicable scenario matrix with independent disposition/custody/public review, verified Auth absence, Auth-before-blocked-cleanup ordering and zero unresolved required adapters |
| G11 public and store consistency | closedPendingOperationalProof | Candidate screen has responsive local rendering tests | Read back the live web route/policy, capture authorized mobile and PWA evidence, approve reviewer steps and reconcile App Store privacy plus Google Data Safety/deletion URL wording |

## Verification command set

Run from the repository root:

```sh
flutter analyze --no-pub
flutter test --no-pub test/features/account_deletion test/models/account_deletion test/services/account_lifecycle_candidate_adapter_v2_test.dart
npm --prefix functions run build
npm --prefix functions run test:contracts:no-build
node scripts/check_repository_safety.js
git diff --check
```

Passing these commands establishes only local candidate quality and dormancy.
It cannot replace the named owner, authoritative provider readback, isolated
staging, restore rehearsal, independent review or store evidence required by
the normative ledger.
