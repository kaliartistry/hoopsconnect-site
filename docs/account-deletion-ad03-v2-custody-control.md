# HoopsConnect AD03 dormant V2 ownership and custody control

Status: **isolated candidate only; production activation prohibited**

`activationAllowed: false`

Implementation base: `f3a07efe0ef408f7a29fdeaa5e2e56e848b0cd8f`

Architecture pin: `9a9d0150244fc124bbc8ab1697fba177a3c862de8b7099c5c684d02ed8537832`

AD03 supplies the missing ownership-transfer and last-owner custody prerequisite
between the merged AD02 lifecycle fence and future AD04 deletion acceptance. It
does not export a callable, modify production Rules, bootstrap an owner, name a
production custodian, mutate Firebase Auth or IAM, delete an association, or
activate account deletion.

## Exact authority and storage boundary

Recoverable ownership is not inferred from a role, legacy profile, email, name,
or UID alone. Every owner binding includes exact Firebase project, nullable
tenant, UID, random AD02 account generation `G`, lifecycle epoch `E`, a schema
version, and a deterministic opaque binding reference. The control rejects
mixed lanes, duplicate owners, malformed generations, unknown fields, and
unrecognized states.

The candidate uses physically separate control and recovery-evidence lanes:

| Record | Root lane | Tenant lane |
| --- | --- | --- |
| Ownership control | `associationOwnershipV2Root/{associationId}` | `associationOwnershipV2Tenants/{tenantId}/associations/{associationId}` |
| Recipient eligibility | `recipientEligibilityV2Root/{uid}` | `recipientEligibilityV2Tenants/{tenantId}/users/{uid}` |

Transfer intents, departure receipts, custody policies, custody cases, and
minimal audit events are server-private subcollections of the exact ownership
control. The emulator-only Rules deny all client access to them. `firebase.json`
continues to reference the unchanged production Rules.

The separate eligibility record contains no recovery-channel value. It records
only exact P/T/UID/G/E, an opaque evidence reference, verified/present states,
and a bounded validity interval. A future trusted provider adapter owns its
production creation and invalidation; AD03 includes no writer for it.

## Transfer protocol

The transfer protocol is `prepare -> recipient acceptance -> commit`:

1. Prepare rechecks the initiating owner's AD02 lifecycle and membership inside
   the same transaction, requires `association.manage`, proves an exact owner
   binding in the current versioned control, and snapshots an eligible
   recipient. One intent is pending per association.
2. The exact recipient explicitly accepts or declines. Acceptance requires a
   provider-verified AD02 token, `auth_time > reauthAfterSecV2`, and an absolute
   reauthentication age of at most 300 seconds. Lifecycle, membership, control,
   intent, and non-PII recovery evidence are read inside the transaction.
3. Commit rechecks the control version and the recipient's active exact
   lifecycle, membership, capability, Auth-presence evidence, and verified
   recovery evidence. The recorded acceptance `auth_time` must still be
   strictly newer than the recipient's current AD02 reauthentication boundary.
   Commit also binds the intent's embedded project, tenant, association, and ID
   to the exact document path. Only then does one transaction replace the
   departing owner, close the intent, and write a fixed-length hashed-ID
   minimal audit event.

Transfer expiry is processed lazily inside these same transactions; no
production scheduler or sweeper is introduced by AD03. After
`expiresAtSecV2`, recipient accept/decline calls fail with
`AD03_TRANSFER_NOT_READY` and cannot return or alter stale consent. A current
exact recoverable owner can either submit the expired intent to the standalone
commit operation, which atomically marks it `expired`, clears
`transferPending`, and then reports `AD03_TRANSFER_NOT_READY`, or prepare a
different intent ID. That replacement transaction closes the old intent and
creates the new pending intent with one control-version advance. The expired
record clears the prior acceptance authentication time, so a replacement must
obtain fresh explicit consent. Exact replacement retries return the existing
new intent; changed recipient or version data under its ID conflicts.

An accepted recipient who declines, loses Auth, changes `G`/`E`, becomes
inactive, loses `association.manage`, or loses verified recovery eligibility is
never installed as owner. The departing owner may then choose the separately
confirmed custody route. Normal association operation is not suspended merely
because a transfer is pending.

## Last-owner deletion seam

`applyOwnerDepartureInTransactionV2` is the transaction-composable AD04 seam.
It accepts only a branded exact active binding returned by the AD02 evaluator
and must run before the future deletion transaction stages writes. On every
first execution it re-reads lifecycle and membership in that same transaction
and revalidates exact P/T/UID/G/E, active state, association, reauthentication
boundary, and `association.manage`. It reads and writes the same ownership
control that transfer commits use. Exact completed receipt replay is read-only.

