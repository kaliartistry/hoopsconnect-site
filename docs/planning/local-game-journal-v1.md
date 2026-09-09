# HoopsConnect local game journal v1

Status: **implemented but dormant; no UI, provider, Firebase, Function, Rules, router, endpoint, or production-data integration**

Architecture source: HoopsConnect Stat Integrity Architecture Plan, SHA-256 `8399812d7ff524c3a0b9f5b2d76e7a044c8ae478db641cf21760c09cf7038205`

Base: `0567450423cd839e8524f28271bd6cddb35636f0`

The executable boundary is under `lib/services/local_game_journal/`; the compact machine-readable inventory is `contracts/local_game_journal/v1/contract.json`. Packet 01 remains the authority for canonical encoding, operation semantic/request hashes, operation kinds, delivery states, receipts, identifiers, and explicit facts.

## Storage and capture gate

- Android/iOS use `sqflite`; macOS/Windows/Linux and Dart VM tests use transactional SQLite through `sqflite_common_ffi`. SQLite opens are serialized and generation-guarded across asynchronous path resolution and capability probing. Each attempt owns a non-singleton handle until publication, so closing during initialization invalidates the attempt, rolls back an in-flight probe, and closes only that attempt's eventual handle without disturbing a later reopen.
- Web uses `idb_shim` bound directly to native IndexedDB read-write transactions. The adapter checks that the selected factory is persistent. It does not use `idb_shim`'s memory fallback. Concurrent opens share one logical attempt. Every native open attempt has an absolute two-second deadline beginning when the request is issued, including an upgrade queued behind an older connection that emits no blocked event. Any eventual late connection is closed without running the logical capability probe, and version-change events invalidate and close the current connection.
- Repository opens are serialized and generation-guarded through store initialization and logical migration. Closing invalidates an in-flight generation before releasing the store, so stale path resolution, capability probing, or migration completion cannot republish readiness or close a newer successful owner. A deliberate later open remains supported.
- Unsupported, unavailable, quota-constrained, transaction-aborted, corrupt, or unproven storage returns a typed local-journal error. SQLite and IndexedDB validate that every persisted journal key/value returned by `get` or `scan` is text before handing it to the repository; malformed raw adapter types are `mutatedRecord`, while arbitrary caller callback type errors remain ordinary transaction aborts. Observing persisted corruption through any guarded repository read or mutation invalidates cached verification and latches capture disabled while caller conflicts, transient storage failures, and a truly unprepared workspace remain non-poisoning. Calling `open` again on the same live repository cannot clear that latch. Production never silently falls back to memory.
- The deterministic memory/fault-injection adapter exists only under `test/`.
- Neither adapter claims database encryption. The OS/application sandbox may protect files, but that is not a portable encryption-at-rest guarantee. The journal therefore forbids contact/guardian fields and stores only the operational facts needed for recovery. Encrypted deletion quarantine fails closed until a reviewed cross-platform secure-storage provider exists.

`prepareGame` atomically stores the supplied versioned package envelope and workspace checkpoint only when every canonical and secondary record class for that workspace is empty. A missing package never permits rebinding an orphaned checkpoint, entry, receipt, operation/command index, recovery-export audit, or workspace index. `append` commits the operation, operation-ID index, command-ID index, and next checkpoint in one transaction before returning `savedOnDevice`. No network state, Firestore cache state, or pending-write flag is treated as a receipt.

## Identity, partitioning, and versions

Every partition is exactly:

```text
actorAccountId / associationId / competitionId / seasonId /
divisionId / phaseId / gameId / workspaceId
```

Every component uses Packet 01 opaque ID grammar: 1–128 ASCII letters, digits, `_`, or `-`, starting with a letter or digit. A repository instance is bound to one active actor account and refuses other-account partitions. Signing out closes handles but does not delete records. Reauthentication creates a new account-bound repository. No method substitutes a current season, roster, game, or workspace.

A versioned preparation package pins the device session, writer epoch, operation schema, `journalReducerVersion`, the distinct `calculatorVersion`, rules profile, competition policy, assignment ID/positive-integer version, roster snapshot reference/hash, accepted server sequence fact, accepted head/hash, preparation timestamp, and package checksum. It fetches or creates no server data. Local schema/package v2 migrates legacy schema v1 assignment strings to canonical positive integers and renames the package reducer field in one transactional `local_game_journal_v1_to_v2` step; invalid or incomplete source records fail closed.

Packet 07 owns durable local storage, not construction of the final preparation payload. The later Packet 05/08 integration must supply the complete minimized roster, rules, and accepted-checkpoint bundle; this packet neither invents nor fetches those authoritative inputs. Read/bootstrap paths do not call `prepareGame`, allocate a writer session, or advance an epoch. Server reconnect is also outside this dormant packet: its future caller must revalidate current authority, exact game, assignment version, and writer epoch before delivery. Conflict, stale-authority, or writer-transfer rejection preserves old-epoch work as a `conflictBranch` rather than rewriting or deleting it.

