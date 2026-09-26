# HoopsConnect share-system QA report

Date: September 14, 2026

## Verdict

The current 4:5 share experience is ready for the private JBA presentation on
the hosted staging site. It is useful beyond a generic score image: the source
league is obvious, team identity is immediate, the sponsor is readable, and
the exported content is tied to the same versioned public release that the fan
page displays.

The broader social package is not finished. Story-specific 9:16 cards and
server-rendered 1.91:1 link previews remain the next expansion and must not be
described as live.

## What is live

The public experience now exposes content-specific share actions for:

- Final scores
- Box-score summaries
- Player season spotlights
- Team snapshots
- Standings
- Category leaderboards

Final-score and box-score cards show both teams, their scores, and uploaded team
logos when available. Initials remain the explicit fallback. Box-score cards
keep the four period results plus one leading performer from each team, rather
than shrinking a complete player table into an unreadable image.

Every card keeps four identities separate:

1. Jamaica Basketball Association is the quiet endorsing organization.
2. The selected league owns the main logo and name.
3. The score, player, team, standings, or leader content is the focal point.
4. HoopsConnect and the league title sponsor occupy opposite sides of the
   footer.

The sponsor plate uses the real transparent ShipSafe asset and a larger white
plate. The NBL mark uses the sharper official artwork with a deterministic
transparent-background cutout; it was not recreated by an image generator.

## Visual QA evidence

The live mobile check covered the 390 by 844 layout used in the presentation
screenshots. The final-score, box-score, player, team, standings, and leader
share sheets all opened from their real public pages. The browser reported no
warnings or errors.

The leader-card download completed through the hosted browser and the app
reported the generated PNG was accepted by the platform. Share, Copy text, and
Download image remain separate actions so a fan can choose the fastest route
for the platform they use.

Review surfaces:

- Hosted fan experience: <https://hoopsconnect-jba-staging.web.app/public/games>
- Final game and box score: <https://hoopsconnect-jba-staging.web.app/public/games/qa-final-game>
- Player spotlight: <https://hoopsconnect-jba-staging.web.app/public/players/st-georges-slayers-p1>
- Team snapshot: <https://hoopsconnect-jba-staging.web.app/public/teams/st-georges-slayers>
- Standings: <https://hoopsconnect-jba-staging.web.app/public/standings>
- Leaders: <https://hoopsconnect-jba-staging.web.app/public/leaders>
- Claude Design share-system canvas:
  <https://claude.ai/design/p/019df151-45f3-7e47-8fd3-c5b493957288?file=HoopsConnect+Share+System.html>

## Claude Design review and implementation decision

Claude Design produced a five-page, ten-frame share-system canvas covering the
trigger sheet, 4:5 score post, 9:16 Story, 1.91:1 link preview, box-score
summary, player spotlight, standings, safe areas, fallbacks, and Flutter share
layer guidance.

Adopted for the presentation build:

- Team marks are visually necessary, not decorative.
- The association is demoted to an endorsement band and the league becomes the
  prominent competition identity.
- The losing score is visually quieter.
- ShipSafe is isolated on a compact white plate inside a fixed sponsor rail.
- HoopsConnect stays in the footer so it does not compete with the league.
- The old rounded panel-inside-a-card treatment is removed. A full-bleed
  midnight-to-royal arena canvas now carries one dominant score or subject
  zone, live court depth, restrained court-line texture, and a narrow
  metallic-gold structure. The arena plate is text-free; every identity and
  statistic remains dynamic.
- Heavy condensed display treatment is reserved for scores and content labels;
  clean smaller type handles the league, source, and supporting statistics.
  Longer labels scale down safely instead of wrapping or clipping.
- Shadows are shallow and tonal: strong enough to separate team marks and the
  sponsor rail, but not large enough to make the card look like stacked tiles.
- Short player and team payloads use a compact stat deck. Rankings use ordered
  rows. These structures replace the empty flexible gaps that previously left
  content floating in the canvas.
- The capture boundary contains only the card, so debug or emulator banners
  cannot enter the saved image.
- Box-score content is reduced to periods and two useful performer lines.

The refinement was checked against current sports and social-creative guidance:
Monotype's sports typography guidance on narrow cuts and distinctive numerals,
Material guidance on elevation and softer shadows, Meta's 1080-pixel creative
and safe-zone guidance, and current NBA/FIBA/EuroLeague broadcast graphics. The
result uses those hierarchy principles without copying another league's visual
identity.

Scheduled next rather than rushed into the presentation build:

