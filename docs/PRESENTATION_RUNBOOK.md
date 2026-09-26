# HoopsConnect presentation runbook

## Current release: September 17, Build 33

- Build 33 (`1.0.19+33`) makes both the team name and team logo actionable in
  the game score header and each box-score team header. The team profile opens
  in the same navigation stack, so Back returns to the original game and tab.
- The full Flutter suite passed 1,024 tests with 16 intentional skips. Focused
  analysis reported no issues.
- The staging website is live at `https://hoopsconnect-jba-staging.web.app`.
  The deployed JavaScript SHA-256 matches the local artifact:
  `d1a03d615dc272209f7fe4a73474fe53e68f6f25e0563a29d38f0117435de497`.
  Hosting continues to return `X-Robots-Tag: noindex, nofollow, noarchive`.
- Live browser acceptance covered the Slayers box-score header, Slayers team
  profile, browser Back to the same game, and console health. No warnings or
  errors were reported.
- Firebase App Distribution uploaded and distributed Android version
  `1.0.19 (33)` to the existing `testers` group. APK SHA-256:
  `6b4e9f8af56956aa7caab6999f16eeef8f75c35bef870d604936beb650ab0ecc`.
- Google Play accepted the same signed Build 33 bundle on the closed Alpha
  track, and the provider API read-back returned version code `33`. AAB
  SHA-256:
  `6a578453b72ecb69bb3456ce563b99a978091a2f65531a1eed5268d1bfd42372`.
- Apple pre-upload validation passed, App Store Connect processed Build 33 as
  `VALID`, and the provider read-back reports `IN_BETA_TESTING` in the existing
  `HoopsConnect Internal QA` group. IPA SHA-256:
  `24647141e0874ba7ade32844db5159185e8776caa96477c3e445cd0a48f26811`.
  Apple issued one non-blocking warning: the current iOS 13 deployment target
  must be raised to iOS 15 before spring 2027.

This section supersedes the Build 32 release-status paragraphs below. Build 32
details remain as historical presentation evidence.

## Current update: September 17, royal-blue presentation release

### Visual-system update

- Build 32 makes royal blue the permanent product chrome across public and
  signed-in surfaces. Green is reserved for real JBA/JBL artwork and genuine
  success states, so the association and league marks remain distinctive.
- Light pages use a neutral gray canvas, white layered cards, royal tint for
  selected states, restrained gold accents, and the same royal gradient across
  game, team, player, league, and sign-in presentation surfaces.
- Logos remain large enough to read. Transparent marks render directly on light
  surfaces, dark panels provide a soft-white contrast well, and failed or
  unavailable artwork now shows a branded initials fallback instead of an empty
  plate.
- Recorded results use two separate team rows with marks, aligned scores, and a
  clear winner treatment instead of a run-on text line.
- Claude Design's final phone and desktop review judged the royal system
  coherent across the landing page, games, game details, standings, and leaders.
  Its three last polish findings were the logo fallback, landing scoreboard
  palette, and recorded-result structure; all three were corrected before this
  release.
- Post-deploy phone-size QA on the live staging site confirmed the real JBL and
  FOSKA marks, readable result-row team logos, the royal hierarchy, and zero
  browser warnings or errors.

### Stats and rivalry comparison update

- Stats exposes Players, Teams and Compare for guests and signed-in users.
  The existing public player leaderboard URL remains stable.
- `/public/team-stats` ranks all published teams in the selected league by
  PPG, RPG, APG, SPG, BPG, wins or losses. Historical JBL averages use the
  supplied nine-game reporting period. Unknown W/L remain unavailable.
- `/public/compare` supports teams and players, scoped by league/season.
  Player selection is searchable by player or team name. Team and player
  detail pages include a Compare shortcut with the first selection prefilled.
- Both comparison modes offer sponsor-branded PNG cards. Player cards contain
  GP, PPG, RPG, APG, SPG and BPG. Team cards contain W, L, PPG, RPG, APG and SPG.
  Current-publication validation runs before opening and before export actions.
- Last five meetings means up to five available reported matchups, most recent
  first, with box-score links. Player points use published player lines or an
  exact normalized name match within the player's team in an imported recap.
  Missing performances are not silently replaced with zero or a prediction.
- No win-probability engine, fan voting, automatic rivalry alerts or public
  social posting was added. Sharing opens the normal user-controlled flow.

Build 32 (`1.0.19+32`) is published to the staging website and Firebase App
Distribution's existing `testers` group. Web `main.dart.js` SHA-256 is
`75b0832988eba0a93bfc07a0cd1a3b6ef2d1a64036ca0678c4df77aa207921eb`.
APK SHA-256 is
`b172c0cab116a1ea6f0760695b18a7d69708d5de140ae67f7b5d7f0d6ae5b9d7`.
Firebase confirmed upload and distribution of version `1.0.19 (32)`.

