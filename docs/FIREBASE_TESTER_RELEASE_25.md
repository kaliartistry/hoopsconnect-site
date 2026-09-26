# Firebase tester release 25, September 17, 2026

## Verified outcome

Android version **1.0.18 (25)** was uploaded to Firebase App Distribution and
distributed only to the existing `testers` group in `hoops-connect-jm`.
The group still has two members, Kali and Kurt (`khurt365`). No new testers,
roles, production records, store releases, or hosting deployments were changed.

Kurt's existing app-level Android link remains:

https://appdistribution.firebase.google.com/testerapps/1:212612973375:android:2b6139ac0f5ee182db498a

The exact new release is:

https://appdistribution.firebase.google.com/testerapps/1:212612973375:android:2b6139ac0f5ee182db498a/releases/6bq4f7j2qj22g

Firebase read-back returned `1.0.18`, build `25`, created at
`2026-09-17T20:07:07.624614Z`. CLI distribution returned success. The group
release count increased from three to four, while membership stayed at two.
Kurt must use the Google account associated with his existing invitation.
This verifies availability to that group, not a completed install on Kurt's phone.

## Included software and data boundary

The APK contains the current working-tree software, including the fixed player
spotlight layout and current sharing, sponsor, public-page, and branding assets.
It was built from `codex/qa-remediation-integration`, base commit `44eedd3`,
with the preexisting uncommitted presentation changes preserved. It is not a
clean-commit release or a merge to main.

The native build uses the existing production mobile Firebase configuration.
Neither `HOOPSCONNECT_STAGING_MODE` nor `HOOPSCONNECT_PRESENTATION_PREVIEW` was
enabled. Real sign-in and existing server data remain in place.

**The local JBL historical presentation bundle is not published into the live
mobile database or public snapshot.** Bundling its assets is not the same as
making those records appear in the normal native app. Do not describe this
release as mobile/staging dataset parity. Publishing that historical content
requires its own scoped data-release work; do not run the broad staging seed
against production or switch native authentication projects to achieve it.

## Validation

- Full Flutter tests: 998 passed, 16 skipped, zero failures.
- Player spotlight layout regression rerun: all 11 passed.
- JBL import Node tests: all three passed; source regeneration check passed.
- `flutter analyze --no-pub lib test`: no issues. Repository-wide analysis has
  35 informational lints in vendored `third_party/unorm_dart`; those were not
  changed. One new test brace lint was corrected.
- `git diff --check`: passed.
- Signed release APK: version 1.0.18, build 25, Android target SDK 36.
- Downloaded previous Firebase build 24 and verified identical signing
  certificate SHA-256:
  `9e26ef57266e5bffc4522f48f7be1e6de0b2817c44d2bd1da1c9cd523a310e19`.
- Installed build 24, then installed build 25 with `adb install -r` on the
  disposable HoopsConnect Android emulator. Both succeeded; package read-back
  changed from 1.0.17/24 to 1.0.18/25. No app-data removal was performed.
- This proves the Firebase-to-Firebase install/update path, not compatibility
  with Google Play's separately signed installed app.
- The disposable emulator used the installed Android 36 Google APIs image via
  a runtime override, with read-only/no-snapshot mode. Its configured Play image
  was missing. It was shut down afterward without saving changes.
- A fresh visual/native interaction walkthrough was blocked because the Mac
  was locked. No claim of end-to-end visual or authenticated device QA is made.

APK: `build/app/outputs/flutter-apk/app-release.apk`

SHA-256:
`84f8c295bfbe12f753c4f1b76b458d15437b502c2333cf29c4d7ecfdb75ac366`

## iPhone: built, not distributed

The current iOS source successfully archived and exported version 1.0.18,
build 25. Flutter validated bundle ID `com.hoopsconnect.hoopsConnect` and
the existing iOS 13 deployment target. The generated IPA uses App Store
distribution signing, not Firebase direct-install signing, and was NOT uploaded
to Firebase, TestFlight, or the App Store.

IPA: `build/ios/ipa/hoops_connect.ipa`

SHA-256:
`8faae52452166c9c877c1a8019f9baede39281793ffd1f3cd7faf67bc9b6bd01`

Read-only provider checks found:

- Apple bundle ID exists and the distribution identity is available locally.
- Apple lists zero registered iOS test devices and zero ad-hoc profiles.
- Firebase's project tester-UDID export returns zero registered devices.
- Firebase's existing iOS release-list endpoint returns HTTP 404.
- Apple still lists build 24 as the newest uploaded build; this turn did not
  modify TestFlight.

To finish direct iPhone distribution, obtain Kurt's device registration/UDID
with his participation, register that device in the correct Apple team, create
the HoopsConnect ad-hoc profile, export the new archive for registered devices,
and upload/distribute it to the same existing Firebase group. Verify profile
device inclusion and Firebase availability before calling it installable.
Do not upload the current App Store IPA as if it were a working Firebase build.

Official reference:
https://firebase.google.com/docs/app-distribution/register-additional-devices
