# HoopsConnect account-deletion release gates (AD01)

Status: **G1–G11 closed; activation forbidden**

The normative gate record is `contracts/account_deletion/v1/release_gates.json`. AD01 supplies contract tests and review artifacts only; it does not satisfy operational, policy, provider, UI, store, or production evidence. A later packet may mark a gate passed only with a named accountable owner, immutable evidence references, independent review where required, and a versioned fixture update.

| Gate | Area | Closed because the following evidence is absent |
| --- | --- | --- |
| G1 | Controller and retention | Named controller and authorized decision maker; approved per-class registry; approved disclosure versions |
| G2 | Player and minor rights | Verified account-person claim policy; guardian/non-account process; field-level publication policy; ranking privacy treatment |
| G3 | Recoverable ownership | Named custody and recovery operators; independent infrastructure owner; transfer rehearsal; last-owner suspension rehearsal |
| G4 | Legacy migration inventory | Fresh authorized Auth/profile/membership inventory; generation metadata; approved owner bootstrap; source/media classification; suppression-before-migration proof |
| G5 | Complete fencing | Rules, command/receipt, provisioning, notification, Storage, legacy/public-read, and old-client denial evidence |
| G6 | Provider configuration | Pinned SDK compatibility; Apple native/web identifiers; revocation-material handling; provider-event validation; App Check; domains/CSP; indexes; least-privilege workers |
| G7 | Deadline and operations | Approved completion timing; staffing/alerts; backlog capacity; completion delivery; processor request process; outage/attention handling |
| G8 | Restore and retained copies | Backup/PITR/object-version/log/processor decisions; durable suppression; key custody; restore-before-traffic rehearsal |
| G9 | Official-stat integration | Approved identity/evidence/privacy addendum; legacy privacy adapter; proof of no certified-hash conflict; proof that no raw/export/public fallback bypasses privacy |
| G10 | End-to-end evidence | Applicable scenario matrix; independent disposition, custody, and public-privacy review; verified Auth absence; zero unresolved required adapters |
| G11 | Public and store consistency | Live web route and privacy-policy readback; mobile/PWA screenshots; reviewer procedure; App Store privacy and Google Data Safety/deletion URL consistency |

Every gate currently has `owner=null`, `evidenceRefs=[]`, and `passed=false`. `activationAllowed=false` is mandatory while any gate is closed.

## Gate procedure

1. Assign the accountable owner and evidence reviewer.
2. Resolve relevant retention decisions and version the policy registry.
3. Implement in a separate scoped packet with the deletion surface still disabled.
4. Exercise normal, retry, ambiguity, last-owner, Auth-only, legacy, minor/privacy, provider, backup/restore, and old-client scenarios.
5. Capture authoritative provider state and rendered UI evidence, not only local assertions.
6. Record evidence references and independent review.
7. Update the machine-readable gate only after all required evidence is present.
8. Re-run the full repository and release validation suite.

Passing one gate cannot waive another. A policy approval does not prove implementation; a test does not prove provider configuration; Auth deletion does not prove data disposition; and a store disclosure does not activate a safe backend.

## Required stop conditions

Activation stops on any unknown or incompatible policy, missing adapter, unsupported data class, unresolved custody, missing provider material without an approved truthful fallback, restore path without suppression, public/raw/export bypass, stale-generation authority, official-stat hash conflict, or inconsistent public/store wording.

If the existing official-stat contract cannot support the addendum without changing canonical bytes, certified hashes, or global identity semantics, that is an escalation—not authorization to edit the existing contract in AD01.