The full Flutter suite passed 1,023 tests with 16 intentional skips; focused
analysis reported no issues. Live desktop and 390 by 844 phone-size browser QA
confirmed the redesigned game details: royal-blue score treatment, materially
larger team marks, soft-white contrast wells only on dark panels, readable
period-score headers, separate team box-score tables, totals, pinned player
names and direct player-profile links. Build 32 also makes every published
box-score statistic header sortable, descending on first tap and ascending on
the second, while keeping unavailable values at the bottom. Game, team and
player detail pages now use the same royal-blue, gold and neutral-light visual
system, including readable royal app bars and higher-contrast player statistics.
The live JavaScript hash matches the built artifact and Hosting still returns
`X-Robots-Tag: noindex, nofollow, noarchive`.

This section supersedes older dated presentation/import notes below. The web
review site remains `https://hoopsconnect-jba-staging.web.app`; the native app
uses `hoops-connect-jm`. They are separate Firebase projects receiving the same
scoped JBL presentation source imports, not a claim of one database.

- Imported 46 distinct complete game results from Kurt's 24 newly supplied
  Results 2025 workbooks into both projects. Original files and pre-import
  backups are retained locally. Existing season totals and standings were not
  recalculated from this incomplete game ledger.
- Completed game-detail presentation statistics are deterministic client-side
  examples using known performers and familiar roster names. Final scores stay
  unchanged, player points reconcile, and two inconsistent quarter tables are
  adjusted only in the presentation layer. Nothing writes these completions
  back into source game stats, player season totals or standings.
- Team pages default to Games, with upcoming fixtures, five recent results and
  an expandable list of the remaining results. Tapping a result opens its box
  score. Players & stats is one tap away and defaults to Per game, with Totals
  and pinned Points, Rebounds, Assists, Steals and Blocks selectors. Player names
  open their profiles and preserve Back navigation. No future JBL fixtures were
  invented; the upcoming section explicitly says when none are published.
  JBL team averages use nine games for the
  supplied 2025 statistical period; player averages use each player's recorded
  appearances. These are not averages over the later 46-game partial ledger.
- Follow opens `/settings?follow=jbl` (or the selected league ID) directly at
  expanded team selection, with notification preferences and a top Save action.
  Signed-out visitors land at member access before returning to that selection.
  Selecting a league follows its current teams; future teams are not silently
  promised. Push delivery still requires device permission and server eligibility.
- Shareable standings include all ten teams with W, L and league-points columns.
  Unknown wins/losses remain dashes rather than being derived from a partial ledger.
- CSV enhancements were withdrawn when Kali clarified that request was for
  someone else. Existing export behavior remains unchanged.
- The eventual clean start is statistics-only, preserving teams, logos and
  leagues. No reset or deletion has been performed or scheduled.

Validation: focused Flutter tests cover stat switching, Follow selection,
sign-in anchoring, source-preserving completion of all 46 games, shared
standings, publication checks and share sheets. The hosted mobile Slayers page
was checked for real Rebounds/Totals interaction, readable layout and no console
errors. The hosted asset hash matched the built artifact. Signed-in saving and
real device push delivery are not claimed from widget checks alone.

The Build 32 Android distribution note below is historical. Build 33 now
supersedes it on Firebase App Distribution and Google Play closed Alpha, and
the matching iOS build is in TestFlight internal testing.

Claude's independent fan-UX review is complete. Build 32 retains its highest
priority box-score findings: familiar Summary, Box score and Team stats views;
separate team tables; pinned player names; totals; stronger score hierarchy;
and constrained shadows and borders. Player and team profiles now show a
visible `Compare` label, and box-score player names open the public player
profile when one is published. User management has composable search and role
filters for Super Admins, Admins, Statisticians, Team Reps, Media and Fans;
Press accounts are grouped under Media.

Kurt was sent the current `/public/leaders` website link through his existing
WhatsApp conversation, with the explanation that the same stats are available
in the app for convenient regular phone use. WhatsApp showed Sent.
The requested second message asking Kurt to check both logged-in and logged-out
views also showed Sent.

UX references checked: ESPN's Boston team-page Schedule/Stats/Roster navigation,
NBA team upcoming-games placement and statistical modes, and FIBA EuroBasket
team Games/Roster/Statistics sections. This is a pattern comparison, not a claim
of full feature parity or an independent usability study.

## Earlier rehearsal notes (historical context)

Last rehearsed: 2026-09-15

This runbook covers the single hosted interactive acceptance site and the local
release-mode operations environment. Both use synthetic data and remain
separate from the production Firebase project.

## Hosted interactive acceptance site

Open this stable URL:

```text
https://hoopsconnect-jba-staging.web.app
```

This is the primary environment for the JBA evaluation. It uses the dedicated
Firebase project `hoopsconnect-jba-staging`, not `hoops-connect-jm`. Email,
Google, and Apple sign-in providers are enabled. The Google and Apple buttons
were checked from this hosted URL: both opened their respective account pages
with the registered Firebase callback in the request. Google's completed
account-holder return still needs verification. On September 15 at 08:58 UTC,
staging Auth created an Apple-only identity for `ilak_1@hotmail.com`; its
server-owned profile is an active Fan. That is evidence of a completed Apple
provider authentication in staging, but not of administrator access or the
exact client used. The address owner has not yet been confirmed by Kali.

