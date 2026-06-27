# Codex Handoff

This is the working handoff for HoopsConnect so Codex, Copilot, and local VS Code
work can stay aligned around one source of truth.

## Source Of Truth

Use GitHub as the canonical source of truth. This workspace has GitHub workflow
files and Firebase project config, but it may not currently be an active Git
checkout. Before Codex starts work, initialize or reconnect this folder to the
canonical GitHub repository and push the current baseline.

Recommended workflow:

```bash
git status
git remote -v
```

If `.git/` is missing, create or connect the GitHub repository before feature
work starts. Use `main` as the protected branch. Codex should work from feature
branches or pull requests, and CI should pass before merging.

## Project Shape

- App: Flutter / Dart
- Backend: Firebase Auth, Firestore, Cloud Functions, FCM, Storage, App Check,
  and Crashlytics
- State: Riverpod
- Routing: GoRouter with role-based guards
- Platforms: iOS, Android, and web
- PWA target: existing Flutter web build, hosted by Firebase Hosting

Important files:

- [../lib/app/router/app_router.dart](../lib/app/router/app_router.dart) - route
  table and role guards
- [../lib/app/app_shell.dart](../lib/app/app_shell.dart) - responsive app shell
  with desktop rail and mobile navigation
- [../lib/models/user_model.dart](../lib/models/user_model.dart) - roles and
  permission getters
- [../lib/core/widgets/responsive_layout.dart](../lib/core/widgets/responsive_layout.dart) -
  tablet and desktop breakpoints
- [../firebase.json](../firebase.json) - Firebase Hosting, Functions predeploy,
  rules, indexes, and headers
- [../fastlane/Fastfile](../fastlane/Fastfile) - native build and beta
  distribution lanes
- [../web/manifest.json](../web/manifest.json) - PWA metadata

## Roles And Access

The app uses six roles:

- `superAdmin` - full admin access, users, divisions, schedule, invite codes
- `admin` - admin panel, stat approval, team/post moderation
- `statistician` - live stats and stat submission
- `rep` - team representative workflows and board acknowledgments
- `media` / `press` - press tools and stats access
- `fan` - read-focused access

Route access is enforced in [../lib/app/router/app_router.dart](../lib/app/router/app_router.dart).
Firestore access is enforced in [../firestore.rules](../firestore.rules). Keep
both in sync when changing permissions.

## Admin And Statistician PWA Direction

Keep one Flutter codebase. Do not split into a separate admin web app yet. The
existing Flutter web target should become the admin/statistician PWA, with native
iOS and Android still used for mobile installs.

Implementation order:

1. PWA metadata and install polish in [../web/manifest.json](../web/manifest.json).
2. Desktop/tablet stat-entry table in [../lib/features/stats/stat_entry_screen.dart](../lib/features/stats/stat_entry_screen.dart).
3. Desktop acknowledgment matrix in [../lib/features/ack/ack_tracker_screen.dart](../lib/features/ack/ack_tracker_screen.dart).
4. Desktop tables for user, team, and division management screens.
5. Offline stat-submission design only after online PWA workflows are stable.

Known risk: live stats state can be sensitive to provider lifecycle on web. Check
`liveGameProvider` behavior before relying on the PWA for court-side use.

## Distribution

Firebase project: `hoops-connect-jm`

App identifiers:

- Android package: `com.hoopsconnect.hoops_connect`
- iOS bundle: `com.hoopsconnect.hoopsConnect`
- Firebase Android app: `1:212612973375:android:2b6139ac0f5ee182db498a`
- Firebase iOS app: `1:212612973375:ios:23ec778ad8cafa58db498a`
- Firebase web app: `1:212612973375:web:48d3d72e5196b7fadb498a`

Current native tester path:

- Firebase App Distribution group: `testers`
- Android tester URL: `https://appdistribution.firebase.google.com/testerapps/1:212612973375:android:2b6139ac0f5ee182db498a`
- iOS tester URL: `https://appdistribution.firebase.google.com/testerapps/1:212612973375:ios:23ec778ad8cafa58db498a`

Public Play Store and App Store links should not be treated as live until they
are verified from the stores.

## Secrets Policy

Do not commit:

- Android signing files: `android/key.properties`, `*.jks`, `*.keystore`
- App Store Connect private keys: `*.p8`
- Certificates and provisioning profiles: `*.p12`, `*.cer`, `*.mobileprovision`
- Google Play or Firebase service account JSON keys
- `.env` files
- Generated build output

Firebase app config files contain public project identifiers and API keys. They
can be committed when protected by Firebase Security Rules and App Check, but the
team can choose CI injection later if preferred.

## Verification Commands

Run these before handing work back or opening a pull request:

```bash
flutter analyze
flutter test
flutter build web --release
npm --prefix functions run build
```

For PWA changes, also verify the web build in browser DevTools:

- Manifest loads with the correct app name, colors, icons, and orientation.
- The app installs or can be added to the home screen where supported.
- Login and role-gated routes work on desktop and tablet widths.
- `/live-stats`, `/admin/stats`, and admin screens remain protected by role.

## Deployment References

Use [../DEPLOY.md](../DEPLOY.md) for Firebase deploy order and release commands.
Deploy order remains rules, indexes, functions, then hosting.