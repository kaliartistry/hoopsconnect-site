# JBL live replacement, September 17, 2026

## What is live

The NBL catalog entry and its owned teams, historical fixture/stat records,
division aggregates and NBL announcements were replaced in both
`hoopsconnect-jba-staging` (review website) and `hoops-connect-jm` (native app).
The review site is https://hoopsconnect-jba-staging.web.app/public/games.

JBL contains ten teams and 188 player-team statistical records from Kurt's
`NBL total stats1ist round (1).xls`, dated April 10, 2025. All 5,555 points
reconcile, including two-point, three-point and free-throw scoring. Five public
leaderboards contain all 188 rows, with cumulative totals and per-game values.
The display period is **2025 First Round**, not the current season. No game
results, schedule, standings, registrations, minutes or shooting attempts were
invented. Thirteen supplied PNGs were copied exactly, published under
content-addressed Storage paths, and verified byte-for-byte through public URLs.
FOSKA Oats is the JBL main sponsor. No supporting-sponsor examples were added.

The women's leagues and staging school league were preserved. Existing shared
season/container IDs remain for referential integrity, even where an internal
ID contains `nbl`. Their NBL display labels were removed. The staging `qa-nbl`
competition container contains other leagues, so only NBL-owned children were
removed and the shared display name was neutralized. Auth accounts, user roles,
memberships and league actor authorities were not changed.

## Backup and exact scope

Lossless, permission-restricted JSON backups and applied plans are in the ignored
directory `.local/jbl-live-migration/backup-MuUyAe/`.

- Production backup: `hoops-connect-jm.json`, 363 documents, SHA-256
  `991f76dda034cb5869d8bb653e72aa7dab6706a3c226d80c65ffa7067cdcea96`.
- Staging backup: `hoopsconnect-jba-staging.json`, 388 documents, SHA-256
  `264f753a486d8361f7750050dd988535e2877f1420c5c2fa3a2a395ddaee1570`.
- Each corresponding `*-applied.json` records the reviewed plan, every exact
  target path and its previous value. Each project was changed in one atomic
  transaction with source read-back preconditions, including the public snapshot.
- Production plan: `924a8ffe2817e17e51d863b6698a502257eae18eb4a66b4b538284ed1c875f7d`,
  466 writes including the snapshot and publication control.
- Staging plan: `85af1aefcbfc70521dad06f74486d06964d2239447e588d5f0e116ba9c2455de`,
  312 writes including the snapshot and publication control.
- The previous deployed production publisher source was saved as
  `build/jbl-migration-audit/deployed-public-source.zip`.
- Previous bucket CORS configuration is `storage-cors-before.json` beside the
  backups. Four known HoopsConnect web origins now have GET/HEAD CORS access.
  This does not change object ACLs, authentication or database access rules.

For rollback, first reconcile any post-migration activity. In a transaction,
disable/remove `publicSnapshotControls/jba`, restore each operation's `before`
document or delete only an introduced document with `before: null`, then restore
the backed-up public snapshot. Do not overwrite subsequent user changes without
review. The new publisher stays closed without its server control; restoring
ongoing pre-migration publication also requires the saved old publisher source.
Never run the broad QA seed or recursively remove the association.

## Publisher compatibility

`public_functions/src/legacy_live.ts` is a separate, explicit deployment
entrypoint for `onPublicLeagueSourceWritten`, the old live compatibility trigger.
Only that function was deployed in each project. The official-stat v2 publisher
in `index.ts` remains dormant. No database rules, auth functions, billing settings
or app-store tracks were changed.

The compatibility trigger requires `publicSnapshotControls/jba` with an explicit
v1.1 approval, has a maintenance switch, reads a consistent source transaction,
retains league scope and fingerprints its output. It skips migration source
events already represented by the atomic snapshot. It reads at most 1,000
records per source collection and fails above an 850 KB snapshot safety bound.
It is not an official v2 result certificate or a claim of unlimited scale.

The bulk migration initially produced Cloud Run instance-capacity abort logs
with concurrency one. Its atomic snapshot remained correct. The publisher now
allows eight concurrent deliveries on the same single-instance cap. The existing
no-retry policy remains; repeated billable retries for up to seven days were not
enabled. Atomic import publication and final read-back establish this import's
completeness independently of the bulk trigger deliveries.

Reproduce the deployment package with
`node scripts/prepare_jbl_compatibility_deploy.js`, then deploy only
`functions:public:onPublicLeagueSourceWritten` using the generated config and an
explicit project. The default public-functions entrypoint remains dormant.
Do not accidentally deploy the whole default functions codebase.

The migration CLI defaults to dry-run. `--apply-plan` requires the exact reviewed
digest, a backed-up source unchanged on the server, and a matching deployed
publisher label. It refuses replay once an application evidence file exists.

## Verification

Full post-write read-back matched all planned and preserved paths: 560 in
production and 582 in staging. Production retains 22 other-league games and
staging retains five, plus three existing public media items. All new JBL
leaderboards retain 188 rows. Current snapshot versions:

- Production: `acf871f1b550fb5f0fe55821024edc4678f1303b40958b92af2c4b328c880bdd`.
- Staging: `73239dbc2d8800546b66bbc27f7b5acc58d1f875d2b8299e01fffdd68c2669e1`.

The first staging migration snapshot briefly omitted other-league timestamps
because separate Admin SDK copies have different Timestamp constructors. The
live publisher immediately rebuilt from native timestamps. The local projection
now normalizes backup timestamps to ISO strings, and regression tests preserve
other-league games/media and stable ordering. No underlying records were lost.

29 Node migration/publication tests and 24 focused Flutter public/sharing tests
passed. The normal staging web build, version 1.0.18 (25), was deployed with
noindex/nofollow/noarchive and no-store preserved. Browser checks exercised JBL
overview, team, player and a sponsor-branded player-share PNG download. CORS
failures found during the first pass were repaired; the clean rerun had zero
browser errors or warnings. The installed release Android 1.0.18 (25) was also
checked against production data, showing JBL, FOSKA, ten teams and 188 records.
Android's leaderboard share opened the native image-sharing sheet with FOSKA
and the correct historical-period statistics; nothing was sent to a recipient.
This data update does not require a new native binary. No new store upload or
iPhone-specific native test is claimed by this migration.

The two existing environments still differ in their unrelated league fixtures.
Only JBL was made consistent here. Future current-season onboarding and canonical
roster registration remain separate from this historical statistics import.