Kali's existing staging Super Administrator
account currently uses email/password. To make Google or Apple return to that
same administrator UID, he should sign in with his existing staging email
method once, open Profile, and choose Connect Google and/or Connect Apple. The
provider popup asks him to authenticate and consent; successful linking keeps
his role and data on the same UID. The Apple credential is currently held by
the separate Fan UID, so Connect Apple on the Super Administrator account will
not safely link it until that account conflict is resolved with the verified
owner. Do not merge UIDs or grant privileges to the new Fan account as a
shortcut. Until then, use email sign-in for administrator demonstrations. The
hosted Profile screen
was verified with a synthetic Super Admin account and displayed both Connect
buttons; no personal provider account was linked during automated QA. Use the
Full control account in the Synthetic accounts table below so the
representatives can review the board, administration, leagues, child divisions,
teams, statistics, and public views.

The hosted sign-in page now includes a short staff-account note beneath the
Google and Apple buttons. Its desktop and 390-pixel phone layouts were checked
after deployment; the note remains readable without covering the provider
buttons or the password-recovery link. This is a web-only workflow cue and is
not present in the already-uploaded native build 14.

The site and its Firestore writes were rehearsed from the deployed URL. The
browser test signed in, created and removed an empty fourth league, created a
child division beneath the Women’s League, archived it, restored it, and then
reset the staging dataset. All observed Auth and Firestore traffic named the
staging project, and the browser console reported no warnings or errors.

The acceptance site is deliberately non-indexable through the Hosting
`X-Robots-Tag: noindex, nofollow, noarchive` header. It is a persistent staging
site rather than an expiring preview, so do not share the login credentials
outside the evaluation group.

The hosted staging build uses Firestore's online memory cache, not IndexedDB
offline persistence. This avoids the single-tab cache lock when evaluators
open several browser tabs; the final second-tab public-page check rendered
with no new browser warnings or errors. Native builds and production web keep
their existing persistence configuration. Do not present staging-web offline
editing as a tested feature.

The earlier expiring, public-only Hosting preview was retired after the
interactive staging site passed QA. Share only the stable staging URL above.

On September 15, the staging web build was rebuilt with
`HOOPSCONNECT_STAGING_MODE=true` and deployed with `firebase.staging.json`
using Hosting only. The deployed `/public/games` route returned HTTP 200 and
`X-Robots-Tag: noindex, nofollow, noarchive`; accessible browser QA showed
the NBL score, next game, Media tab, and score share sheet with ShipSafe and
both team marks. The staged public snapshot was republished after a narrow
display-name/brand-label correction so page headings say `2026 Season`,
`Title sponsor`, and `Association partner`. This did not seed/reset Firestore
or modify accounts, leagues, games, scores, or production data.

Kali McCarthy has a separate active Super Administrator identity in staging so
his production password and production data are never reused by the demo. The
production Kali McCarthy identity remains active and unchanged.

Staging billing is linked only to `hoopsconnect-jba-staging`. A USD 5 monthly
project budget alert and a separate USD 5 monthly Cloud Run Functions spend cap
are configured. Cloud cost reporting is delayed, so a small overage remains
possible before a service is paused. Production billing was not changed.

Twenty-two Cloud Functions are deployed in staging. Permanent division
deletion, membership and invitation changes, season lifecycle commands,
server-authoritative schedule commits, and the other callable administration
workflows can therefore be demonstrated from the stable hosted site. The
staging-only acceptance build does not require App Check for these callable
operations; authentication, role, capability, and association checks remain in
force. Production continues to require its normal App Check posture. Old
Functions container images are removed after one day.

Current hosted limitation: the public snapshot publisher remains deliberately
dormant. The hosted fan pages use the safe, synthetic public snapshot seeded for
this evaluation. A score changed in the private operations collections will not
automatically republish that public snapshot until the separate public-release
publisher gate is approved and deployed.

### Public sharing update, September 15

The hosted site now supports score and box-score cards, upcoming-game cards,
published media-story cards, and direct public media links without requiring
sign-in. The score and box-score cards retain the navy arena, gold accents,
single-line league lockup, prominent team scores, readable JBA/NBL marks, and
ShipSafe sponsor treatment accepted for the presentation. A 390-pixel phone
preview and desktop browser review found no card overflow or browser errors.
The share action rechecks the server-owned publication before creating an
artifact; withdrawn or changed results are not silently distributed.

The production app is a different data case: its older public snapshot is
published but lacks exact result and snapshot version fields. Build 16 can
offer an explicitly labeled current-public-feed score or team-standings preview
after an exact server comparison, but it must not present a box score or player
stat card from that old feed as a verified publication. The production feed
currently has no published media stories. Staging's synthetic stories remain
shareable and are not production news.

### Android gray Share follow-up, September 15

Google Play Alpha build 16 (1.0.9) still serves closed testers. The production
public feed uses an older snapshot contract: 102 final scores and 12 standings
rows are public, but result-version fields and public player box lines are not.
This is why signed-in Box Score, Player Stats, and Leaders Share controls could
be gray in build 16. Login status itself is not the gate.

