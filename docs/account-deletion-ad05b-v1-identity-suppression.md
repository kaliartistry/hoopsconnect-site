# Account deletion AD05-B identity suppression packet

Status: **dormant fixture-backed candidate; no policy approval, activation,
export, deployment, provider mutation, public mutation, or epoch change**

Exact implementation base:
`d133416157be5cfbf35cd2f4d00e03c2840bf2b2` (merged AD05-A).

AD05-B covers exactly three AD01 inventory rows:

1. `account_person_claims`
2. `person_identity_evidence`
3. `public_projections_exports`

It creates a server-private, subject-and-association-scoped suppression
prerequisite and a verified reference manifest. It does not complete any of
the three normative adapters. The AD01 retention registry still has
`policyVersion: null` and `activationApproved: false`, so the dormant plan
permits zero writes. The only write-capable constructors are explicitly named
test-only synthetic seams and are exercised only with fixture policy.

## Scope and identity authority

The manifest and suppression record bind the exact Firebase project, nullable
tenant, raw UID, canonical UTF-16LE UID bytes, account generation, accepted
lifecycle epoch, deleting state, internal AD04 job, and the complete AD05-A
execution binding for each of the three adapter effects. They also bind one
association, one opaque subject, one verified account-person claim, claim
provenance, identity-evidence capsule, identity-evidence provenance,
the AD01 publication decision, a separate field-level publication-policy ID,
version and provenance, and minor state. The field-level approval marker is
explicitly synthetic-test-only; it is not a production policy decision.

The scope authority is exactly `verifiedAccountAssociationOnly`.
`personErasureAuthorityV1` is false. Account deletion can detach the deleting
account generation from a verified association claim; it cannot infer that the
account owns the person or authorize erasure or publication of the represented
person. A profile, email, display name, jersey, current membership, or string
similarity is never an identity source. Unknown minor status remains
non-public.

All persisted effect bindings are full, independently parseable AD05-A
execution bindings. A stored hash without its exact project, tenant, UID,
generation, epoch, job, policy, adapter, task effect, action, and source
manifest cannot satisfy the manifest.

## Reference coverage and actual references

Coverage evidence is separate from actual reference instances. The manifest
has one exact coverage declaration for every supported class:

- account-person claim;
- identity-evidence capsule and original material;
- public profile and projection;
- leaderboard and ranking;
- press view and raw compatibility path;
- export artifact and downloadable file;
- search index, sharing asset, and cache derivative;
- restore/replay input and rebuild input.

Each coverage declaration is exact-scope and records either
`referencesEnumerated` or `verifiedAbsent` with a scanned source/version,
provenance, and evidence reference. An enumerated class must have at least one
actual reference. A verified-absent class must have none. Actual references
are bounded, ordered, uniquely identified, and may contain zero, one, or many
instances of a class. A missing, duplicate, unclassified, incomplete, or
scope-drifted coverage declaration blocks the packet.

Every actual reference binds exact project, tenant, UID bytes, generation,
epoch, association, subject, claim, source system/schema/version, path hash,
record or object version, provenance, classification, and identity-bearing
status. The account-person claim reference has a transactional record-version
guarantee. Versioned identity material and public/external references
deliberately record `versionOrProviderGuaranteeUnavailable`; AD05-B does not
mislabel them as transactionally supported.

An injected fixture verifier must attest the exact reference-set fingerprint,
coverage-set fingerprint, canonical claim-source manifest fingerprint,
claim-reference closure, raw-path coverage, restore-suppression coverage, and
verification time. These structural fixtures are not proof of a production
inventory source or verifier.

## Required ordering and create-once records

The safe ordering is:

1. AD05-A seals the canonical private source manifest for
   `account_person_claims`.
2. AD05-B builds and verifies the complete identity-reference manifest.
3. One transaction creates both the private reference manifest and the private
   suppression record, after re-reading the canonical claim-source manifest.
4. Only then may the fixture claim-detachment effect enter the frozen AD05-A
   exact-once item kernel.

The manifest and suppression records are create-once. Exact retries are
read-only replays. One missing half, changed content, changed source manifest,
or changed scope conflicts. Their paths are job-scoped and hash the private
manifest or association/subject/claim identity.

