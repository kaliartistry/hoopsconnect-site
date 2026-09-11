# Stage 2 courtside recovery integration request

Status: candidate complete and dormant. No deploy or production activation requested.

Baseline: `6682f06`

## Candidate delivered

- `CourtsidePreparationMaterial` converts one exact assigned-game result plus authoritative assignment, rules, calculator, policy, roster-snapshot, accepted-head, and candidate revision ID/number/hash/scope into the existing `PreparedGameRecoveryPackage`.
- `CourtsideRecoveryOrchestrator` serializes capture for one account/device/writer epoch, appends before publishing saved state, reconciles ambiguous local commits by exact replay, and exposes immutable operation status. Explicit revision submission closes capture before delivery and becomes accepted only after every operation has a receipt and the workspace is durably submitted.
- `CourtsideOperationServerAdapter` is the only network seam. It receives the immutable operation plus the preparation checksum, assignment/roster binding, and exact candidate identity. An accepted response must repeat that revision identity and package checksum around the operation receipt; a mismatched response pauses permanently rather than being stored or resent.
- Foreground recovery publishes `savedOnDevice`, `queued`, `sending`, `accepted`, and `needsAttention` separately. It recovers a stranded `sending` operation after restart, retries a lost response with the same command/request hash, accepts exact duplicate/out-of-order receipts, and preserves stale assignment or writer conflicts.
- `CourtsideCandidateBridge` compares the active workflow revision with the recovery-bound revision and durable submission evidence. Correction work must use a distinct N+1 package/snapshot/bridge; N's accepted snapshot cannot accept N+1.
- Revision submission atomically stores checksummed identity and terminal-prefix evidence in the workspace checkpoint. Final acceptance adds the exact accepted sequence/head/hash. That proof survives full acknowledged-operation pruning and sign-out, so an empty retained journal cannot be shown as ready for capture.
- Manual recovery obeys the persisted `CommandErrorCode` policy. Only `retrySameCommand` may resume directly. Authentication retry requires an injected verifier to return the exact account/operation/command; refresh-state cases require a new command and operator-resolution cases remain paused. The status card exposes different copy and actions for each posture.
- `CourtsideRecoveryNotifier` and `CourtsideRecoveryStatusCard` are dormant integration components. The card uses ordinary focusable buttons rather than a global key listener and explicitly says delivery stops when the web app closes.
- Sign-out closes storage without deleting it. Deletion reconciliation requires the exact account, device, manifest, checksum, and consent. It never grants local discard authority.

## Integration seams required

1. The assigned-game server read must return, in one authoritative boundary, the existing bootstrap plus `assignmentId`, a server-established `workspaceId`/`deviceSessionId`/writer epoch, named journal reducer and calculator, adopted rules-profile and competition-policy versions, exact roster snapshot ID/hash, accepted server sequence/head/hash, and the candidate revision ID/number/hash/scope. The client must not invent or combine these from unrelated reads.
2. A reviewed fixed-purpose operation callable and exact status lookup must implement semantic idempotency and return `OperationReceiptContract` byte-for-byte bindings. Direct client writes to journals, receipts, immutable revisions, review, certification, and releases must remain denied.
3. Only after the official-stat capability cutover is proven may the integration owner register an account-bound repository/notifier, mount the status surface on the assigned-game route, call `recoverForeground` from a foreground lifecycle signal, and call `closeForSignOut` before replacing account scope.
4. The capture reducer must create `CourtsideCaptureCommand` from the existing stat action semantics and must restore field focus/caret after rebuilds. This packet deliberately does not edit the live stat screen or its notifier.
5. Account lifecycle integration must create the journal manifest before device cleanup, collect fresh consent for that exact manifest, reconcile every opaque identity, and continue server deletion independently. No logout or deletion completion path may clear the journal implicitly.

## Activation blockers

- JBA rules-profile adoption evidence is still required. A reference profile is not an adopted production rule.
- The operation append/status callables, direct-write denials, capability document, and server receipt conformance are outside this packet.
- The authoritative writer-session allocation/transfer flow and second-device operator resolution must be integrated server-side.
- The live stat screen, app lifecycle, auth sign-out, and account deletion shared-root seams need integration review.
- Physical iOS/Android and iOS Safari/PWA interruption evidence remains a release gate. VM widget tests do not replace it.

## Candidate verification

Focused tests cover loss before and after the local commit, exact state publication, lost server response and exact retry, restart with stranded sending state, duplicate/out-of-order receipts, concurrent capture serialization, second-device writer conflict, assignment revocation without unsafe retry, verified reauthentication, stale-state/new-command refusal, mismatched revision receipts, fully pruned accepted recovery, unavailable/quota-constrained/corrupt storage, sign-out preservation, deletion manifest/consent binding, hostile N/N+1 snapshot reuse, closed-PWA copy, and keyboard focus safety. Existing journal, Flutter, analyze, dormancy, and repository-safety commands must remain green when this packet is integrated.