Build 24 (1.0.17) offers a final-score share from the current public feed after
an exact server recheck. The score button on an approved private Box Score
screen shares that same game's already-public final score when the older feed
has no published box lines. It must not offer an unrelated fixed box-score
sample. The signed-in Player Stats and Leaders screens now show share actions
only for their own versioned, public records. The older production feed lacks
those records, so those specific controls are absent there until actual public
stats are published; staging's published player and leader records remain
shareable. No unpublished private statistics are read into share cards.
Locally generated sample numbers remain in isolated test helpers for visual QA,
not as context-free share options on live stat screens.

Share cards now use the configured league title sponsor, falling back to the
configured association partner only when the league has no active sponsor.
Mixed-league standings use association branding and its partner. Published
player and leaders cards resolve their actual league instead of losing sponsor
data. The Schoolboy score and box cards were initially missing the association
partner because game detail had a second, league-only branding getter; it now
uses the common fallback path. Public card faces and copied captions no longer
show internal publication/result hashes; hashes remain in artifact filenames
and validation state. A 360-pixel widget test caught a sponsor-rail overflow; the footer now
reserves space for both the HoopsConnect wordmark and the sponsor plate.
Build 24 uses the real association display name `JBA` and team matchup/date
for game PNG filenames, so the local fixture's internal `qa-` IDs do not
appear as user-facing labels or saved filenames. Sponsor banners never append
`DEMO`. The public league selector has a wider iPhone menu and tighter tab
spacing.

The member Board has a direct `Public scores and share cards` entry; the public
fan view offers `Back to app` from a signed-in session. Mobile PNG `Save image`
now writes to Android Gallery or iOS Photos rather than app-private Documents.
The close control has stronger contrast. A transient publication-check
connection failure permits a cautious retry; a confirmed withdrawal still
blocks export. Mixed-division standings preview one team per division and copy
all rows beneath their parent division; unverified rank fields say `Rank
pending`. The initial Android and iPhone scratch simulator QA exercised Share,
Copy, Save, and Photos visibility; Claude is retesting the final unmarked visual
pass separately. Claude's Build 24 scratch retest passed on both Android and
iPhone with offline local data and production Firebase config removed: the
legacy-public-final Box Score share opened the current game's score (not an
unrelated sample), Copy text matched its names/score, Save wrote to Android
Gallery/iOS Photos, and both native share sheets opened. With no posted stats,
no share icon appeared. Its iPhone tabs and league/division dropdown labels
displayed fully. The scratch builds were debug builds, not the Play-installed
or Apple-distributed binaries. Claude identified two non-blocking follow-ups:
evening-game PNG filenames use the UTC date rather than the Jamaica display
date, and an older Box Score player table clips its STL/BLK columns by 52px
on a narrow iPhone. Both remain in Build 24 and should be addressed in the next
update. Real share targets, Android 10 and older, and the production signed-in
stats path were not verified by that scratch pass.

Build 20's review was withdrawn before testers received it when Kali found
missing sponsors. Build 21's draft was discarded after the Schoolboy Score/Box
gap was found. Build 23's unsent Alpha change was discarded after Claude found
identity/matchup mismatches; the uploaded artifacts remain in Play's library.
Build 24 is the corrected release candidate. Its Android bundle is accepted
by Google Play and its Alpha change was sent for review on September 15. Play's
automated quick checks subsequently completed with the provider statement
`Your changes are now in review. We may find additional issues when reviewing
your app.` **Build 16 still serves
Play testers until Google approves Build 24.** Do not tell Kali his phone can update until Alpha
explicitly says Build 24 is `Available to selected testers`.

## Private mobile test builds

Provider state was read back on September 15, 2026:

- Android 1.0.9, build 16: a signed AAB was uploaded to the existing Closed
  testing Alpha track. Google Play's Test and release page now lists closed
  testing `alpha` release `16 (1.0.9)` serving to testers, and Publishing
  overview says the update was published September 15 with no unpublished
  changes. It is the current tester build, but it does not contain the Build 24
  share fix above. Build 24 (1.0.17) is the candidate for the same closed
  Alpha track, with no change to the tester audience. The
  intermediate build 15 draft was withdrawn from review
  and discarded after the visual QA correction. Play confirmed its bundle
  remains in the artifact library; no active build or tester account was
  removed.
- Android 1.0.17, build 24: the signed AAB and matching release APK built
  locally. The AAB SHA-256 is
  `ad1b9fe6d75f0971111f934a4a723f80a0eaccc545cdf34922d6e1b6e98f68b5`;
  the APK SHA-256 is
  `f4cd032ccc410f23bc9e5312808f3a1e3a76a57758a44c30ea0cf68b4327dd52`.
  Play accepted the AAB as `24 (1.0.17)` with target SDK 36 and no loss of
  supported devices. The 100% Alpha release `24 (1.0.17) Share reliability`
  was saved and sent as the sole change for review. Publishing overview read
  back `Changes in review`, `1 change sent for review`, and then confirmed the
  automated checks finished and the change entered review. This is not yet an
  installable Play update.
