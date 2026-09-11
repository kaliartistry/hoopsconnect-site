# HoopsConnect isolated QA environment

The Stage 0 QA environment runs the app against a synthetic Firebase project,
all four local data-bearing emulators, and both Functions codebases. It never
uses the production Flutter entrypoint or production Firebase options.

## Prerequisites

- Flutter 3.41.2 and Dart 3.11, matching CI.
- Node 22, matching both Functions packages.
- Firebase CLI 15.8.0, matching CI.
- Chrome or Chromium.
- Locked dependencies installed with `flutter pub get`,
  `npm --prefix functions ci`, and `npm --prefix public_functions ci`.

## Run the complete check

```text
node scripts/run_local_qa.js
```

The runner has no target or credential flags. It refuses ambient Firebase or
Google credentials, uses project `demo-hoopsconnect-stage0-platform`, reserves
its own loopback port set, builds `lib/main_qa.dart`, seeds deterministic data,
and closes the emulators when the check ends.

The successful markers are:

```text
HOOPSCONNECT_QA_FIXTURES_OK users=14 publicGames=2 callable=true storage=true password=LocalQa-Only-42!
HOOPSCONNECT_WEB_BOOT_OK fresh=true update=true staleWorker=false
```

The fixtures provide full and empty-season identities for `fan`, `rep`,
`statistician`, `media`, historical `press`, `admin`, and `superAdmin`. Their
email is the lowercase role followed by `@hoopsconnect.test`; empty users add
`-empty` before the at sign. All use the displayed synthetic password. Guest
coverage uses the signed-out app and requires no identity.

Notification initialization and App Check are intentionally absent from the QA
entrypoint. Fixture users have no FCM tokens, so the suite cannot dispatch a
real notification. Storage writes, callable loading, Firestore/Auth access, and
the public snapshot trigger are still exercised locally.

## What the browser smoke proves

The smoke server applies the candidate Hosting CSP to the actual release build.
Chrome must create a Flutter root on a fresh load and a cache-bypassing reload,
load CanvasKit from the build itself, retain valid manifest metadata, and avoid
a stale persistent app-shell cache. Flutter 3.41 emits an unregister-only
`flutter_service_worker.js`; the test verifies that contract and confirms both
fresh and cache-bypassing update boots. A successful `flutter build web` without
these checks is not a pass.

The production app, provider configuration, physical-device behavior, and live
Hosting release remain outside this local check.