Every applicable AD05-A claim-source item maps one-to-one to an
`accountPersonClaim` reference by source-path hash, source schema and version,
record version, provenance, association hash, classification, subject, and
claim. A manifest for claim A cannot authorize mutation of claim B.

## Frozen AD05-A mutation seam

The fixture-only claim effect detaches only the account-generation binding. It
preserves the association, subject, claim kind and verification state, claim
provenance, identity-evidence references and provenance, publication-policy
reference, minor state, and unrelated records. It writes the suppression and
reference-manifest fingerprints into the claim record and advances its source
record version.

The effect does not implement a parallel receipt or mutation path. It calls
`applyCandidateAd05TransactionalDocumentItemV1`, preserving AD05-A's canonical
manifest membership, source-version check, atomic source-write plus immutable
receipt, exact replay, and conflict semantics.

The repository passed to that frozen kernel is guarded. Before the kernel reads
or writes the source and receipt, the same Firestore transaction re-reads and
validates the persisted suppression, identity manifest, canonical AD05-A claim
manifest, full binding closure, and one-to-one claim reference closure. A
pre-read suppression check cannot authorize the mutation.

## Unsupported versioned and public families

AD05-A mechanically supports only protection families T and R. AD05-B does not
change that registry or upgrade V/E rows:

- `person_identity_evidence` remains V-family and unsupported because object
  version, original-material custody, derivative, and provider guarantees are
  not approved.
- `public_projections_exports` remains E-family and unsupported for cleanup
  completion. The durable suppression is only a prerequisite and deny signal.

The public guard rejects publication, rebuild, and restore/replay while the
suppression is present. It requests no privacy-epoch or release-head mutation.
AD05-B does not erase a public artifact, inspect an external provider, advance
the privacy epoch, advance the public epoch, change a release head, or claim
raw/export cleanup complete. A later reviewed integration packet must check
the suppression before restored or legacy data is read and again before any
publication.

Missing claim provenance, identity evidence, field-level publication policy,
raw-path coverage, restore/rebuild coverage, generation/tenant/association
provenance, canonical source manifest, suppression durability, or applicable
reference closure fails closed as blocked. Missing V/E version, object, or
provider guarantees remains unsupported and nonterminal.

## Sporting integrity

Every suppression record fixes the following mutation authorities to false:

- official-stat global identity;
- snapshot epoch;
- release head;
- public epoch;
- canonical bytes;
- certified hashes;
- actor provenance; and
- correction lineage.

The claim detachment seam contains no official-stat fact, revision,
certificate, journal, correction, or projection writer. Immutable sporting
facts and their provenance remain unchanged.

## Test and release posture

Focused unit tests cover strict schema parsing, complete scope binding,
coverage-versus-instance semantics, zero/multiple references, missing
provenance and raw/restore classes, unknown-minor closure, V/E unsupported
guarantees, cross-tenant/generation/association/subject/claim drift,
create-once replay, same-transaction suppression, cross-claim closure,
exact-once claim detachment, and publication/rebuild/restore denial.

A real Firestore emulator proves all client access is denied, the two private
records seal atomically, and concurrent claim-detachment attempts produce one
commit and one exact replay. The emulator Rules fixture is not referenced by
`firebase.json`.

The dormancy suite pins production entrypoints, configuration, deployed
Firestore and Storage Rules, official-stat contracts, AD01 through AD04, and
all AD05-A code/docs/fixtures. It also proves the AD05-B graph is unreachable
from production Functions and contains no handler, Firebase SDK, provider,
network, Auth, epoch, or release-head writer.

Production activation remains blocked by authoritative AD01 decisions,
verified claim and guardian/non-account rights policy, identity-evidence
version/custody guarantees, field-level minor/publication policy, complete
raw/public/export inventory, provider/object/cache treatment, restore and
rebuild rehearsal, later reviewed privacy-epoch integration, independent verifier
registration, production private Rules, handler integration, and the remaining
G1 through G11 evidence. No production export, import, handler, deployment, or
live Firebase/provider/store operation is part of this packet.
