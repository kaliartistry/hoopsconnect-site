# JBA PWA Final Status

Date: 2026-06-30

## Overall Status

The PWA foundation exists. The existing Flutter web app can be used as the private admin/statistician portal after deployment/access confirmation, browser/device testing, security hardening for public launch, and workflow polish.

## What Passed

- Repo is a Flutter/Firebase app with expected structure.
- Flutter dependencies resolve.
- `flutter analyze` passes.
- `flutter test` passes.
- Cloud Functions TypeScript build passes.
- `flutter build web --release` passes.
- PWA manifest, icons, service workers, and web build assets exist.
- Firebase Hosting points to `build/web`.
- Firebase Hosting SPA rewrite exists.
- Public self-signup now defaults to `fan`.
- Website integration plan is documented.
- Public data layer spec is documented.
- Firebase demo data is current: 102 games, 102 approved game stats, 0 past pending games.
- 26 past pending games were backfilled with generated demo box scores.
- Player season stats, team season stats, standings, and leaderboards were rebuilt from approved game stats.

## What Failed

- Security rules are not ready for public launch:
  - direct user self-create can request elevated non-admin roles
  - all authenticated users can read all user docs
  - rep team updates are too broad
  - rep ack writes are too broad
  - storage writes are too broad
- Full usability verification failed non-blockingly because live browser/device testing with seeded data was not available.

## What Is Blocked

- Live deployment: blocked by Firebase/DNS/App Check/Auth domain access and explicit deploy approval.
- Public website integration: blocked by website platform/access decisions and public data/privacy decisions.
- Public launch: blocked by security rules hardening and emulator tests.
- Production season use: blocked by staging/prod process, seeded data validation, real-device testing, monitoring, backups, and rules hardening.

## What Needs JBA/Kurt/Kali Decision

- Confirm canonical GitHub repo/remote.
- Choose portal URL.
- Confirm Firebase project ownership and deploy access.
- Confirm website platform and admin access.
- Choose public data fields.
- Decide player photo/bio/minor privacy policy.
- Confirm whether `media` is the canonical role name with `press` as legacy alias.
- Decide pilot launch date and first public website pages.

## What Can Be Demoed Now

- PWA/admin portal architecture and build evidence.
- Existing Flutter web app locally if demo Firebase data/accounts are available.
- Current Firebase demo standings, leaderboards, teams, players, schedules, and approved box scores.
- Admin/statistician workflow screens from the app.
- Website integration plan.
- Public data layer plan.

## Must Fix Before Public Launch

- Tighten self-create Firestore rule to fan-only or trusted invite flow.
- Limit user reads.
- Field-limit rep team updates.
- Limit rep ack writes to caller's own ack entry.
- Tighten Storage role/path ownership rules.
- Add Firebase emulator security tests.
- Verify Auth/App Check/web domain setup.
- Verify public data/privacy policy.

## Must Fix Before Production Season Use

- Create staging/prod Firebase strategy.
- Run full role/account QA.
- Run tablet/laptop game-day QA.
- Seed active season, teams, rosters, schedules, and demo/production data.
- Test full stat lifecycle and ack lifecycle.
- Configure monitoring, budget alerts, backups, and rollback.
- Review Functions dependency vulnerabilities.

## Recommended Next 5 Actions

1. Confirm canonical repo and Firebase ownership/access.
2. Tighten Firestore/Storage rules and add emulator tests.
3. Seed demo data and create role-specific demo accounts.
4. Deploy the PWA to a selected portal subdomain after explicit approval.
5. Decide JBA website platform/public data fields, then build the read-only API or static JSON export.

## Final Verification

- `git status --short`: PASS, expected changed/untracked files only.
- `flutter analyze`: PASS.
- `flutter test`: PASS, 254 tests.
- `npm run build` in `functions/`: PASS.
- `flutter build web --release`: PASS.
- Firebase demo data verification: PASS, 102 approved game stats and 0 past pending games.
