# Official-stat domain inventory and mapping dry run

Status: **report-only Packet 03 tooling; not a migrator**

These tools inventory legacy source evidence, propose deterministic v2 domain
IDs, classify uncertainty, and reconcile a no-write plan. They cannot create,
update, delete, batch-write, or transact against Firestore. They do not certify
legacy statistics, merge identities, clean data, or authorize a migration.

The canonical implementation versions are:

- source schema `stat-migration-source-v1`;
- inventory schema `stat-migration-inventory-v1`;
- report schema `stat-migration-dry-run-report-v1`;
- mapper `stat-migration-mapper-v1` in namespace
  `hoopsconnect-stat-migration-namespace-v1`;
- classifier `stat-migration-classification-v1`;
- Packet 01 encoding `official-stat-canonical-json-v1`.

## Safe local fixture run

The default command reads the tracked, synthetic, non-sensitive fixture and
writes private local artifacts under the ignored `.local/stat-migration/`
directory:

~~~bash
npm --prefix scripts run stat-migration:fixture
~~~

For a fixed human-readable runtime timestamp:

~~~bash
node scripts/stat_migration_inventory.js \
  --mode=fixture \
  --input=scripts/fixtures/stat-migration/source-v1.json \
  --output-dir=.local/stat-migration/review-001 \
  --generated-at=2026-09-08T00:00:00.000Z
~~~

`generatedAt` is written only to `run-metadata.json`. It is explicitly absent
from the canonical inventory/report payloads and their semantic hashes.

## Export mode

Export mode accepts an explicit JSON manifest using the same source schema:

~~~bash
node scripts/stat_migration_inventory.js \
  --mode=export \
  --input=/ABSOLUTE/PRIVATE/PATH/source-manifest.json \
  --output-dir=.local/stat-migration/export-review
~~~

The source manifest must provide an exact project/export identifier,
association, export identifier, full source path and key for every record,
source collection/type/schema, scope, reference edges, provenance evidence,
classification evidence, and source data. Numbers must fit Packet 01's safe
integer domain. Legacy fractional/special Firestore values should use explicit
tagged string representations like the read-only adapter does; the tool never
rounds them.

Source paths and keys are identity evidence. Do not rewrite or normalize away
meaningful distinctions. Jersey values remain strings, so `0` and `00` are
different evidence. Names, email addresses, phone numbers, schools, jersey
numbers, and resemblance are never identity keys.

## Optional Firebase read-only mode

Firebase mode is optional and is not needed for ordinary fixture/export review.
It uses only bounded Firestore REST `GET` pages ordered by `__name__`; the
adapter has no Firestore write API. It requires all of the following:

- explicit `--input`, `--project`, and `--association` values;
- the existing target guard and exact production/non-production read opt-in;
- exact acknowledgement
  `--acknowledge-read-only=PROJECT:ASSOCIATION:NO_WRITES`;
- page size from 1 through 250;
- an input manifest whose source project and association match the flags.

The tracked
`scripts/fixtures/stat-migration/firebase-provider-v1.example.json` shows the
provider manifest shape using synthetic placeholders. Review collection scope,
reference fields, and any embedded-array stable-key policy before a live read.
Embedded roster entries must bind their exact parent team through the explicit
`parentRelation` setting; required game, team, and parent relationships fail
closed when absent.
An array index is retained as the exact source key when a trustworthy embedded
key is unavailable; it is not treated as a person match.

Example for the local emulator only:

~~~bash
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 \
node scripts/stat_migration_inventory.js \
  --mode=firebase \
  --input=scripts/fixtures/stat-migration/firebase-provider-v1.example.json \
  --project=demo-hoopsconnect \
  --association=jba \
  --acknowledge-read-only=demo-hoopsconnect:jba:NO_WRITES \
  --output-dir=.local/stat-migration/emulator-review
~~~

Do not substitute a production project into this example without a separately
justified, authorized read and the existing exact production-read guard. This
packet does not require or perform a production read.

## Artifacts and privacy boundary

Every output directory is restricted to mode `0700` and each JSON artifact to
mode `0600` where supported:

| Artifact | Contents | Semantic |
| --- | --- | --- |
| `operator-inventory.json` | Full source paths/keys, field hashes, reference edges, source schema/provenance, scope, classifications, issues, page checkpoints | Yes; private operator artifact |
| `canonical-report.json` | Stable source labels, hashes, classifications, proposed IDs/paths/field hashes, creates, conflicts, exclusions, unresolved joins, counts, dependency order, rollback mapping, reconciliation expectations | Yes; sanitized but still private operational evidence |
| `run-metadata.json` | Mode, generated time, artifact hashes, and explanatory note | No; incidental runtime metadata |

Raw source fields are never copied into either generated report. The private
operator inventory retains full paths/keys but only hashes record fields.
Console output is limited to counts, classifications, hashes, artifact paths,
and the explicit no-write state. The tracked fixture contains synthetic values
only. Never move real operator output into the repository.

## Classification review

The exact vocabulary is `evidenced`, `unverified`, `synthetic`, `orphaned`,
`contradictory`, `duplicateCandidate`, and `privacyRestricted`.

- `evidenced` requires explicit independent evidence hashes.
- `approved` in a legacy record has no certification meaning and remains
  `unverified` without independent evidence.
- `synthetic` requires generator provenance matching an explicit versioned
  rule in the input manifest. Absence of evidence is never synthetic and never
  evidenced.
- Orphans, contradictions, duplicate candidates, privacy restrictions, and
  missing scope are blocked for operator review.
- Synthetic records receive stable quarantine mappings but produce no proposed
  creates and can never be auto-certified.
- Participant-line names are evidence only. No player/person link is proposed
  from a name or other fuzzy attribute.

Missing historical `effectiveFrom` and `effectiveTo` facts remain explicit
`unknown(not_recorded)`. Missing season/division/phase/game scope never means
global scope and produces `HC_MI_MISSING_SCOPE` with no proposed target path.

## Safe reruns and reconciliation

The inventory command builds the report twice in memory and fails if the two
canonical results differ. Verify artifacts again with:

~~~bash
node scripts/verify_stat_migration_report.js \
  --report=.local/stat-migration/review-001/canonical-report.json \
  --operator-inventory=.local/stat-migration/review-001/operator-inventory.json
~~~

Add `--compare=/path/to/another/canonical-report.json` to require byte-identical
reports. On a later source snapshot, pass the earlier report to the inventory
command with `--previous-report`. The same source identity with a changed field
hash is then blocked as `HC_MI_CHANGED_SOURCE_HASH`, with expected and observed
hashes. Its deterministic proposed IDs do not silently change.

The verifier recomputes payload hashes, rebuilds the report from the operator
inventory, checks the source snapshot binding, and confirms that write and
auto-certification counts are zero. Reports are disposable and recreatable;
the source remains untouched.

## Stable failure codes

The report embeds the stable registry for malformed source, unsupported schema,
unsafe path, cross-association reference, missing scope, contradictory source,
changed source hash, nondeterminism, oversized page/report, attempted write
mode, orphaned reference, duplicate candidate, and privacy restriction.

Passing this dry run means only that a deterministic review package was
produced. A future Packet 17 executor still requires reviewed mappings,
immutable export/restore evidence, staging rehearsal, create-if-absent conflict
semantics, explicit authorization, and separate production activation.