- A non-last owner can leave with `ordinary`; the exact owner is removed and at
  least one recoverable owner remains. Any pending transfer is closed as
  `cancelledByOwnerDeparture` in that same transaction because the owner-set
  change invalidates its prepared impact and any recorded recipient consent;
  transfer and acceptance must then be renewed against the new control version.
- A last owner cannot use `ordinary`. A changed control version forces renewed
  impact confirmation, preventing two concurrent owners from each assuming the
  other will remain.
- `transferThenDelete` succeeds only by committing an already accepted,
  still-eligible recipient in the same transaction.
- `suspendToCustody` removes the last owner and suspends normal association
  operation. A configured fixture-only policy creates `suspendedToCustody`.
  Missing named custody creates `custodyRequired` plus an `operatorUnassigned`
  case with safe code `CUSTODY_CONFLICT` and the exact AD01 outcome
  `policyBlockedButDeletionMustReceiveOperationalResolution`.

The missing-policy result is intentionally asymmetric: normal association work
fails closed and operational attention is required, but
`personalDeletionMayContinueV2` remains true. It is neither a claim that named
custody succeeded nor permission to keep the person's account indefinitely.
Production cannot reach this candidate because activation remains closed.

Departure receipts bind exact P/T/UID/G/E, operation, choice, expected control
version, transfer/case references, and result. Exact retries return the same
result; changed payload under the same operation conflicts.

## Custody and recovery

The only complete custody policy in fixtures is explicitly
`configurationClassV2: testFixture` and `decisionStateV2: testOnly`. Its
version and canonical configuration fingerprint are copied into the recovery
case and required in the service command, so a same-ID reconfiguration makes an
older command unusable. The module has no production command authorizer, and
`productionCustodyActivationReadyV2` always returns false.

Fixture recovery requires:

1. a named test operator and case owner in the exact policy;
2. explicit fresh acceptance by an exact active successor with current
   `association.manage` and verified recovery eligibility, recording the
   provider `auth_time` separately from the acceptance event time;
3. a separately branded, short-lived test service command carrying an opaque
   recovery-review evidence reference; and
4. a final transaction that rechecks policy, case, control, and successor before
   restoring `operating` with the successor as recoverable owner, including
   requiring the accepted `auth_time` to remain newer than the current AD02
   reauthentication boundary.

Audit records contain control versions, opaque owner/counterparty references,
case/intent/policy references, an enumerated event type, and time. They contain
no name, email, contact channel, free text, role, raw recovery evidence, or
credentials. Restricted intents, cases, and receipts remain personal data and
require later approved retention/disposition.

## Association operation barrier

For the eight ordinary mutation classes, `operating` and `transferPending`
defer to ordinary authority. In
`custodyRequired`, `suspendedToCustody`, or `recoveryReview`, the contract
suspends normal membership, invite, role, roster, game-assignment, stat-entry,
review/certification, and publication mutation.

Deletion/privacy cleanup and trusted or audited recovery require their future
dedicated server authorities in every control state. Historical presentation
never receives an AD03 allow in any state; it returns
`ad06CurrentPrivacyDecisionRequired`, preserving AD06 ownership of privacy
epochs and public/raw/export projections.

## Evidence and remaining activation gates

The candidate tests cover strict parsing, exact root/tenant separation,
recipient freshness, transfer replay/conflict, accept/decline/eligibility loss,
same-control owner-departure races, stale AD02 authority, cross-scope/path
redirection, maximum-length IDs, pending-transfer departure, missing-policy
suspension, version/fingerprint-bound fixture custody recovery, minimized audit
shape, and transitive dormancy. A real Firestore emulator exercises optimistic
transaction retries rather than only a helper simulation.

Production activation remains blocked by at least:

- **G3:** named production custody/recovery operator, case owner, escalation
  coverage, independent infrastructure owner, and rehearsed operating process;
- **G4:** authorized owner inventory/bootstrap and migration evidence;
- central integration of the custody barrier into membership, invite, roster,
  assignment, stat, review/certification, and publication transactions;
- a trusted production recipient-eligibility writer and custody-command
  authorizer; and
- AD04 acceptance integration and repeated integrated deletion races.

AD06 still owns privacy epochs and crash-safe public/projection custody. AD07
still owns per-device encrypted local-journal quarantine and consent. AD03 does
not amend official-stat canonical bytes, certified hashes, actor provenance, or
the local journal contract.
