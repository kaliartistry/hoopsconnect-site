# Stage 0 platform integration requests

These changes belong to the integration owner because their files are shared or
hash-pinned. They were not applied by Workstream A.

## Production Hosting CSP

`web/flutter_bootstrap.js` removes the remote CanvasKit dependency by selecting
the renderer already emitted in `build/web/canvaskit`. It also registers
Flutter 3.41's unregister-only worker only when a legacy worker already exists,
so update users escape old app-shell caches without giving fresh users a
persistent cache. FlutterFire 2.24.1 still
loads its JavaScript modules from this versioned path:

```text
https://www.gstatic.com/firebasejs/<flutterfire-pinned-version>/firebase-*.js
```

Add `https://www.gstatic.com/firebasejs/` to the production `script-src` in
`firebase.json`. Keep it path-scoped and do not add a broad `https://*` or `*`.
Also add `worker-src 'self' blob:` for the locally served Firebase Messaging
worker. Flutter 3.41's generated app-shell worker unregisters itself and must
not be treated as an offline cache. The pinned `google_sign_in_web` loader also requests the exact
`https://accounts.google.com/gsi/client` script during startup; allow that
script path, with the corresponding `/gsi/` frame/connect path for the actual
provider flow. The resulting minimum renderer/SDK portion is:

```text
script-src 'self' 'unsafe-inline' 'unsafe-eval' https://www.gstatic.com/firebasejs/ https://accounts.google.com/gsi/client ...;
worker-src 'self' blob:;
```

The current production App Check setting uses reCAPTCHA when a site key is
present. Before calling that provider configuration production-ready, validate
and narrowly add its current official `script-src`, `frame-src`, and
`connect-src` endpoints, plus the Firebase Auth iframe origin for
`hoops-connect-jm.firebaseapp.com`. The QA entrypoint intentionally skips App
Check and social-provider popups, so it does not supply that provider evidence.

After changing `firebase.json`, extend `scripts/test/hosting_csp.test.js` to
check `script-src`, `worker-src`, and `frame-src`, then run the browser boot smoke
with headers read from `firebase.json` against a production-entrypoint build in
an isolated staging project. Do not deploy as part of this patch.

## Shared CI

Install `public_functions` with `npm ci` and run `npm --prefix public_functions
test`. Add `node scripts/run_local_qa.js` as a separate browser/emulator job so
its dedicated ports and Java process are isolated from the existing security
emulator suite. Pin Node 22, Java 21, Flutter 3.41.2 and Firebase CLI 15.8.0 as
the current workflow does. `scripts/qa/toolchain.json` is the Stage 0 executable
contract; the runner fails with an exact mismatch instead of silently accepting
a different local runtime.

## Pinned production entrypoint

Do not copy QA conditionals into `lib/main.dart`. It is byte-pinned by dormant
authorization and account-lifecycle guards. `lib/main_qa.dart` is a separate
entrypoint; any future production-entrypoint change needs a deliberate guard
transition by the integration owner.
