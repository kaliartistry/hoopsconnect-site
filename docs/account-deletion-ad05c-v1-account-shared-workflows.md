# AD05-C account and shared-workflow deletion packet

## Status

AD05-C is a dormant, test-only mechanical packet. It is not imported by the
production Functions entrypoint, its Rules fixture is not configured in
`firebase.json`, and both activation and production export remain disabled.
The normative retention policy is still unapproved.

## Purpose

This packet proves the boundary between account-owned data and shared league
history for the first twelve non-media AD05 adapters. It can erase, revoke, or
detach only a strict synthetic field-owned record tied to the exact Firebase
project, tenant, UTF-16 UID bytes, account generation, lifecycle epoch,
deletion job, adapter, association scope, path hash, schema, record version,
and provenance. It never treats a display name, email, role, `authorId`, or
`createdBy` value as sufficient ownership proof.

## Adapter disposition

| Adapter | Family | Dormant mechanical behavior |
| --- | --- | --- |
| Firebase Auth identity | R | Verify exact-generation absence; never call Auth |
| User profile | T | Erase only a synthetic field-owned record; reject live mixed documents |
| Memberships/capabilities | T | Revoke only after AD03 custody proof |
| Notification inbox | R | Verified not applicable until a real schema exists |
| Team assignments | T | Detach account binding after AD03 custody proof |
| Pending invites | T | Revoke only an exact-generation pending invite |
| Historical invites | R | Preserve redeemed invite history as non-granting evidence |
| Authorization evidence | R | Preserve restricted evidence; it can never grant authority |
| Personal UGC | T | Erase only content with authoritative personal ownership provenance |
| Official notices | R | Detach attribution while preserving the shared notice |
| Acknowledgements | R | Preserve completed acknowledgement outcomes |
| Event attribution | R | Detach attribution while preserving the shared event |

T means an exact-once transactional document effect is mechanically supported.
R means evidence-only verification. Notification inbox is stricter: it can only
be represented as positively verified not applicable.

## Non-negotiable protections

- Shared league facts are never erased.
- Completed acknowledgements and redeemed invites are never erased.
- Historical or audit material never grants current authority.
- Membership and team-assignment removal fails closed without completed AD03
  owner-departure or custody-suspension proof. The proof must be a persisted,
  parseable AD03 departure receipt read in the same transaction and bound to
  the exact account, generation, epoch, association, operation, and receipt
  fingerprint; a caller-supplied status or hash alone is insufficient.
- Evidence-only verification requires the persisted canonical sealed manifest
  and binds its exact effect, item membership, source path hash, schema,
  version, and provenance before reporting success.
- Cross-generation, cross-tenant, cross-project, cross-job, cross-association,
  stale-version, and unproven-provenance records fail closed before writes.
- The live `users/{uid}` document remains outside this packet because it mixes
  account fields with later AD05-E device fields.
- Media, device/FCM state, official-stat or legacy records, processor erasure,
  restore prevention, and residue verification remain assigned to later packets.

## Activation gate

Production activation requires an approved normative retention policy, an
authoritative inventory for every live schema, a reviewed production adapter
mapping, provider-specific deletion evidence, deployment approval, and complete
security and regression gates. This packet satisfies none of those activation
conditions by itself.
