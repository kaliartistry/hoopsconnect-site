# AD05-E FCM registration and preference evidence packet

Status: dormant, synthetic, server-side evidence only. This packet does not
export a Function, call Firebase Messaging, change production Rules, revoke a
provider token, recall a delivery, release a deletion barrier, or clear a
device.

## Purpose

AD05-E covers only the AD01 `device_fcm_preferences` adapter. It inventories
generation-bound installation slots, notification preferences, legacy mixed
profile surfaces, queued recipient edges, delivery attempts, deletion
barriers, and retry or replay sources. Every source class must be completely
enumerated or have positive generation-scoped absence evidence.

The source authority, AD04 accepted-job binding, deleting/deleted lifecycle,
canonical AD05 manifest, evidence, suppression prerequisite, disposition plan,
observation, and immutable receipt seal are reread in one read-only
transaction. Changed source versions, omitted classes, fabricated absence,
cross-scope substitutions, or a changed observation under the same sealed item
fail closed.

Raw FCM tokens are excluded from evidence and receipts. Candidate registration
records contain only token fingerprints. The three AD02 preferences remain
separate fields, missing preference data is never treated as consent, and the
legacy `users/{uid}.fcmTokens` surface must be covered even when the V2 slot
inventory is empty.

## Dispatch boundary

`reserved`, `dispatchCommitted`, and `submitted` attempts remain unresolved.
AD05-E never retries them, rewrites their intended recipients or payload hash,
claims that a submitted notification was recalled, or releases a held barrier.
Terminal delivery history and shared notification content are preserved.
Registration-reference removal is not provider-token invalidation.

The existing AD02 notification design requires an AD04-owned provider-specific
reconciler for uncertain attempts. That integration is not implemented, so it
remains an explicit production activation blocker. Auth deletion scheduling
stays independent of this blocked cleanup row.

## Excluded work

`local_offline_journal` and `device_local_state` are D-family rows owned by the
later AD07 per-device teardown and consent packet. `notification_inbox` remains
under AD05-C. AD05-E does not delete a whole profile, mutate shared league
history, clear an offline journal, or promise global cache clearing.

## Activation blockers

The normative retention policy, live source migration and ownership, provider
semantics, AD02-to-AD04 dispatch reconciliation, production Rules, handlers,
deployment, device behavior, public disclosures, and store review all require
separate approval. Every production and terminal capability in this packet is
false.