The local API names the pinned rules value `rulesProfileId`; its Packet 01 semantic-hash key remains exactly `rulesetVersion`. This preserves the already-merged canonical hash contract. Operation schema `2` is accepted; configured reducer, calculator, and rules-profile allowlists fail closed on unknown values.

## Immutable operation and mutable delivery

Packet 01 deliberately separates immutable operation evidence from mutable transport metadata. `LocalJournalEntry` is the persisted aggregate, but delivery fields do not participate in `payloadHash`, `semanticHash`, `requestHash`, or the previous-operation chain.

Immutable operation fields are:

```text
partition; operationId; commandId; deviceSessionId; writerEpoch;
localSequence; previousOperationHash; expectedServerHead;
operationSchemaVersion; reducerVersion; rulesProfileId;
operationType; payload; payloadHash;
gamePeriod; gameClockPosition; logicalPlayOrder; clientObservedAt;
semanticHash; requestHash
```

Sequence starts at `0` with `previousOperationHash = notApplicable(genesis)`. Each later sequence is strictly contiguous and its previous hash is the prior operation's Packet 01 `requestHash`. Exact operation/command retries compare the entire immutable canonical operation. Identical retries return the stored entry or durable pruned receipt; changed reuse fails `payloadKeyConflict`. Repository integrity, export, pruning, and deletion inventory share one verified-workspace snapshot boundary covering the package/checkpoint binding, complete hash chain, exact receipt set, and exact operation/command index sets.

Basketball order is independent: `gamePeriod`, `gameClockPosition`, and `logicalPlayOrder` may move backward for an entered correction while local acceptance sequence continues forward. Amend/undo payloads use exactly one of `amendsOperationId` or `reversesOperationId`, and the referenced operation must already exist in the same partition. Evidence is never overwritten.

Payload maps have exact per-operation required/optional keys. They contain only canonical JSON values and reject contact/guardian key names, non-finite/fractional numbers, unknown keys, unsupported enums, invalid IDs, duplicate lineups, and zero counter deltas. `attachEvidence` stores an opaque reference, not raw evidence bytes.

Facts always use the Packet 01 wire states `known`, `unknown`, or `notApplicable`; unknown/inapplicable values are explicit nulls with their prescribed reason semantics. Optional wire keys are not used for facts. Timestamps normalize to UTC milliseconds. Maps/lists are recursively copied and unmodifiable at API boundaries.

Delivery uses Packet 01 states `savedOnDevice`, `queued`, `sending`, `accepted`, and `needsAttention`. A `sending` operation has receipt state `unknown(response_pending)`. `accepted` requires an exact receipt binding account, scope, workspace, operation, command, request hash, kind, writer epoch, server sequence/head/hash, and accepted time.

Transient retry scheduling is persisted, deterministic for a command/retry count, exponentially increasing, jittered from 50–100%, and capped at 60 seconds. Delay arithmetic stops after the small fixed number of doublings needed to reach that cap even when a persisted retry count is the maximum safe integer. Packet 07 schedules no network retry. Authentication, permission, schema, conflict, stale-writer, and resource conditions pause with a typed reason.

Server conflict, stale-authority, and writer-transfer results additionally preserve the workspace as a local `conflictBranch`. Fresh appends and all queue/resume/send transitions stop on that branch; exact operation replay, late receipt recovery, and recovery/export remain available. Packet 07 does not silently rewrite the writer epoch or discard a forked tail.

Workspace submission states are `captureOpen`, `submissionQueued`, and `submitted`. A workspace cannot become submitted until all retained operations have durable receipts.

## Resource limits

The executable constants are the source of truth. Principal v1 bounds are: 16 KiB payload, 32 KiB operation, 4 KiB receipt, 32 MiB retained workspace operations, 20,000 lifetime operations per workspace/device, 128 KiB preparation package, 157,614,080-byte uncompressed canonical recovery archive, payload nesting depth 12, archive nesting depth 28, archive container width 20,000, 21,901,312 archive nodes, 64 keys per payload map, 512 elements per payload list, 4,096 payload nodes, and query pages of 25 by default/100 maximum. The archive byte and node ceilings are derived from the bounded immutable workspace, fixed per-operation evidence, prepared package, and envelope reserve. After JSON decoding, an iterative depth/node/width preflight runs before recursive canonical normalization, preventing stack exhaustion while retaining the full valid workspace contract.

Period numbers are 1–1,000 and clock positions 0–86,400,000 ms. These are storage abuse bounds, not playing-rule assumptions. Construction and persisted decoding use the same bounds and stable reason-code grammar, and append performs a canonical caller round trip before entering any storage transaction. The code does not hardcode game duration, number of overtime periods, or a universal basketball clock length. All integers stay in Packet 01's cross-runtime safe range.

Packet 08 compatibility constants reserve 25 operations/128 KiB per future server batch; Packet 07 has no ingress or endpoint.

## Recovery, pruning, deletion, and migrations