- 1080 by 1920 Story layout with platform-safe top and bottom zones
- 1200 by 630 server-generated link preview for every public share URL
- Per-device format memory and first-class Save to Photos on native platforms
- Share completion analytics by league, content type, format, and destination
- Player game-line cards with an approved player photo field

## Verification

- Flutter static analysis of `lib` and `test`: passed with no issues. The
  repository-wide command still reports 35 informational style notices in the
  vendored `third_party/unorm_dart` package, with no app errors or warnings.
- Full Flutter suite: 950 passed and 16 intentionally skipped.
- Focused share payload and share-sheet gate: 25 passed.
- Cloud Functions TypeScript build: passed before deployment.
- Public snapshot tests: 24 passed.
- Hosted mobile share flows: final score, box score, player, team, standings,
  and leaders all opened successfully.
- Hosted PNG download: accepted by the browser platform.
- Hosted browser console: zero warnings and zero errors during the final pass.

## Environment and remaining boundary

The staging web build is the latest presentation build. The private Apple and
Google tester binaries remain version 1.0.7, build 13, and do not contain this
new web presentation pass.

The staging Firebase project has twenty-two deployed Cloud Functions, a USD 5
monthly project budget alert, and a separate USD 5 monthly Cloud Run Functions
spend cap. Cloud billing reports with delay, so a small overage remains
possible. Production was not changed.

The public snapshot publisher is still deliberately dormant. The hosted fan
pages use the safe synthetic release seeded for this evaluation; changing a
private operations score does not automatically republish the public snapshot.
That production publication pipeline remains a separate approval gate.

## September 15 release update (supersedes the tester-build statement above)

Build 24 (`1.0.17+24`) is the corrected mobile release candidate from this
single Flutter codebase. The September 14 visual verdict above still describes
the staging card design; its old build-13 tester status and verification counts
are historical, not current. The full current Flutter suite passed with 984
tests and 16 intentional skips, and static analysis of `lib` and `test` passed
with no issues. The Build 24 website is live at the same isolated,
non-indexable staging URL. The Android Build 24 AAB was accepted and submitted
to Google Play Closed Alpha; automated quick checks passed and the change is
in review, not yet installable from Play. The matching Android APK was
distributed only to the existing two-member Firebase App Distribution tester
group. The iOS Build 24 IPA passed Apple's validation and upload with no
errors, delivery UUID `2d4417c1-4620-4506-85ab-3f976ee776de`. It then
processed successfully, and App Store Connect read back `Testing` in the
preexisting one-tester HoopsConnect Internal QA group. Neither platform is
publicly released.

Claude's isolated Android and iPhone simulator retest of the Build 24 source
verified that a legacy-final Box Score share opens the score for the game
actually being viewed, not a fixed sample. Copy text matched its score and
matchup, Save wrote a PNG to Android Gallery and iOS Photos, and the native
share sheets opened. With no posted stats, there was no misleading share icon.
The iPhone Games, Media, Standings and Leaders tabs and league/division menus
displayed in full. This QA used scratch debug builds with production Firebase
configuration removed, not the signed app-store binaries. The final source
also hides Player Stats and Leaders share controls when their own public,
versioned records do not exist; it does not substitute sample people.

The two known small follow-ups are a UTC-versus-Jamaica date mismatch in a
saved evening-game PNG filename, and a 52-pixel overflow in the older Box
Score player table on a narrow iPhone. Neither changes the score on the card
or blocks its Share/Copy/Save actions. Real social-app share targets and the
already-installed Google Play package were not exercised in the disposable
simulators. Staging's configured sponsors appear in its share cards. The
older production public feed has no sponsor for the legacy final checked in
Claude's offline copy, so that specific real-feed card has an empty sponsor
rail until the association or league config supplies one.

Visual evidence (local simulator captures):

- Android current-game share sheet:
  `/private/tmp/claude-501/-Users-kaliartistry-mac-Jamaica-Basketball-App/ee89327f-5340-4106-b75c-3087b61a43a1/scratchpad/shots/b24_03_legacy_box_sheet_small.png`
- iPhone current-game share sheet:
  `/private/tmp/claude-501/-Users-kaliartistry-mac-Jamaica-Basketball-App/ee89327f-5340-4106-b75c-3087b61a43a1/scratchpad/shots/ios10_02_box_legacy_share_card.png`
- iPhone sponsor-branded Schoolboy example:
  `/private/tmp/claude-501/-Users-kaliartistry-mac-Jamaica-Basketball-App/ee89327f-5340-4106-b75c-3087b61a43a1/scratchpad/shots/ios9_03_schools_score_card.png`

The exact provider state and safe tester links are maintained in
`docs/PRESENTATION_RUNBOOK.md`.
