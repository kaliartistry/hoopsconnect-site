# HoopsConnect isolated QA environment

The Stage 0 QA environment runs the app against a synthetic Firebase project,
all four local data-bearing emulators, and both Functions codebases. It never
uses the production Flutter entrypoint or production Firebase options.

## Prerequisites

- Flutter 3.41.2 and Dart 3.11, matching CI.
- Node 22, matching both Functions packages.
- Java 21, matching CI and the Firestore emulator.
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
and closes the emulators when the check ends. Before it builds, it enforces the
versions in `scripts/qa/toolchain.json` and prints the exact executable and
version mismatch when a pin is unavailable.

The successful markers are:

```text
HOOPSCONNECT_QA_FIXTURES_OK users=14 teams=4 players=24 publicGames=6 leaderboards=5 callable=true storage=true password=LocalQa-Only-42!
HOOPSCONNECT_WEB_BOOT_OK fresh=true update=true newDocument=true staleWorkerRemoved=true
HOOPSCONNECT_QA_DELIVERY_GUARD_OK codebases=default,public
```

The fixtures provide full and empty-season identities for `fan`, `rep`,
`statistician`, `media`, historical `press`, `admin`, and `superAdmin`. Their
email is the lowercase role followed by `@hoopsconnect.test`; empty users add
`-empty` before the at sign. All use the displayed synthetic password. Guest
coverage uses the signed-out app and requires no identity.

Every fixture role and capability set, including the historical `press` alias,
is loaded directly from `functions/src/authorization_schema_v1.json`. The
fixture does not maintain a second authorization table. The full dataset has
four teams across Premier and Development, 24 rostered players (including `0`
and `00` jersey cases), regulation and overtime finals, submitted, rejected,
in-progress and scheduled games, all/division standings, five leaderboard
categories, active/draft/archived seasons, and synthetic canonical roster,
schedule-revision, assignment, stat-revision and review records. The empty
association remains genuinely empty for every role.

Notification initialization and App Check are intentionally absent from the QA
entrypoint. In addition, both actual Functions emulator worker codebases preload
`scripts/qa/functions_runtime_guard.cjs`. When QA mode is active it rejects every
non-loopback Node HTTP, HTTPS, and `fetch` request, so an accidental FCM, email,
webhook, or other delivery attempt fails closed. The runner verifies that both
the default and public codebases loaded the guard. Empty FCM tokens are defense
in depth, not the delivery boundary. Storage writes, callable loading,
Firestore/Auth access, and the public snapshot trigger are still exercised
locally.

## Keep the fixture running for interactive Stage 1 work

```text
node scripts/start_local_qa.js
```

This uses the same builds, pins, credential refusal, loopback ports, delivery
guard and deterministic seed as the ephemeral check, then keeps Auth,
Firestore, both Functions codebases, Storage and Hosting alive. Open
`http://127.0.0.1:15500/` and sign in with any fixture identity. Press Ctrl-C to
stop the suite; its synthetic state is intentionally discarded so every next
run starts from the same seed.

## What the browser smoke proves

The smoke server applies the candidate Hosting CSP to the actual release build.
Chrome must create a Flutter root on a fresh load, explicitly install and
activate a synthetic stale app-shell worker, and then create a different
document/navigation identity on a cache-bypassing reload. The candidate
bootstrap replaces an existing worker with Flutter 3.41's unregister-only
`flutter_service_worker.js`; the smoke waits until the registration is gone and
the app has rendered again. It also proves CanvasKit came from the build and
retains valid manifest metadata. A successful `flutter build web` without these
checks is not a pass.

The old generated bootstrap was separately captured during F-01 reproduction:
under the candidate-style Hosting CSP it requested remote
`https://www.gstatic.com/flutter-canvaskit/.../canvaskit.js` and never created a
Flutter root. The current smoke has no "legacy reproduction" switch; it tests
only the built candidate so its success cannot be confused with that captured
baseline.

## Tool discovery and platform boundary

Portable discovery uses `PATH` plus explicit `HOOPSCONNECT_QA_NODE`,
`HOOPSCONNECT_QA_JAVA`, `HOOPSCONNECT_QA_FLUTTER`,
`HOOPSCONNECT_QA_FIREBASE`, `HOOPSCONNECT_QA_PYTHON`, and
`HOOPSCONNECT_QA_CHROME` overrides. On macOS only, the runner also checks the
Homebrew Node 22 keg and Android Studio's Java 21 runtime. If that Node keg was
left linked to an incompatible Homebrew `simdutf`, the runner can use an
installed compatible `libsimdutf.33` only for the QA subprocess; it does not
change Homebrew links. Those fallbacks are convenience paths, not portable
assumptions. CI Linux should provide the pinned tools on `PATH` or use the
overrides. Browser discovery has the same boundary: common Chrome/Chromium
names are portable, while the final `/Applications/Google Chrome.app` candidate
is macOS-specific. The persistent runner and its Ctrl-C shutdown were rehearsed
on macOS; native Windows command-wrapper and signal behavior remains unverified.

The production app, provider configuration, physical-device behavior, and live
Hosting release remain outside this local check.