- Android 1.0.16, build 23: signed AAB was accepted by Play, but its saved
  unsent Alpha release was discarded before review. Its bundle remains in the
  artifact library. Matching APK was distributed through the existing Firebase
  `testers` group, but build 24 now supersedes it.
- iOS 1.0.17, build 24: Xcode archive and 59.3 MB App Store IPA built locally
  and passed Flutter's App Settings Validation: iOS 13.0 minimum, version
  1.0.17/build 24, bundle identifier `com.hoopsconnect.hoopsConnect`.
  IPA SHA-256 is
  `cc199b5f8a93b56c1b0fa6c7682ee8129c2d5f2c70957124b34cd55ac3d6774d`.
  The App Store Connect browser account became available after a direct
  session retry. An existing active team App Manager API key validated this
  IPA with no errors and one iOS-minimum-version warning for spring 2027.
  Apple's upload then succeeded with no errors, delivery UUID
  `2d4417c1-4620-4506-85ab-3f976ee776de`. TestFlight's HoopsConnect Build
  Uploads table first read back version 1.0.17/build 24 as `Processing` at
  2:22 PM New York time, then `Complete`. The Build 24 Test Information page
  showed its automatic assignment to the preexisting `HoopsConnect Internal
  QA` group (one tester). A short `What to Test` note covering public games,
  media, score sharing, image saving, and league/division administration was
  saved. The group Builds tab finally read back `Build 1.0.17 (24)` as
  `Testing`, with one tester and six group builds. No external tester group was
  assigned and this is not an App Store public release.
- iOS 1.0.9, build 16: the signed Xcode archive and 59.2 MB App Store IPA were
  built locally and passed Flutter's App Settings Validation (iOS 13.0 minimum;
  `com.hoopsconnect.hoopsConnect`). Build 15 was exported locally but not
  uploaded. App Store Connect returned to its login page, and Xcode Apple
  Accounts is signed out; build 16 has **not** reached TestFlight. Apple
  authentication and verification, IPA upload, processing, and internal-group
  assignment must be read back before tester availability is claimed. Kali was
  asked to complete Apple sign-in when available; the requested upload is now
  build 24. Builds 20, 21, and 23 were exported locally but superseded before
  Apple upload. Build 24 has now processed and is Testing in the existing
  internal group; build 16 remains a historical local-only export.

- Apple TestFlight: version 1.0.8, build 14, uploaded successfully with
  delivery UUID `b9b5c0b5-0c6f-40c4-aa36-38391602969e`. App Store Connect
  shows the upload Complete and the build Testing in the HoopsConnect Internal
  QA group. That group has one invited internal tester, Kali's Apple account;
  there are no recorded installs yet. The external Public Testers group is not
  assigned. The App Store version remains Prepare for Submission; this is not
  a public release.
- Google Play prior release: version 1.0.8, build 14, was uploaded to Closed
  testing Alpha and marked Available to selected testers before build 16
  replaced it as the serving release. Google Play lists
  release 14 (1.0.8) as released on September 15, 2026 at 12:59 AM New York
  time. The checked `Testers` email list contains Kali's
  `kalimccarthy@gmail.com` address; no tester-list change was made during this
  read-back. On Android, the selected account can use
  `https://play.google.com/apps/testing/com.hoopsconnect.hoops_connect` to join
  the test, then install from Google Play. Production remains inactive.

Both new native archives were built against the existing production Firebase
project `hoops-connect-jm`; the hosted review site uses isolated staging data.
The web-only self-service account-linking screen was deployed after those
native archives were uploaded, so build 14 does not include that Profile
control. Its existing mobile Google/Apple sign-in code and production Firebase
provider configuration were not changed by the web-only linking pass.
This distinction matters for the meeting: accounts and changes made on staging
web do not automatically appear in the store-delivered app. The Android store
package and release signing certificate already have a Google OAuth client in
production. Registering that same package/fingerprint in staging produced a
cross-project conflict and no staging Android OAuth client, so a staging native
build with the same store identity is not safe for Google sign-in. The
test-only conflicting SHA-1 registration was removed from staging after this
check; production's fingerprint and OAuth client were not changed. Do not swap
the native Firebase configs or claim mobile/web data parity. Apple accepted the
iOS archive with one future-looking warning that the iOS 13 minimum must be
raised to iOS 15 by spring 2027; there were no validation or upload errors.

### Private Firebase App Distribution route

**September 17 update:** Android **1.0.18 (25)** is now distributed to the same
two-member Firebase `testers` group. The exact release is `6bq4f7j2qj22g`;
Kurt's existing app-level Android link is unchanged. Firebase-to-Firebase
build 24 → 25 installation was verified on the disposable Android emulator.
The iOS build compiled but is not distributed: neither Apple nor Firebase has
a registered iPhone test device, and no ad-hoc profile exists. The native
build still uses live mobile data, not the local JBL historical presentation
bundle. See [release 25 evidence and remaining gates](FIREBASE_TESTER_RELEASE_25.md).

