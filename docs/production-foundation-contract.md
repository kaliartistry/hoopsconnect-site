# Production Foundation Contract

Date: 2026-09-08

Status: authorization schema v1 candidate; not deployed.

## Root and scope

The association/operator is the current root. In this product instance the
public association is "jba". Tenant-owned application documents derive their
association identity from the path "associations/{associationId}/...".

Server-owned membership records explicitly carry:

- associationId
- seasonId
- competitionId (nullable until competitions become a first-class model)
- teamId and divisionId when the role requires them
- authorizationSchemaVersion

This keeps season and future competition scope explicit without prematurely
turning this application into a generic multi-league platform.

## Roles and capabilities

Roles remain presentation labels. The server-generated capabilities array in
"memberships/{uid}" is the authorization contract.

| Role | Core capabilities |
| --- | --- |
| superAdmin | all v1 capabilities for its association |
| admin | team/post management, stat entry/approval/export, internal and press reads |
| statistician | association/internal reads and stat entry |
| rep | association/internal reads, public post creation, team representation, own acknowledgment |
| media / press | association/internal reads, stat export, press tools |
| fan | association read only |

superAdmin is association-scoped. It is not a hidden platform-global identity.
No invite can grant superAdmin.

New profiles and memberships are written only by callable Functions using the
Admin SDK. Firestore clients cannot create or modify roles, capabilities,
association/team scope, invite lifecycle, or audit entries.

## Signup and invite invariants

- Public email/password, Google, and Apple signup provisions fan only.
- The server fixes public signup to association jba; it ignores client role,
  tenant, team, UID, and email claims.
- Privileged codes are random, single-purpose, single-use, expire in at most 30
  days, and are constrained to the inviter's association and grant authority.
- A raw invite is a 256-bit URL-safe bearer derived for one authenticated
  issuance operation. Firestore stores only its SHA-256 invite identifier;
  inspection never echoes it and manager listings cannot recover it.
- Creation and redemption use actor-, operation-, payload-, association-, and
  invite-bound server-private receipts. Exact retries return the original
  semantic result without creating or consuming a second invite. Receipts and
  audits contain no bearer credential.
- Redemption is one Firestore transaction covering invite validation,
  association/team validation, profile assignment, membership creation, invite
  consumption, and the audit record.
- Expired, revoked, used, malformed, cross-association, unsupported-role, and
  replayed codes fail closed.
- Legacy or statically seeded invite documents are rejected. Only random,
  single-use authorization-schema-v1 invites can be inspected or redeemed.
- `memberships/{uid}` is the single-association account invariant. A second,
  suspended, revoked, split, or mismatched record fails closed and requires an
  explicit audited recovery/transfer workflow.

## Private and public data

- users, memberships, authorizationAudit, authorizationOperationReceipts, and
  inviteCodes are private.
- Fans can read their own user record, not the user directory.
- Staff directory reads require members.read and a same-association query.
- Fans can read only posts explicitly marked public with requiresAck false;
  acknowledgment maps never cross the fan boundary.
- Staff with posts.internal.read can read same-association internal posts.
- Future certified public DTOs live under publicData/{associationId} and are
  separate from private source documents. Clients cannot publish them.

## Compatibility and migration boundary

Legacy users/{uid} roles are never trusted for authorization. Earlier clients
could self-assign those values, so every account must have a reviewed,
server-owned memberships/{uid} record before the v1 rules are activated.

Every new callable request carries authorizationSchemaVersion 1; mismatched
clients receive failed-precondition. Before activating schema v1 remotely:

1. Export and hash the relevant user/invite/post documents.
2. Audit legacy roles, tenants, teams, post visibility, and static seed codes.
3. Deterministically generate memberships and compare counts/field hashes.
4. Ship the compatible client and Functions first.
5. Backfill explicit post visibility and wait for the required index.
6. Create reviewed memberships for approved users and revoke every legacy or
   static invite found by the aggregate migration audit.
7. Tighten rules only after callable health and client adoption are verified.
8. Reject clients below the association's later
   minimumAuthorizationSchemaVersion.
9. Keep the export and migration manifest for rollback; rollback restores data,
   Functions, indexes, and rules as one versioned unit.

No broad schema migration is part of this tranche.
