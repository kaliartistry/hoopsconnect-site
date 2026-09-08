# JBA Demo Readiness

Date: 2026-06-30

Status: PASS for meeting/demo preparation. NEEDS-DECISION for live deployment, website integration, and public launch.

## Plain-English Positioning

HoopsConnect already has the technical foundation for a PWA because the app supports Flutter web. We do not need to build a separate admin app from scratch. The next step is to deploy, test, and polish the existing web version so admins and statisticians can reliably use it on laptops and tablets.

HoopsConnect should be the source of truth for league operations. The JBA website should display approved public information from HoopsConnect through a safe read-only data layer.

## What Is Ready

- Flutter web build exists and builds successfully.
- PWA manifest, icons, and web app metadata exist.
- Firebase Hosting is configured for `build/web`.
- SPA deep-link rewrite is configured.
- Role-based routing exists.
- Admin/statistician workflows exist in the app.
- Cloud Functions build succeeds locally.
- Public self-signup now defaults to `fan`.
- Firebase demo data is current for the meeting: 102 games, 102 approved game stats, 0 past pending games.
- Player stats, team stats, standings, and leaderboards were rebuilt from approved game stats after backfill.
- Documentation/runbooks have been created for PWA readiness, deployment, roles, usability, security, website integration, public data, and final status.

## What Is Not Ready

- No production deployment was performed.
- Live hosted state was not verified.
- DNS/custom portal domain was not configured.
- Firebase Auth authorized domains and App Check for the portal domain were not verified.
- No real browser/tablet QA was performed against seeded Firebase data.
- Public website integration is not implemented.
- Firestore/Storage rules need tightening before public launch.
- No Firebase rules emulator tests were found.
- No staging/production Firebase split is configured.

## What Can Be Shown

- The product direction and PWA/admin portal plan.
- Local build/test evidence.
- Existing PWA manifest/hosting foundation.
- Existing app screens and workflows if local Firebase/demo data/accounts are available.
- The website integration plan: portal link first, public read-only data layer next.
- Timeline and risk-based roadmap.

## What Should Not Be Promised

- Do not promise the live deployment is already verified.
- Do not promise public website integration is already complete.
- Do not promise the website can safely read private app data directly.
- Do not recommend iframe embedding of the private PWA.
- Do not promise offline stat entry is ready.
- Do not promise full production readiness.
- Do not promise public launch until security rules are tightened.
- Do not promise the current Git remote is definitely the canonical production repo.

## Demo Account Requirements

Create or verify:

- Super admin account.
- Admin account.
- Statistician account.
- Team rep account.
- Media account.
- Fan account.

Each account should be tested through a normal browser login, not only role preview.

## Demo Data Requirements

Current verified demo data state:

- Association `jba`.
- Active season `nbl-2025-26`.
- 12 teams across NBL Premier and Women's League.
- 96 player season-stat/roster docs.
- 102 games.
- 102 approved game stats.
- 0 past pending games as of June 30, 2026.
- 3 standings docs: all, NBL Premier, Women's League.
- 15 leaderboard docs.

Still create or verify before the live meeting:

- One submitted game awaiting admin approval.
- One ack-required board post with expected reps.
- One public board post.
- Role-specific demo accounts.

## PWA Explanation For JBA

The PWA is the laptop/tablet version of the same HoopsConnect app. Admins and statisticians log in through a private web portal, use the same Firebase data, and get larger-screen workflows without a separate codebase. This keeps mobile and web aligned and avoids duplicate systems.

## Website Integration Explanation For JBA

The JBA website should remain the public face. HoopsConnect should hold the official league data. The website can show approved schedules, standings, leaderboards, box scores, teams, players, and announcements by reading a safe public API or static JSON export generated from HoopsConnect.

Private admin/statistician screens should not be embedded into the public website.

## Timeline Estimates

- Demo cleanup: 0.5-1 day.
- PWA MVP deployment: 1-3 days after Firebase/DNS/App Check access is available.
- Tablet/laptop workflow polish: 1-2 weeks.
- Public website read-only integration: 3-7 dev days depending on website platform/access.
- Deeper CMS/plugin or bidirectional sync: 2-6 weeks.
- Production hardening for real season use: 3-6 weeks.

## Risks/Caveats

- Rules need tightening before public launch.
- Website platform is unknown.
- Player privacy rules need JBA input.
- Local Node version differs from Functions Node 22.
- Functions dependencies report vulnerabilities from `npm install`; review before deploy.
- Venue network reliability may decide whether offline stat entry becomes required.