Kurt's June WhatsApp thread contains separate Firebase App Distribution tester
links for Android and iPhone. The production Firebase project has an existing
`testers` App Distribution group with two members, Kurt and Kali; Kurt reported
installing and using the app. This route is separate from Google Play Closed
Alpha and Apple TestFlight. It can invite additional named testers without
making the app publicly listed, but an invitation to a binary does not create
an administrator account or change role permissions. Check the exact release,
recipient list, and signing before each distribution. Do not send a new link or
add a recipient just because the group exists.

On September 15, Android build 23 (`1.0.16`) was uploaded as the signed APK
to the production Firebase Android app and distributed only to the preexisting
`testers` group. CLI read-back reported success, and the group remained at two
testers with release count two. Authorized testers can use the stable release
page at
`https://appdistribution.firebase.google.com/testerapps/1:212612973375:android:2b6139ac0f5ee182db498a/releases/1pabpatg5kol8`.
Do not circulate the temporary one-hour direct binary download URL. Firebase
does not prove an in-place update over a Play-installed package because Play
app-signing and this release APK's certificate may differ; verify signing on
the device before recommending installation over an existing app.

The corrected Android build 24 (`1.0.17`) APK was subsequently uploaded and
distributed to that same preexisting two-member `testers` group. CLI read-back
reported `uploaded new release 1.0.17 (24)` and `distributed to testers/groups
successfully`; its stable, authorized-tester release page is
`https://appdistribution.firebase.google.com/testerapps/1:212612973375:android:2b6139ac0f5ee182db498a/releases/0d5pji1a0c3d0`.
This replaces build 23 as the recommended Firebase tester build, but does not
change Play's serving build 16 or prove install-over-Play signing compatibility.

For Android, Firebase App Distribution accepts APKs and, when the Firebase app
is linked to Google Play internal app sharing, AABs. Verify that integration
before distributing a future AAB; build 24 used the matching signed APK.
For iPhone, an App Store/TestFlight IPA is not automatically installable by this
route. Firebase ad hoc distribution requires the tester device UDID in the
provisioning profile and a matching ad hoc-signed IPA (or an Enterprise-signed
build). Verify Kurt's existing iPhone device registration and Apple signing
state before claiming an updated iPhone Firebase install. Both paths use the
production mobile Firebase project and therefore do not share the staging web
dataset by default.

## Full operations demo (local)

The local runner cannot use production credentials. All Firebase services are
bound to the presenter's loopback interface, and outbound delivery from the
Functions workers is blocked.

## Before the meeting

Use the same Mac and browser you will present from. The local URL is not
reachable from a phone or a second computer. Use screen sharing if the audience
is remote. Do not create a tunnel or expose the emulator ports.

From the repository root, run:

```text
node scripts/run_local_qa.js
```

That is the complete automated release gate. A passing run ends by itself. Then
start the persistent presentation:

```text
node scripts/start_local_qa.js
```

Wait for this line:

```text
HOOPSCONNECT_QA_INTERACTIVE_READY url=http://127.0.0.1:15500/ guardedCodebases=default,public stop=Ctrl-C
```

Keep that terminal open. Open `http://127.0.0.1:15500/` in Chrome. A visible
Firebase emulator notice is expected. It is a safety label and no longer blocks
the mobile navigation beneath it.

For a native iPhone simulator check, leave the presentation terminal running,
boot an iPhone simulator in Xcode, and run this in a second terminal:

```text
node scripts/run_ios_simulator_qa.js
```

The simulator runner makes a disposable source copy and removes the production
Firebase plist from that copy before Flutter or any Firebase plugin starts. It
uses the same synthetic accounts and loopback emulators, runs with Dart asserts
enabled, and deletes the copy when it stops. Never launch `lib/main_qa.dart`
directly from the production iOS project.

The runner discovers the repository-pinned Node 22, Java 21, Flutter 3.41.2,
Dart 3.11.0, and Firebase CLI 15.8.0 toolchain. On this Mac it prefers Android
Studio's Java 21 runtime even when the system `JAVA_HOME` points to a newer JDK.

## Synthetic accounts

Every account uses password `LocalQa-Only-42!`.

| Story | Email |
| --- | --- |
| Full control | `superadmin@hoopsconnect.test` |
| League administration | `admin@hoopsconnect.test` |
| Assigned stat entry | `statistician@hoopsconnect.test` |
| Team acknowledgment | `rep@hoopsconnect.test` |
| Media tools | `media@hoopsconnect.test` |
| Historical media alias | `press@hoopsconnect.test` |
| Read-focused member | `fan@hoopsconnect.test` |

The matching empty-state accounts add `-empty` before `@`, for example
`admin-empty@hoopsconnect.test`.

## Ten-minute presentation story

### 1. Public league, no sign-in

Start on the login page and point out the signed-out score preview. Select the
no-sign-in league option, then show:

