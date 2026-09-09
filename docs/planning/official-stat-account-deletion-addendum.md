# Official-stat identity, evidence, and privacy addendum for account deletion

Status: **AD01 review addendum; G9 remains closed**

This addendum is deliberately separate from `official-stat-contract.md`. It does not amend that contract, activate v2 official stats, change canonical encoding, or approve a retention decision. It defines the integration boundary a later account-deletion implementation must preserve.

## Non-negotiable sporting integrity

Account deletion does not rewrite sporting history. Accepted operational facts, certified sporting facts, immutable revision bytes, revision lineage, certificate bytes, and certified hashes remain byte-for-byte stable unless the existing official-stat correction protocol independently creates a new authorized revision.

Deletion must never:

- silently alter a certified payload or its canonical serialization;
- reuse the deleted account as a system actor;
- rewrite a historical command under another actor;
- remove a participant or event solely to make personal data disappear;
- mutate a global identity, snapshot epoch, release head, public epoch, or certified hash as a side effect;
- treat a display name, email, jersey number, or string similarity as identity proof.

If privacy disposition would require changing immutable bytes, the implementation must retain the bytes only under an approved restricted-retention decision and suppress/detach mutable identity presentation around them. If that cannot meet the approved policy, G9 remains closed and the conflict is escalated.

## Separate planes

The implementation must keep four planes separate:

1. sporting facts and their immutable/certified revisions;
2. account-to-actor authorization and command provenance;
3. person identity, eligibility, guardian/consent, photo, biography, birth-date, and school evidence;
4. mutable public projections, indexes, exports, press views, caches, and sharing assets.

Deleting an account removes or restricts the account binding according to policy. It does not imply that the represented player, guardian, statistician, team, or association is deleted. Conversely, preservation of a sporting fact does not authorize continued public display of a person's name, photo, biography, school, account link, or contact data.

## Identity-evidence capsule boundary

Future v2 records that need identity or eligibility evidence must bind an opaque, versioned identity-evidence capsule or commitment whose original material is stored under separate access control and retention policy. The capsule must identify its schema, policy decision, evidence class, provenance, verification time, and privacy epoch without embedding unnecessary personal values into certified fact bytes.

An account deletion may detach or suppress the mutable account/person presentation while preserving an immutable capsule commitment. That commitment remains personal data if linkable. Erasure, restricted retention, key destruction, or continued custody of the original evidence requires an explicit approved policy. Silent commitment or certified-hash rewriting is forbidden.

## Actor provenance

Historical `actorUid`, issuer UID, approver UID, reviewer UID, command receipt, and audit records are handled by the `authorization_evidence`, `historical_invites`, `v2_journal_operations`, and `v2_certified_evidence` adapters. Their action depends on approved purpose and evidentiary need.

The presentation layer must not expose the deleted account merely because immutable evidence retains an internal reference. If a retained actor reference is necessary, it must be access-restricted, purpose-limited, non-authoritative for future grants, and covered by restore suppression. Old receipts are permanently denied by the lifecycle generation/epoch/capability fence.

## Legacy identity-bearing data

Legacy player IDs, map keys, roster maps, player-season stats, aliases, raw game lines, descriptions, jersey maps, quarter maps, and copied aggregates may contain names or other identity inside keys and denormalized fields. The `legacy_player_identity` and `legacy_game_evidence` adapters must inventory actual records rather than rely on current-schema presence.

Name or email matching is prohibited as an identity-resolution method. Controlled re-keying requires verified account-person claims, collision-safe opaque replacement IDs, a migration manifest, referential-integrity checks, and rebuild suppression. A legacy key cannot be declared anonymous merely because it is hashed or truncated.

## Public, raw, press, and export paths

The `public_projections_exports` adapter covers every rendered profile, leaderboard, ranking, public projection, press view, raw-app compatibility path, export, downloadable file, search index, social/share image, and cached derivative. Public presentation must perform a current privacy-epoch check. No raw record, old endpoint, export, or press fallback may bypass the suppression decision.

When identity presentation changes, the privacy epoch advances. Derived public artifacts must bind the current privacy epoch and become stale when it changes. Rebuild workers must check the suppression ledger before reading restored or legacy data and again before publication. Silent omission from one view while another raw/export path remains visible does not satisfy public-privacy verification.

