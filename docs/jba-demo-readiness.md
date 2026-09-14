# JBA presentation readiness

Snapshot date: 2026-09-14

Status: ready for a local, synthetic presentation. Production deployment,
public launch, and live JBA data remain approval-gated.

## Ready to present

- One Flutter codebase supports signed-out public league pages plus role-based
  iOS, Android, and web workflows.
- The isolated presentation environment builds the release-mode web app,
  starts Auth, Firestore, Functions, Storage, and Hosting emulators, and refuses
  production credentials.
- The deterministic fixture contains 14 role accounts, four teams, 24 players,
  six games across useful lifecycle states, standings, five leaderboard
  categories, a public announcement, and an acknowledgment-required operations
  post.
- Public visitors can inspect schedules, results, standings, leaders, game box
  scores, team details, and privacy-cleared player details without signing in.
- Super admins, admins, statisticians, representatives, media/press users, and
  fans each receive capability-driven routes and controls.
- The latest automated gate covers Flutter tests, Functions contracts and
  integration tests, Firestore and Storage rules, local delivery blocking,
  public web boot/update behavior, and repository safety.
- Native Build 13 was previously made available to private iOS and Android test
  tracks. That is tester availability, not a public store release.

The presenter instructions and recovery steps are in
[`PRESENTATION_RUNBOOK.md`](PRESENTATION_RUNBOOK.md).

## Presentation boundary

The presentation uses synthetic data on the presenter's computer. It does not
read or change production, send real notifications, expose a public URL, or
prove physical-device behavior on every supported device.

Do not describe the following as active production capabilities:

- production Hosting or a custom portal domain;
- public App Store or Google Play availability;
- the dormant official-stat v2, courtside recovery, or account-deletion
  candidates;
- final JBA competition, ranking, roster, privacy, guardian, retention, backup,
  monitoring, or incident-response policies;
- live website integration.

## Decisions still required before launch

1. JBA approves the competition/ranking rules, statistical qualification
   thresholds, roster authority, and correction/review policy.
2. JBA approves privacy, minor/guardian, account-deletion, retention, and public
   identity rules.
3. JBA names production, rollback, backup, and access-recovery owners.
4. JBA approves the Firebase staging project, region, billing, backup/PITR,
   monitoring, App Check, Secret Manager, and budget-alert configuration.
5. The team rehearses the migration and rollback against staging, then approves
   the production maintenance window.
6. Browser, tablet, and physical iOS/Android acceptance is recorded against the
   approved candidate before any public release.

Those are governance, provider, cost, or external-release gates. They are not
unfinished presentation code and must not be guessed or activated from this
runbook.
