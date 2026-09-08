# PWA Readiness Audit

Date: 2026-06-30

Status: PASS

## Conclusion

HoopsConnect does not need a brand-new PWA from scratch. The repo already has a Flutter web target with the core PWA foundation in place. The remaining work is deployment/access confirmation, role/auth cleanup, responsive workflow polish, live browser/device testing, and production hardening.

## Existing PWA Pieces

- `web/manifest.json` exists.
- App name and short name are both `HoopsConnect`.
- `start_url` is `.`.
- `display` is `standalone`.
- Theme color is `#2E7D32`.
- Background color is `#FFFFFF`.
- Description is present.
- Orientation is `any`, which is acceptable for laptop/tablet use.
- Icons exist:
  - `web/icons/Icon-192.png`
  - `web/icons/Icon-512.png`
  - `web/icons/Icon-maskable-192.png`
  - `web/icons/Icon-maskable-512.png`
- Icon file inspection confirms 192x192 and 512x512 PNG assets.
- `web/index.html` includes:
  - manifest link
  - favicon
  - mobile web app meta tag
  - Apple web app title
  - Apple touch icon
  - theme color
  - Flutter bootstrap script
- `web/firebase-messaging-sw.js` exists and initializes Firebase Messaging for background notifications.
- `flutter build web --release` succeeds and generates:
  - `build/web/index.html`
  - `build/web/manifest.json`
  - `build/web/flutter_service_worker.js`
  - `build/web/firebase-messaging-sw.js`
  - `build/web/icons/*`
  - `build/web/main.dart.js`
- `firebase.json` points Firebase Hosting at `build/web`.
- `firebase.json` has a SPA rewrite from `**` to `/index.html`, which supports deep-link refreshes.

## Missing Or Needs Verification

- Live deployed hosting state has not been verified.
- PWA install behavior has not been tested in a real browser after hosting.
- Firebase App Check web site key and production App Check enforcement need deployment-environment verification.
- Firebase Messaging on web needs browser permission, service-worker registration, and real notification testing after hosting.
- There is no staging/prod split documented in `.firebaserc`; only `default: hoops-connect-jm` is present.
- No Lighthouse/browser PWA audit was run in this pass.
- No tablet/laptop real-device usability test was run in this pass.

## Needs Polishing

- Confirm the portal brand name for browser install prompts. `HoopsConnect` is acceptable, but `JA HoopsConnect` or `HoopsConnect Admin` may be clearer depending on JBA preference.
- Confirm the desired portal URL. Recommended options:
  - `portal.jamaicabasketball.com`
  - `admin.jamaicabasketball.com`
  - `stats.jamaicabasketball.com`
- Add explicit cache policy for Flutter assets only if update behavior becomes a problem. Current `firebase.json` does not add custom cache headers, which is conservative for app updates.
- Run a browser install test after deployment.

## Separate Admin App Recommendation

Do not build a separate admin app right now. The existing Flutter web build is the correct foundation for the private admin/statistician portal. Splitting into another web app would duplicate routing, auth, Firestore models, and role logic before the current PWA path has been exhausted.

## Iframe Embedding Recommendation

Do not casually iframe the private PWA into the JBA website.

The current Firebase Hosting headers intentionally block embedding:

- `X-Frame-Options: DENY`
- Content Security Policy contains `frame-src 'none'`

Those headers are appropriate for a private admin/statistician portal. If JBA wants website integration, use a direct portal link for private users and a separate read-only public data layer for public stats/schedules.

## Direct Portal Link Recommendation

Recommended first step:

Add a link on the JBA website labeled one of:

- `Admin Portal`
- `Stats Portal`
- `League Operations Login`

That link should point to the hosted Flutter web/PWA portal. Public website pages should consume approved public data through a safe API/export layer, not by reading private Firestore collections directly.

## Verification

Commands verified:

- `flutter build web --release`: PASS
- Inspected `build/web/manifest.json`: PASS
- Inspected `build/web/index.html`: PASS
- Inspected `build/web/icons/*`: PASS

