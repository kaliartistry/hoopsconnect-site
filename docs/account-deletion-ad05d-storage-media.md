# AD05-D storage media evidence packet

Status: candidate-only, dormant, synthetic evidence. It is not a production
account-deletion adapter and it performs no Firebase Storage operation.

## Purpose

AD05-D defines the minimum exact evidence needed before HoopsConnect can safely
reason about media during account deletion. It separates personally exclusive
objects from association-owned shared media and binds each claim to one account
generation, sealed AD05 manifest item, bucket configuration, object generation,
metadata generation, derivative graph, token state, and observation.

The verifier also requires a separately persisted registered synthetic source
authority. That authority fixes the producer, provenance, source version and
hash, high-water mark, exact object-version set, and exact reference set. A
six-record ownership, rights, graph, coverage, effect-plan, and observation
chain is read with it in one transaction. A deterministic persisted receipt
seal binds the authority and full chain, so a later observation cannot replace
an earlier accepted result under the same manifest item.

The packet deliberately does not change the frozen AD05 registry. Both
`personal_storage_media` and `shared_association_media` remain unsupported
terminal adapters. A successful candidate receipt means only that a persisted
synthetic evidence record was internally consistent. It never means that an
object was deleted, a public URL stopped working, a cache was purged, or a
restore path was closed.

## Candidate classifications

- `personalExclusive`: every inventoried version and derivative must be absent,
  every download-token set must be absent, and the synthetic observation must
  report `personalVersionEraseVerified`.
- `associationShared`: media remains live or retained for the association, the
  departing account reference is absent, and the synthetic observation must
  report `sharedAccountReferenceDetachVerified`.

Object names use one canonical test-only namespace. Generations are decimal
strings so JavaScript number coercion cannot silently change a provider version.
Derivative references must form a closed, acyclic graph. Restore-token evidence
is intentionally unsupported and must be null.

## Dormancy and security boundary

The implementation exports no Cloud Function, imports no Firebase Admin or
Storage provider SDK, makes no network call, and writes nothing. Its Firestore
and Storage Rules fixtures deny every client and are not referenced by
`firebase.json`. Production Rules, exports, deployment configuration, and the
frozen AD05-A, AD05-B, and AD05-C surfaces are pinned by tests.

## Activation blockers

Production work cannot begin until a separate approved design supplies:

1. authoritative inventory coverage for every live object version and
   derivative;
2. an explicit hierarchical-namespace, versioning, soft-delete, retention, and
   legal-hold policy for the real bucket;
3. verifiable download-token revocation plus public URL, cache, and CDN closure;
4. verifiable restore, replay, backup, and rebuild suppression;
5. an association policy for shared-media custody and rights after a person
   leaves; and
6. a provider-backed, idempotent worker with receipts, retries, monitoring, and
   an independently approved production activation gate.

Until those conditions are met, AD05-D can improve test vocabulary and evidence
discipline only. It cannot advance deletion completion or authorize account
finalization.
