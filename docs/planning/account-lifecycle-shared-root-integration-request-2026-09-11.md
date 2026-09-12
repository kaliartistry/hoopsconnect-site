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

## Agreed split route contract from Workstream A

- Authenticated request path: `/account/delete`
- Public read-only recovery path: `/account/deletion/status`
- Authenticated local-work path: `/account/deletion/reconcile-device`
- The route guard must evaluate a device-bound deletion receipt before the
  ordinary signed-in/signed-out redirect. A successful request explicitly
  hands off to the public status path before Auth can disappear.
- On an ordinary cold start, a signed-out account with an exact accepted or
  acceptance-unknown receipt goes directly to `/account/deletion/status`; it
  does not need a separate account-deletion intent. A stale-generation,
  cross-account or cross-device receipt never gets that precedence.
- A saved request receipt is local recovery authority only for the read-only
  status endpoint. It is never authorization for another deletion request.
- Status recovery never starts provider reauthentication and never creates a
  new request ID.
- The app must not redirect a deleting or cleanup-pending person between login
  and deletion in a loop after Firebase Auth disappears.

| Account/session condition | Required route result |
| --- | --- |
| Active current-generation account, explicit navigation | Open `/account/delete` and allow the injected local-work check |
| Current device has unresolved official work | Hand off to `/account/deletion/reconcile-device`; return to `/account/delete` only with an exact-bound resolved manifest |
| Blocked or suspended current-generation account | Keep `/account/delete` reachable; fail closed on any operation not explicitly allowed by lifecycle authority |
| Provider reauthentication cancelled | Stay on deletion overview, report cancellation and send no prepare or request call |
| Accepted request or deleting account with an exact device-bound receipt | Hand off to `/account/deletion/status`, without reauthentication or a new request |
| Auth user absent, server cleanup pending, saved receipt present | Keep `/account/deletion/status` reachable and label Auth removal separately from cleanup completion |
| Cleanup needs operational attention, saved receipt present | Keep `/account/deletion/status` reachable; do not offer a second deletion request |
| Verified complete receipt | Show the completed result once, then permit an explicit exit |
| Signed out with no saved receipt | Use the ordinary sign-in route; do not infer that deletion exists |
| Stale generation or mismatched receipt | Deny account authority and use a safe recovery/support path; never bind it to the current account |

The dormant `candidateRouteForAccountLifecycleV2` mirrors these three paths and
tests the receipt-aware signed-out projection. Workstream A owns the production
route guard and mounted handoff screens; Workstream F does not import or change
those roots in this candidate.

## Interfaces requested from the integration owners

### A: auth, provider and navigation seam

Provide a reviewed adapter for the candidate reauthentication interface:

- password reauthentication through the current Firebase user;
- Google reauthentication with cancellation distinguished from failure;
- Apple reauthentication with its server-staged revocation material represented
  on the client only by an opaque reference;
- an explicit Apple relationship state of linked, not linked or unknown;
- current project, tenant, UID, generation, lifecycle epoch and recent-auth
  binding for the subsequent prepare call;
- one unforgeable session-attempt ID, monotonic epoch and opaque nonce shared
  by reauthentication, prepare and submission; provider and prepare results
  must return the exact binding and the client must recheck it after every
  asynchronous boundary; and
- an account switch at any boundary must discard staged provider material,
  stop the old flow and prohibit later request or cleanup work under mixed
  authority; and
- no deletion request when the provider window is cancelled or its result is
  ambiguous.

A also owns the eventual settings/profile entry point and the router/auth-state
projection. F requests those files only after the route matrix is accepted.

### D: per-device official-work seam

Implement the candidate device-cleanup interface against the agreed offline
journal contract. The adapter must enumerate the exact device manifest,
distinguish unaccepted from accepted and receipt-unknown operations, prohibit
discard of receipt-unknown work, and bind any consent to that device and
manifest checksum. Every inspection, decision and cleanup call must bind the
exact project, nullable tenant, `accountId`, random `accountGeneration`,
lifecycle enforcement epoch and `deviceSessionId`; the saved receipt and
local-work summary must match every field. Another account,
recreated generation or device's receipt/consent must not be reused.

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
authProjectIdV2
authTenantIdV2
authUidV2
generationHash
expectedLifecycleEpochV2
sessionAttemptIdV2
sessionAttemptEpochV2
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

The first five identity fields come from the existing AD04 prepared intent.
The transport wrapper adds the two current session-attempt fields while
sanitizing the intent into this client DTO; the strict client adapter rejects
any mismatch before impact review. The wrapper must carry the same binding
into acceptance, and must never select a current Firebase user after an await
without revalidating that exact binding.

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
- Prove retryable rate-limit/unavailable outcomes reuse the exact operation,
  request and status capability, while `never` and operator-resolution classes
  retain a durable terminal rejection fence and cannot create replacement IDs,
  including after restart.
- Prove an unresolved last-owner request is accepted and fenced, reports the
  actual AD04 progression `processing` / `AD_DELETION_REQUESTED`, then
  `accountRemovedCleanupPending` / `AD_ACCOUNT_REMOVED_CLEANUP_PENDING`, and
  finally `attentionRequired` / `AD_CLEANUP_ATTENTION_REQUIRED`; personal
  deletion must continue while shared operations remain suspended.
- Prove ordinary signed-out cold starts with exact accepted or unknown receipts
  route to public status without extra intent, while stale or mismatched
  receipts use the ordinary safe route.
- Switch accounts independently during provider reauthentication, prepare,
  submit and local cleanup; each old operation must stop at that boundary and
  no request, receipt transition or cleanup may run under mixed binding.
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