## Minors and player privacy

Unknown minor status never defaults to adult. Until verified policy permits presentation, an unknown-minor person's name and photo are non-public. Account deletion, guardian unlinking, or loss of consent must trigger a current field-level publication decision across profiles, rankings, press views, media, exports, and caches.

Account ownership alone does not prove authority to erase or publish a player's identity. Verified player/guardian/non-account rights processes are separate from self-deletion and must avoid deleting unrelated sporting facts or other persons' evidence.

## Media and multi-person evidence

Personally owned photos, clips, thumbnails, URLs, and derivatives are inventoried by `personal_storage_media`. Team logos, scoresheets, association documents, and evidence containing multiple people are inventoried by `shared_association_media`.

The adapters must address Storage object versions, metadata, transformed derivatives, public URLs, CDN/browser caches, embedded references, and future processor copies. Shared evidence cannot be erased or retained wholesale merely because one account is deleted. The approved policy must define redaction, access restriction, detachment, version conflict handling, and preservation of unrelated persons' records.

## Holds and retained certified evidence

Certified evidence may be `restrictedRetention` only under an `activeApproved` hold or policy decision with named authority, exact scope, purpose, permitted readers, duration/trigger, review, disclosure, and release disposition. It must be absent from public projection unless separately permitted.

`releasePending`, `unknown`, generic “official history,” or indefinite default retention is nonterminal. When the hold ends, evidence and all derived/linking material return to disposition and verification. The hash alone does not prove anonymity.

## Offline journals and ambiguous receipts

Accepted server journal operations, truly unaccepted device-local work, and receipt-unknown device-local work are distinct states. A missing receipt never proves non-acceptance, and accepted actor provenance is preserved under the official-stat contract. Account deletion does not upload or recover local work merely to finish server inventory, and server deletion continues independently of every device-local decision.

Before handoff or discard, each reachable device reconciles opaque command IDs against accepted receipts through a separately authorized, generation/game-scoped recovery mechanism. The deletion status capability and status aliases cannot read or recover journal content, authorize reconciliation, or mutate a journal. Each device requires its own consent bound to an exact manifest; another device's consent is never inherited. Authorized handoff must preserve original actor provenance and cannot transfer the departing user's credentials. Authorized discard applies only to the consented manifest.

If reconciliation cannot safely finish before sign-out, retain only an encrypted quarantined recovery partition with a named custodian and disposition deadline. Ordinary caches, Firestore persistence, Riverpod state, listeners, notifications, and PWA caches are cleared when fenced according to platform ordering. A second offline device cannot be remotely guaranteed purged, but it must deny normal account use and reconcile its own manifest when it next observes deletion or revocation. Policy and disclosure must state that realistic boundary.

## Restore and migration suppression

Before restored backups, PITR, exports, migration manifests, or legacy imports feed official-stat or public systems, the account-generation suppression ledger and current privacy epoch must be applied. Replayed data cannot recreate account bindings, granting receipts, public identity, photos, or stale projection assets.

Migration must preserve canonical fact bytes and certified hashes while applying controlled identity re-keying only in mutable identity/reference planes. If a proposed migration changes certified bytes or global identity semantics, it requires a new official-stat design decision outside AD01.

## Adapter ownership of this boundary

- `account_person_claims`: verified account/person/guardian links and their disposition;
- `person_identity_evidence`: original identity, eligibility, consent, minor, and publication evidence;
- `legacy_player_identity`: name-bearing keys and legacy player identity surfaces;
- `legacy_game_evidence`: raw legacy evidence and copied identity-bearing fields;
- `v2_journal_operations`: accepted actor provenance and operational facts;
- `local_offline_journal`: unaccepted or receipt-unknown device work;
- `v2_certified_evidence`: immutable revisions, certificates, corrections, and evidence capsules;
- `public_projections_exports`: all mutable/public/raw/press/export derivatives;
- `personal_storage_media` and `shared_association_media`: owned and multi-person media;
- `backups_restores`: suppression before replay;
- `deletion_operational_residue`: minimal non-granting evidence of completed disposition.

Every applicable adapter requires a versioned policy decision and terminal evidence. G9 cannot pass until reviewers prove both that certified hashes remain valid and that no public/raw/export/restore path can republish suppressed identity.