1. Games: switch between National Basketball League, Women’s League, and
   Schoolboy League. Each league has its own colors, title sponsor, divisions,
   Latest result, and Next game. On the Games landing, the selected league owns
   one deliberate branded hero and its title-sponsor lockup is large enough to
   read. The presentation NBL treatment uses a dimensional royal-blue hero
   with a restrained diagonal sheen against a near-black association shell, a
   light-neutral page canvas, pale-green result emphasis, and elevated white
   cards. The current public NBL Jamaica mark is
   bundled for the showcase; its source and provisional-brand caveat are
   recorded in `assets/images/README.md`. The association partner returns in
   the footer instead of competing in the same header. Media, Standings, Leaders, and
   detail pages use a compact league context rather than repeating every logo.
   Open a game to show its public details, return to the date-grouped
   Schedule, then switch to Calendar and choose a game day. Published regulation
   and overtime finals plus the upcoming schedule are available. Submitted,
   changes-requested, and in-progress states stay inside the signed-in
   operations views.
2. Media: the newest public league headline appears on Games, and Media is the
   second signed-out tab. Switch leagues to show that association-wide stories
   remain available while division-scoped stories follow their parent league.
   Internal and archived posts never enter the public snapshot.
3. Game details: quarter scoring, box score, source/version label, and sharing.
   Open the final-score share card and point out the two team marks, league
   lockup, quieter association endorsement, result, and readable title-sponsor
   plate. Uploaded team logos are used first; team initials appear only as the
   fallback. The same public release can also create a box-score summary. Player
   details, team details, standings, and leaders each expose a content-specific
   share action, with publication/version validation immediately before the
   artifact leaves the app.
4. Standings: each league shows only its own child divisions. Schoolboy League
   holds Division A, Division B, Division C, and Girls Division beneath it. NBL
   holds Premier, Division 2, Division 3, and Community League. Divisions never
   appear as independent top-level leagues.
5. Leaders: switch PTS, REB, AST, STL, and BLK, then open a player.
6. Privacy boundary: the player page explicitly uses only cleared public fields
   and exposes no account, contact, school, or guardian data.
7. Fan reason to sign in: select Follow teams. Scores remain public. After a fan
   signs in, Settings lets them follow individual teams or every team in a league
   and opt into final-score alerts.

Media publication check:

- Verify every team, player, score, and date against the approved source.
- Use one clear headline, a useful summary, and a properly licensed image when
  an image adds information.
- Select the correct child division so the story appears beneath its parent
  league, or leave the division blank for an association-wide announcement.
- Preview on phone and desktop, then have an admin mark the item public. Keep
  drafts internal and archive outdated notices.

### 2. League operations

Sign in as `superadmin@hoopsconnect.test`.

1. Board: show the pinned public welcome post and the urgent internal
   game-day operations check-in.
2. Admin: show the active synthetic season, 42 teams, nine divisions, games
   needing review/stats, and the acknowledgment tracker.
3. Open the acknowledgment tracker. The expected recipient is the assigned
   St George’s Slayers representative and the UI displays the team name, never its
   internal ID.
4. Open Association Brand & Mega Sponsor, then Leagues & Sponsors. The first
   controls identity and sponsor recognition across the whole association. The
   second gives a three-step workflow to create the parent league, add divisions
   beneath it, then set its colors and own title sponsor. Open View league
   hierarchy to show every division nested under exactly one league. A parent
   league cannot be removed while it still owns divisions. Its child divisions
   must be permanently deleted first. The catalog is
   bounded at 100 leagues per association, rather than a fixed set of
   hard-coded competitions.
5. Open Teams & Rosters and create or edit a team. The team editor accepts a
   PNG, JPG, or WebP team logo up to 2 MB and shows a preview before saving.
   Uploaded team marks flow into public score rows and team identity; initials
   remain the fallback when a team has not supplied a logo.
6. Briefly show User Management, Divisions, Game Schedule, and
   role preview. Do not save presentation-time changes unless the walkthrough
   specifically needs them. Restarting the runner restores the exact seed.

### 3. Assigned work

Sign out, then use the account that matches the audience's priority:

- Statistician: `statistician@hoopsconnect.test`, open Game Stats and show the
  submitted, changes-requested, live, and post-game entry paths.
- Team representative: `rep@hoopsconnect.test`, open Board and acknowledge the
  game-day check-in, then show the team-scoped view.
- Media: `media@hoopsconnect.test`, open Media and show published summaries,
  comparison tools, and cleared exports.

If time is short, stay signed in as super admin and use role preview to explain
the navigation difference. A normal sign-in is the stronger proof.

## Exact status language

Safe description for the hosted acceptance site:

> This is the current HoopsConnect acceptance environment using synthetic data
> in a Firebase project that is separate from production. Administrators can
> sign in and use the role-based league, division, team, schedule, season, and
> membership workflows. Search indexing is disabled. Staging Functions are
> deployed behind the application authorization checks, with a five-dollar
> monthly Functions spend cap. The public fan snapshot remains a safe synthetic
> evaluation release rather than an automatic production publication feed.

Safe description for the local operations demo:

