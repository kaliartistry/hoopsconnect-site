# Stage 2 season lifecycle activation

Status: implemented, tested locally, and intentionally inactive by default.

The client no longer writes season documents or `currentSeasonId` directly. The
fixed-purpose `seasonPrepare`, `seasonActivate`, `seasonArchive`, and
`seasonRestore` callables are the only mutation path. Every callable enforces App
Check, current account-incarnation and lifecycle authority, exact association
binding, the authoritative `association.manage` capability, a token-bucket quota,
strict request fields, and an idempotent operation receipt.

The workflow stays closed unless all existing league readiness facts are true and
`associations/{associationId}/leagueWorkflowControl/current.seasonLifecycle` is
exactly `true`. No checked-in script or default configuration sets that flag.

## Activation evidence still required

1. Confirm production lifecycle, custody, privacy, actor-authority, and identity
   projections are complete for every season administrator.
2. Confirm the association document and league workflow control have identical
   current-season IDs, and the current season exists.
3. Decide and implement a scoped V2 `seasons.manage` capability before changing
   the workflow control from `legacyV1` to `v2`. The callable fails closed in V2
   until that capability exists.
4. Confirm App Check enforcement and callable client configuration on iOS,
   Android, and web.
5. Inventory existing season documents. Prepared targets use the versioned schema;
   existing current seasons may be migrated atomically by the first activation.
6. Re-run the full Functions, Firestore Rules, Flutter, responsive, dark-mode,
   large-text, and local QA suites against the exact release commit.
7. Obtain explicit deployment approval, deploy Functions and Rules together, read
   back the deployed revisions, then set `seasonLifecycle: true` through an
   approved server-owned configuration procedure.

Activation never deletes a season. It changes the association and workflow-control
pointers in the same transaction, marks the prior season inactive, and retains all
historical records and routes. Archive is reversible and cannot target the current
active season.
