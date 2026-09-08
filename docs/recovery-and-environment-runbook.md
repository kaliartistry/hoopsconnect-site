# Recovery and Environment Runbook

Date: 2026-09-08

Status: repository controls implemented; cloud recovery controls verified as
not enabled. No cloud setting was changed.

## Verified current cloud state

Read-only GCP/Firebase inspection on 2026-09-08 found:

- Firebase project hoops-connect-jm is active.
- Firestore (default) is Native mode in nam5.
- Point-in-time recovery is disabled.
- Version retention is one hour.
- No Firestore backup schedules exist.
- Firestore delete protection is disabled.
- Project IAM has one Owner, three Editors, and no direct
  roles/firebase.admin member.
- The authenticated Firebase project list contains no separate HoopsConnect
  staging project.
- The authorization audit found five Firebase Auth identities, three Firestore
  profiles (two with privileged legacy roles), two Auth identities without a
  profile, zero membership records, and five accounts requiring manual review.
- Thirty-one legacy privileged invite documents existed at the recorded audit
  date; their identifiers and bearer values are intentionally omitted here.
- All 11 existing posts lack an explicit visibility field; none are marked as
  public posts containing acknowledgments.
- The application Storage bucket contains no objects and the data contains no
  post image or team logo URL references.
- The live Hosting site has no releases and returns the provider's 404 Site Not
  Found response on both default domains.
- App Check is unenforced for Firestore, Storage, Identity Toolkit, and OAuth.

These are current observations, not completion claims. The single Owner,
disabled PITR/delete protection, absent scheduled backup, missing memberships,
known static invites, and legacy post visibility are production release
blockers.

## Local and CI environments

| Environment | Project | Write posture |
| --- | --- | --- |
| development | demo-hoopsconnect | emulator required |
| staging | not configured | blocked until a real project and owners are approved |
| production | hoops-connect-jm | local data scripts refuse writes |

The default Firebase alias is the emulator-only demo ID. Production commands
must name the production alias explicitly; no deploy is performed by this
runbook.

Data scripts use scripts/lib/firebase_target_guard.js:

- production writes are always refused;
- a production dry read needs an exact allow-production-read value;
- remote non-production access needs both an environment allowlist and an exact
  command-line opt-in;
- destructive reseeding needs an exact
  projectId:associations/associationId confirmation;
- emulator hosts must resolve to localhost.

## Preflight

Run:

~~~bash
npm --prefix scripts test
node scripts/check_repository_safety.js
node scripts/audit_production_foundation.js \
  --project=hoops-connect-jm \
  --allow-production-read=hoops-connect-jm
node scripts/audit_production_readiness_data.js \
  --project=hoops-connect-jm \
  --allow-production-read=hoops-connect-jm \
  --association=jba \
  --bucket=hoops-connect-jm.firebasestorage.app \
  --output-dir=.local/production-readiness
firebase emulators:exec --project demo-hoopsconnect --only firestore \
  "npm --prefix functions run test:rules"
~~~

The production audits are read-only. The foundation audit emits aggregate
counts only. The readiness planner emits aggregate counts and hashes to stdout,
and writes a pseudonymous plan plus the sensitive operator mapping under the
ignored `.local/production-readiness` directory. The directory must remain
mode `0700`; its key and JSON artifacts must remain mode `0600`. Any missing
membership, association conflict, legacy invite, or post without explicit
visibility/acknowledgment fields blocks the authorization rollout.

The safety check rejects tracked private keys, service-account JSON,
environment files, signing files, a production default alias, and unguarded
Firebase data scripts.

## Backup enablement gate (later, authorized cloud change)

An authorized project owner must:

1. Add at least one independent, named production owner using least privilege
   and verify both owners can recover access.
2. Create a separate staging Firebase/GCP project and record its approved ID in
   config/environments.json and .firebaserc.
3. Enable Firestore PITR and delete protection.
4. Create a scheduled Firestore backup with approved retention and storage
   region/cost.
5. Configure budget alerts and audit-log retention.
6. Read each setting back through GCP and attach the output to release evidence.

Billing, retention, and data-region choices require owner approval; this tranche
does not make them.

## Export and restore drill

Before a migration, record the branch, commit, project, database, export URI,
document counts, and a checksum manifest. Use a dedicated, access-controlled
Cloud Storage bucket with an approved retention policy.

Run the export only after approval:

~~~bash
gcloud firestore export gs://APPROVED_BUCKET/PREFIX \
  --project=hoops-connect-jm \
  --database='(default)'
~~~

Restore drills must target staging, never production:

~~~bash
gcloud firestore import gs://APPROVED_BUCKET/PREFIX \
  --project=APPROVED_STAGING_PROJECT \
  --database='(default)'
~~~

Verify collection/document counts, sampled field hashes, authorization
invariants, Functions behavior, and application smoke tests. A successful
export alone is not a restore proof.

## Rollback

For an authorization migration, rollback is the versioned combination of:

- the pre-migration export;
- the migration manifest and hashes;
- the previous Functions revision;
- the previous rules and indexes;
- the minimum-client-version setting.

Stop writes, capture a forensic export, restore into staging, validate, and only
then decide whether production import is necessary. Never improvise an in-place
destructive rollback.
