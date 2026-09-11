# Account lifecycle shared-root integration request

Status: **proposed A/F/I contract; no shared root changed**

Requester: Workstream F

Requested owners: A for auth/router/profile integration; D for the official-stat
local-journal adapter; C for notification teardown; I for shared production
roots, activation surfaces and final integration.

This request does not authorize a production handler, Firebase mutation, Rules
or configuration change, deployment, store submission, gate update or
activation. The Workstream F screen and orchestration remain unreachable and
synthetic-only until the owners below accept and implement the contract.

## Proposed route contract for A/F agreement

- Canonical path: `/delete-account`
- Proposed route name: `accountDeletion`
- The route guard must evaluate deletion recovery before the ordinary
  signed-in/signed-out redirect.
- A saved request receipt is local recovery authority only for the read-only
  status endpoint. It is never authorization for another deletion request.
- Status recovery never starts provider reauthentication and never creates a
  new request ID.
- The app must not redirect a deleting or cleanup-pending person between login
  and deletion in a loop after Firebase Auth disappears.

| Account/session condition | Required route result |
| --- | --- |
| Active current-generation account, explicit navigation | Open deletion overview and allow the injected local-work check |
| Blocked or suspended current-generation account | Keep `/delete-account` reachable; fail closed on any operation not explicitly allowed by lifecycle authority |
| Provider reauthentication cancelled | Stay on deletion overview, report cancellation and send no prepare or request call |
| Deleting account with a saved receipt | Open status recovery directly, without reauthentication or a new request |
| Auth user absent, server cleanup pending, saved receipt present | Keep the deletion status screen reachable and label Auth removal separately from cleanup completion |
| Cleanup needs operational attention, saved receipt present | Keep the status screen reachable; do not offer a second deletion request |
| Verified complete receipt | Show the completed result once, then permit an explicit exit |
| Signed out with no saved receipt | Use the ordinary sign-in route; do not infer that deletion exists |
| Stale generation or mismatched receipt | Deny account authority and use a safe recovery/support path; never bind it to the current account |

The existing dormant `candidateRouteForAccountLifecycleV2` already maps
deleted lifecycle state to `/delete-account`. A must decide the full guard
precedence and receipt-aware signed-out projection before any shared-root edit.

## Interfaces requested from the integration owners

### A: auth, provider and navigation seam

Provide a reviewed adapter for the candidate reauthentication interface:

- password reauthentication through the current Firebase user;
- Google reauthentication with cancellation distinguished from failure;
- Apple reauthentication with its server-staged revocation material represented
  on the client only by an opaque reference;
- an explicit Apple relationship state of linked, not linked or unknown;
- current project, tenant, UID, generation, lifecycle epoch and recent-auth
  binding for the subsequent prepare call; and
- no deletion request when the provider window is cancelled or its result is
  ambiguous.

A also owns the eventual settings/profile entry point and the router/auth-state
projection. F requests those files only after the route matrix is accepted.

### D: per-device official-work seam

Implement the candidate device-cleanup interface against the agreed offline
journal contract. The adapter must enumerate the exact device manifest,
distinguish unaccepted from accepted and receipt-unknown operations, prohibit
discard of receipt-unknown work, and bind any consent to that device and
manifest checksum. Another device's consent must not be reused.

### C: notification and cache teardown seam

Provide device-local cleanup that stops protected listeners, detaches the exact
FCM installation registration, clears ordinary account caches and cancels local
notifications only after the server fence is accepted. Failure must remain
visible as device cleanup pending and must not rewrite the accepted server
request as rejected.

### I: transport and shared production seam

When G1-G11 permit reviewed staging work, provide narrowly scoped wrappers for
the existing AD04 prepare, request and read-only status contracts. The client
requests this sanitized prepare DTO:

```text
schemaVersion
intentId
policyVersion
impactVersion
expiresAt
custodyChoice
ownershipResolution
isLastRecoverableOwner
associationId
serverDeletionContinuesIndependently
sportingHistoryIsNotAccountData
```

The accepted and status responses must remain the existing strict AD04 wire
shape. Status secrets must be generated with cryptographic randomness, stored
separately from ordinary caches and never logged, sent to analytics or placed
in URLs. I must select and review a durable device receipt store for iOS,
Android and web before replacing the in-memory candidate store.

I retains ownership of `functions/src/index.ts`, production Rules,
`firebase.json`, provider credentials, scheduled workers, App Check, indexes,
IAM and every activation flag. F requests no changes to those surfaces in this
packet.

## Shared-root patch requested after contract acceptance

1. A adds the route and guard precedence, plus a profile/settings entry point.
2. A supplies provider-profile and reauthentication adapters without placing
   provider secrets in the deletion receipt.
3. D supplies the exact local-journal adapter and per-device consent model.
4. C supplies listener, FCM, cache and local-notification teardown.
5. I supplies emulator/staging transport wrappers first and keeps production
   exports dormant until every gate is genuinely passed.
6. F then replaces the synthetic-only boundary with an explicitly reviewed
   integration constructor; the activation constant is not toggled in place.

## Integration acceptance tests

- Exercise every route row above without a redirect loop on phone and web.
- Cover password, Google and Apple success, cancellation, retry and unknown
  relationship/material results.
- Prove a response lost after acceptance reuses one request ID and checks
  status before any retry.
- Prove last-owner deletion cannot submit without a transaction-bound AD03
  transfer or prepared custody receipt.
- Prove Auth deletion is scheduled only after the durable fence/minimum
  references, can continue while cleanup is blocked, and never makes cleanup
  appear complete merely because Auth is absent.
- Exercise suspended/missing profiles, stale generations, repeat requests,
  cross-device journals, restore-before-traffic and public/raw/export
  suppression in isolated environments.
- Read back authorized provider and staging state; local fakes and emulator
  assertions alone are insufficient for a release decision.
- Keep the normative G1-G11 ledger closed until each named owner and required
  immutable evidence reference actually exists.