> This is the current release candidate running locally with synthetic data. It
> demonstrates the public league experience and the role-based operations app
> without touching production. Version 1.0.7, build 13 is currently available
> to the private Apple internal QA group and the private Google Play Alpha track.
> The app has not been publicly launched.

The local presentation uses ShipSafe SDK as the NBL title-sponsor example. Bank
of Kingston, YardCourt Sporting Co., and Kingston Flame Kitchen are explicitly
fictional demo brands created for this showcase. They do not represent real
sponsorship agreements. The three named leagues are presentation fixtures, not
product defaults. An administrator creates the association's actual leagues and
may remove or rename the fixture examples. The
favorite-team final-score delivery path is implemented and emulator-tested, but
no real fan push is sent until the separately approved production deployment.

## Share-system QA summary

The September 14 design review covered final-score, box-score, player,
team-stat, standings, and leader sharing. The release-critical corrections are
implemented in the hosted acceptance site:

- The final score identifies both teams with uploaded marks or clear initials.
- The association, league, HoopsConnect, and title sponsor have distinct visual
  jobs instead of competing at one level.
- The league lockup is prominent, while HoopsConnect stays in the footer.
- The title sponsor has a readable white plate inside a fixed broadcast rail.
- The share subject sits directly on a full-bleed midnight-to-royal canvas,
  with cinematic arena depth, strong score typography, restrained gold rules,
  shallow tonal shadows, and subtle court geometry. The arena plate contains
  no baked-in identity or score, and the nested rounded content panel is gone.
- Short player and team cards use a compact stat deck, while rankings use
  ordered rows, so no content type is left floating between large empty gaps.
- Final-score, box-score, player, team, standings, and leader actions reuse the
  public snapshot and revalidate its publication/version before sharing.

The next share expansion is multiple export templates: 1080 by 1350 for feed
posts, 1080 by 1920 with Story safe areas, and server-rendered 1200 by 630 link
previews for public URLs. The current release uses the established 4:5 image
card and platform share sheet; do not claim the Story or automatic link-preview
templates are already shipped.

Do not call staging the production website, say it is indexed, or imply that the
official JBA website was changed. Do not say that website integration, public
store release, or every physical-device path is live. The official-stat v2,
courtside recovery, and account-deletion candidates remain intentionally
dormant until JBA approves the competition, custody, and privacy rules they
depend on.

## Quick recovery

- Hosted staging sign-in fails: use the exact Full control email and shared
  password in Synthetic accounts. Do not use a production account.
- Hosted staging data was changed during rehearsal: from the repository root,
  rerun the guarded synthetic seed command recorded in
  `scripts/seed_staging_demo.js`. It refuses production and unconfirmed targets.

- Page looks stale: hard refresh Chrome, then sign in again if needed. The
  synthetic QA session intentionally does not persist across reloads. The
  terminal must still show running emulators.
- Navigation does not respond: confirm the current URL is
  `http://127.0.0.1:15500/`, then hard refresh.
- Wrong data or a walkthrough mutation: press Ctrl-C once, rerun
  `node scripts/start_local_qa.js`, and wait for the READY marker.
- Port already in use: close the earlier presentation terminal with Ctrl-C. Do
  not kill unrelated system processes.
- Sign-in fails: confirm the exact synthetic email and shared password above.
- Browser is lost: reopening the loopback URL is enough while the terminal is
  running.

## Stop and clean up

Press Ctrl-C once in the presentation terminal. The synthetic state and the
temporary credential-isolation directory are discarded. No production cleanup
is required because the presentation never connects to production.

For the hosted association trial, leave the familiar example leagues, teams,
rosters, results, and media in place while representatives are evaluating the
admin workflow. At the agreed end of the trial, inventory the exact staging
records and export a recoverable backup, then remove those evaluation records
from the isolated staging project and verify the public feed is empty. Preserve
the established administrator login and the app infrastructure unless Kali
specifically includes them in the reset. The association can then create its
own leagues, child divisions, teams, and rosters from scratch. This hosted reset
has **not** been performed yet; no production records should be included.

## Next approval gate

After the presentation, record JBA's decisions on competition/ranking rules,
statistical qualification, roster authority, privacy/minors, account lifecycle,
staging region/billing, backup/recovery, monitoring, and rollout ownership. Only
then prepare a staging rehearsal and a separately approved production release.

## September 17 local JBL historical bundle (not deployed)

The bundled public presentation now uses Kurt's **Jamaica Basketball League**
marks, ten team logos and 188 player records from **2025 First Round**, dated
April 10, 2025. FOSKA Oats is Main Sponsor; ShipSafe and YardCourt appear only as
explicit demo supporting-sponsor examples. No new official division, standings,
fixtures, current roster or individual game result was invented.

See [JBL local import and rollback instructions](JBL_LOCAL_IMPORT.md) for scope,
source limitations and the loopback-only, Firebase-free QA build. This local
bundle does not change Firebase App Distribution build 24, store releases, the
hosted site or live data. The YouTube highlights concept is roadmap-only.