A recovery export is canonical uncompressed JSON with exact account/device/scope, version IDs, prepared package, checkpoint, retained operations/delivery state, and durable receipt tombstones for already-pruned operations. Every pruned tombstone carries its original local sequence and receipt; the archive requires exact contiguous prefix coverage and globally unique operation/command IDs across pruned and retained evidence. Retained accepted entries already contain their receipt and are not duplicated as tombstones. Explicit provenance and an archive checksum bind the whole artifact. Its versioned local export audit additionally binds exact partition, preparation-package checksum, writer epoch, lifetime covered count, terminal sequence/hash, archive ID/checksum, manifest ID, submission/recovery state, accepted-through position, and a stable ordered delivery/receipt-evidence checksum. Legitimate workspace evolution makes an older export stale and requires re-export without poisoning capture; staged pruning preserves the normalized receipt-evidence checksum. Imports reject noncanonical encoding, truncation, over-limit size/shape/count, unsupported version, wrong account/scope, malformed or incomplete pruned evidence, duplicate IDs, hash-chain/checkpoint mismatch, and checksum tampering. Imported content is stored under an isolated `untrustedImport` keyspace and never copied into an active journal.

Acknowledged operations are prunable only after the workspace is submitted, every operation through the boundary has a durable receipt tombstone, a complete recovery archive covers the boundary, and the caller separately confirms the archive was persisted. In the pruning transaction, current package/checkpoint binding, the complete already-pruned prefix, exact receipt and operation/command-index sets, and every affected retained entry are validated before the first write. Operation/command indexes and receipt tombstones remain for exact-replay conflict detection.

Account deletion uses an exact per-device manifest derived from the union of canonical active-account package, checkpoint, entry, operation-index, command-index, receipt, recovery-export, and account-wide workspace-index prefixes. Every witnessed partition must still have a valid prepared package, checkpoint, and exactly matching workspace index before device filtering; missing device provenance preserves all bytes and fails closed. Recovery-export witnesses are decoded with version-aware structural validation: current audits must bind their embedded partition and archive ID to the canonical key, while valid legacy or stale audits remain conservative witnesses without being treated as fresh prune authorization. It distinguishes accepted (including pruned receipt evidence), unsubmitted, and response-unknown work; the three counts cover the lifetime local sequence exactly. Each workspace also binds an ordered reconciliation-evidence checksum over every retained or pruned sequence, operation ID, command ID, request hash, writer epoch, and receipt-knowledge state. Creation and consented reconciliation transactionally revalidate each verified workspace snapshot and reject missing, extra, duplicated, swapped, substituted, orphaned, or stale index/package/evidence coverage. Version-1 manifests lack the identity checksum and require a fresh manifest and fresh consent without poisoning capture. Reconciliation exposes only opaque identities until future authorized server reconciliation. Consent binds one account/device/manifest/checksum and is never inherited by another device. There is no global purge or implicit logout cleanup. Server deletion proceeds independently. Because portable encrypted quarantine is not implemented, the quarantine API returns `secureQuarantineUnavailable` without mutating or destroying the journal.

Logical migrations use ordered version steps. A fresh marker is created only when the keyspace is truly empty; missing metadata on any known or unknown record fails closed without changing its bytes. The marker's outer envelope version must equal its inner schema version. Each migration's record changes, corrupt-record quarantine, and new version marker share one storage transaction. The explicit v1-to-v2 step validates original package and deletion-manifest checksums before rewriting every active record envelope and package/checkpoint/index checksum binding. It preserves legacy deletion manifests at inner version 1 so their weaker consent must be replaced, and preserves v1 export audit records with a durable `reexportRequired` marker and revoked prune confirmation because their embedded v1 package/checkpoint is not importable under v2. Failed steps retain the prior version, restart from the last committed boundary, and may rerun idempotently. SQLite schema upgrades and IndexedDB object-store upgrades are likewise transactional; unsupported future schemas disable capture rather than rewriting data.

## Verification boundary

Tests cover Packet 01 canonical hash equality on Dart VM and Chrome, input/output aliasing, exact schemas, sequence/hash/idempotency failures, caller ordering-bound rejection before writes, causal amendments, bounded maximum retry counts, receipt-before-submit/prune, exact and staged pruned-prefix receipt/index coverage, cross-workspace export-audit rejection, orphan-record preparation refusal, iterative deep/broad archive rejection, canonical active-keyspace deletion inventory including package/index double loss and copied export-audit rejection, loss before and after transaction commit, real SQLite raw BLOB/corruption/full-disk classification and reopen, SQLite close during delayed path resolution and both transactional and post-transaction capability-probe windows, repository close during logical migration, recovery tamper/identity/round-trip, deletion consent, missing-marker and checksum-safe migration rollback/rerun/quarantine, state-machine sequences, and real Chrome IndexedDB raw-object rejection, rollback/reopen/native-abort cause preservation, retained-v1 blocking across a first timeout plus a queued retry and close, bounded delayed concurrent-open serialization, late-open cleanup, deliberate reopen with byte-exact preservation, and version-change closure. CI invokes the Packet 07 Chrome matrix explicitly so these browser tests cannot be hidden behind the normal VM skips.

This packet does not promise background upload after browser/PWA closure. It exposes foreground/resume enumeration bounded to Packet 08's future batch limits.
