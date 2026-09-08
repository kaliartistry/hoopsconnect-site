# PWA Deployment Runbook

Date: 2026-06-30

Status: PASS for local deployment readiness. BLOCKED-EXTERNAL for live deployment because Firebase Hosting, DNS, App Check, and production account access must be confirmed before deploying.

No production deploy was performed.

## Recommended Portal URL

Preferred:

1. `portal.jamaicabasketball.com`
2. `admin.jamaicabasketball.com`
3. `stats.jamaicabasketball.com`

Use `portal.jamaicabasketball.com` if the portal includes more than stats, such as users, schedules, acknowledgments, announcements, and league management.

## Required Access

- Firebase project access for `hoops-connect-jm`
- Firebase Hosting access
- Firebase Auth user management access
- Firebase App Check configuration access
- Firebase Cloud Messaging configuration access
- DNS/domain access for the selected JBA subdomain
- Ability to create/update DNS records for Firebase Hosting
- Access to configure authorized domains in Firebase Auth
- Access to configure production budget alerts and monitoring

## Local App Build Commands

Run from repo root:

```bash
flutter pub get
flutter analyze
flutter test
flutter build web --release
```

## Cloud Functions Build Commands

Run from repo root:

```bash
cd functions
npm install
npm run build
cd ..
```

Production/emulator parity note: `functions/package.json` declares Node 22. Use Node 22 locally and in CI/deployment environments.

## Deployment Command

Run only after explicit approval:

```bash
firebase deploy --only hosting
```

Do not run this command until Kali explicitly approves production deployment.

## Firebase Hosting Readiness

Verified in `firebase.json`:

- Hosting public directory is `build/web`.
- SPA rewrite sends `**` to `/index.html`.
- Security headers are present.
- Iframe embedding is blocked by:
  - `X-Frame-Options: DENY`
  - `Content-Security-Policy` with `frame-src 'none'`
- No aggressive cache headers are configured for app assets, which is conservative for early PWA updates.

## Firebase Project Aliases

Verified in `.firebaserc`:

- `default`: `hoops-connect-jm`

Missing:

- No separate `staging` alias is configured.
- No separate `production` alias is configured.

Recommendation:

Create explicit staging and production Firebase projects before real season use, or at minimum document that `hoops-connect-jm` is the production project and protect deploy access.

## Pre-Deployment Checklist

- Confirm this Git remote is the canonical app repository.
- Confirm branch to deploy from.
- Confirm Firebase project target.
- Confirm selected portal subdomain.
- Confirm Firebase Auth authorized domains include the portal domain.
- Confirm App Check web provider/site key for the portal domain.
- Confirm Firestore rules and indexes are deployed separately if needed.
- Confirm Cloud Functions are deployed and healthy if app features depend on them.
- Confirm demo/admin/statistician users exist.
- Confirm no local secrets are being committed.

## Post-Deployment Checks

- Login page loads.
- Admin login works.
- Statistician login works.
- Role-based routing works:
  - admins can reach `/admin`
  - statisticians can reach `/live-stats`
  - unauthorized users are redirected away from admin/stat routes
- Refreshing deep routes does not 404:
  - `/admin`
  - `/admin/stats`
  - `/admin/live-stats`
  - `/leaderboard`
  - `/standings`
- PWA install prompt/home-screen install works where supported.
- Web push/FCM behavior is tested.
- Tablet portrait layout is usable.
- Tablet landscape layout is usable.
- Laptop/desktop layout is usable.
- Browser back/forward behavior is acceptable.
- App Check is active and not blocking legitimate web users.
- Firebase console logs are checked after first use.

## Rollback

Use Firebase Hosting release history to roll back to the previous hosting release if the deployed PWA breaks:

Firebase Console -> Hosting -> Release History -> Rollback

Keep the previous build/release identifiable in Git.

