# HoopsConnect account-deletion retention policy registry (AD01)

Status: **all decisions pending; activation not approved**

The normative registry is `contracts/account_deletion/v1/retention_policy_registry.json`. It maps every v1 inventory row to one adapter and a unique policy decision ID. This document describes the required decision process; it does not choose legal bases, retention periods, or business policy.

The registry pins its 27-row matrix to *HoopsConnect account deletion: architecture and Sol implementation handoff*, prepared September 8, 2026, SHA-256 `9a9d0150244fc124bbc8ab1697fba177a3c862de8b7099c5c684d02ed8537832`. The pinned invariants cover truthful acknowledgments, invite-consumption integrity, complete-ranking truth, controlled legacy rekey/read holds/rebuild suppression, and independent reference reconciliation. That reference prevents these semantics from being lost behind shorter category labels; it does not approve a retention decision.

## Approval rule

Each row must be completed by an authorized decision maker and must include:

- purpose and approved basis;
- exact disposition action;
- retention duration and clock-start event;
- hold authority and release process;
- permitted readers;
- erasure or detachment method;
- backup, restore, and processor behavior;
- minor and publication rule;
- disclosure-text version;
- named owner and evidence references.

No null, `unknown`, `unresolved`, generic “as needed,” or indefinite default can pass. A decision is active only when its state is `approved`, `approved=true`, its owner and evidence are present, and the release gate has independently verified implementation. The registry-level `policyVersion` remains `null` and `activationApproved` remains `false` in AD01.

## Mandatory interpretation

- Pseudonymization is not anonymity.
- A plain or stable hash is not anonymous by default.
- Name or email matching is not an approved identity link.
- Unknown minor status never defaults to adult.
- Account deletion does not delete a tenant, association, team, game, or unrelated person's data.
- “Official history” does not by itself authorize indefinite identifiable retention.
- Retention and deletion decisions apply to copies, indexes, caches, derivatives, exports, object versions, backups, processors, and restoration—not only the primary Firestore record.

## Complete disposition matrix

| Policy decision | Adapter | Data class requiring an approved disposition |
| --- | --- | --- |
| `retention.firebase_auth_identity` | `firebase_auth_identity` | Firebase Auth identity and linked sign-in methods |
| `retention.user_profile` | `user_profile` | User profile, contact fields, preferences, and scope mirrors |
| `retention.memberships_capabilities` | `memberships_capabilities` | Memberships, capabilities, and authority scopes |
| `retention.device_fcm_preferences` | `device_fcm_preferences` | FCM tokens, device registrations, notification preferences, queued recipients |
| `retention.notification_inbox` | `notification_inbox` | Notification inbox and read state, including future schemas |
| `retention.team_assignments` | `team_assignments` | Team representative and operational assignments |
| `retention.pending_invites` | `pending_invites` | Pending invite credentials and issuer replay material |
| `retention.historical_invites` | `historical_invites` | Used, expired, and revoked invite actor fields and receipts |
| `retention.authorization_evidence` | `authorization_evidence` | Authorization audit and command-receipt evidence |
| `retention.personal_ugc` | `personal_ugc` | Personal posts, future comments, and personally owned derivatives |
| `retention.official_notices` | `official_notices` | Association-owned official notices and announcement provenance |
| `retention.acknowledgements` | `acknowledgements` | Acknowledgment obligations, outcomes, and legacy contact duplication |
| `retention.event_attribution` | `event_attribution` | Event creation and operational attribution |
| `retention.account_person_claims` | `account_person_claims` | Verified account-to-person, player, and guardian claims |
| `retention.person_identity_evidence` | `person_identity_evidence` | Identity, eligibility, guardian, consent, name, photo, biography, birth date, and school evidence |
| `retention.legacy_player_identity` | `legacy_player_identity` | Legacy player IDs, roster maps, player-season stats, aliases, and identity-bearing keys |
| `retention.legacy_game_evidence` | `legacy_game_evidence` | Legacy raw game lines, descriptions, jersey/quarter maps, and copied aggregates |
| `retention.v2_journal_operations` | `v2_journal_operations` | Accepted v2 journal commands and operational sporting facts |
| `retention.local_offline_journal` | `local_offline_journal` | Per-device unaccepted or receipt-unknown official-stat work |
| `retention.v2_certified_evidence` | `v2_certified_evidence` | Frozen participants, immutable revisions, reviews, certificates, corrections, and identity-evidence capsules |
| `retention.public_projections_exports` | `public_projections_exports` | Public profiles, projections, leaderboards, press views, raw app paths, exports, and sharing assets |
| `retention.personal_storage_media` | `personal_storage_media` | Personally owned Storage objects, versions, thumbnails, URLs, and derivatives |
| `retention.shared_association_media` | `shared_association_media` | Team logos, association documents, scoresheets, and multi-person evidence |
| `retention.device_local_state` | `device_local_state` | Device caches, Firestore persistence, Riverpod state, local notifications, and PWA caches |
| `retention.diagnostics_processors` | `diagnostics_processors` | Crashlytics, diagnostic logs, analytics, email, support, and future processors |
| `retention.backups_restores` | `backups_restores` | Backups, PITR, object versions, exports, migration manifests, suppression, and key copies |
| `retention.deletion_operational_residue` | `deletion_operational_residue` | Jobs, status aliases, capability hashes, suppression ledger, and minimal evidence |

There are 27 rows and 27 adapter IDs. Adding a data class requires a versioned registry and inventory update plus tests proving complete, unique coverage in both runtimes.

## Action-specific minimums

`erase` requires proof that primary data, indexes, URLs, derivatives, queued work, and service-controlled copies were erased or rendered irrecoverable according to the approved policy.

`detach` requires proof that the account/person link cannot be reconstructed through ordinary service data and that the detached shared record does not retain unapproved identifiers.

`pseudonymize` requires the replacement scheme, linkability assessment, key custody, collision behavior, publication treatment, and eventual erasure rule. It remains personal data unless an authorized assessment proves otherwise.

`restrictedRetention` requires an active approved hold, purpose limitation, named readers, auditable access, duration or trigger, release review, and public suppression. Official-stat immutability does not waive these requirements.

`accessRevokedAwaitingExpiry` requires provider-side access revocation, known expiry behavior, reconciliation, and an approved maximum duration.

`notApplicable` requires positive evidence tied to the generation and inventory version. Absence of a profile, membership, or current-schema path is not enough to conclude that legacy, copied, public, or provider data is absent.

## Holds

Only `activeApproved` can support `restrictedRetention`. `releasePending` and `unknown` prevent completion. A hold must be scoped to named records and purpose; it cannot retain unrelated personal fields or keep public presentation active. When a hold ends, the adapter re-enters disposition and verification.

## Minors and non-account persons

The registry must distinguish account deletion from a player, guardian, or non-account person's rights request. Account ownership does not prove person identity, and a player name/email match is not sufficient. Unknown minor status defaults to non-public treatment for name and photo until verified policy permits otherwise. Shared evidence must not be erased in a way that destroys unrelated persons' records without an approved, scoped method.

## Provider, backup, and processor truth

Provider inability or missing historical material must be recorded truthfully; it cannot be translated into a false `complete`. Backup and processor policies must define when service-controlled copies expire, how suppression is applied before restore or replay, what notices are sent, and what evidence closes the adapter. A deletion completion statement must match those decisions and the public disclosures exactly.
