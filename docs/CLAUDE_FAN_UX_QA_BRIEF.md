# HoopsConnect fan experience QA and design recommendations

Requested by Kali, September 17, 2026. Review and recommendations, not a shared
source implementation or deployment task. Save a report and screenshots in a
new task-scoped scratch directory and give the paths back in your response.

## Baselines

- Live web: https://hoopsconnect-jba-staging.web.app/public/games
- Stats: https://hoopsconnect-jba-staging.web.app/public/leaders
- Team stats: https://hoopsconnect-jba-staging.web.app/public/team-stats
- Compare: https://hoopsconnect-jba-staging.web.app/public/compare
- Team: https://hoopsconnect-jba-staging.web.app/public/teams/st-georges-slayers
- App source: /Users/kaliartistry-mac/Jamaica Basketball App
- Published comparison build: 1.0.19+29. Android is on the existing Firebase App
  Distribution testers group, not a new Google Play or Apple store release.
- Source is deliberately dirty. Do not reset, discard, commit, or overwrite it.
  A new unpublished team-game-list visual patch uses team logos and nicknames in
  public_team_identity.dart and public_team_detail_screen.dart. Distinguish it
  from the deployed Build 29 web/native baseline. No new box-score redesign has
  been implemented yet. Source snapshot timing and build identity must be noted.

## User priority

Familiar, easy navigation on both mobile web and native app. Weight the things
fans expect to find quickly: latest scores, next games, team schedule, past-game
box scores, player and team statistics, comparisons, sharing and useful media.
The present box score stacks too much vertically. The team game list should
use existing real logos and concise names such as Slayers, Rebels, Celtics,
Warriors, preserving the full identity on profiles and accessibility labels.

## Reference comparison

Inspect actual mobile-width interfaces, not just source markup:

- https://www.espn.com/nba/boxscore/_/gameId/401766128
- https://www.nba.com/game/ind-vs-okc-0042400407/box-score

Codex inspected both at 390x844 in Chrome. Suggested direction to independently
challenge: compact score header, clear game-view navigation, team-separated
player tables, names kept visible while stats scroll, important numbers first.
Borrow familiar interaction patterns, not proprietary artwork or page copies.

## Hands-on web checks

Use phone widths around 360/390/430 and desktop. Start signed out; test existing
signed-in state only if accessible, without signing Kali out or changing his
account. Trace Games -> league/team -> past result -> box score -> player ->
compare -> share preview -> back. Check Stats Players/Teams/Compare, search by
player or team, league/season context, statistical definitions, next games,
last five available meetings, Follow, and public media.

For comparisons test two rival teams, two players, same selection rejection,
missing numbers, switching league, returning from a game, and sponsor branding.
Verify current public release validation, but do not mutate/retract real data
to test it. Automated mocks are appropriate for those failure states.

Sharing: score, box score, standings, player, team comparison, player comparison,
media where available. Confirm preview opens, logos/sponsor, long-name wrapping,
text contrast, correct period/context, readable PNG output, Save image, and
native share chooser if supported. Do not actually send/post to real recipients.

## Native simulator checks, if available

Reuse the earlier safe QA method: disposable source copy, dedicated emulator
and iPhone simulator, local/offline fixtures or emulator-only Firebase setup.
Strip production Firebase configuration from scratch simulator builds. Do not
point a QA write workflow at either hosted project. Do not erase user-owned
simulators, change signing, upgrade SDKs, touch credentials, or terminate
unrelated processes. Smoke-test navigation and sharing on Android and iOS.
If a platform cannot be tested, state the exact limitation; a compiled build
or browser viewport is not simulator interaction evidence.

## Data and scope constraints

This is an understood presentation/training dataset. Preserve existing real
team names, logos and sponsors. No data import, invented records, deletions,
historical-stat recalculation, backend/rules/auth edits, cloud billing changes,
store release, hosted deployment, or external messages during this QA.
Do a quick code orientation only to explain UI findings. Do not turn this into
a broad architecture audit. Do not modify shared app code. Proposed patches or
wireframes can live in your scratch report, clearly labeled as proposals.

## Return report

1. Prioritized defects and usability findings with exact route, platform, steps,
   expected vs actual behavior, screenshot and severity.
2. A ranked fan information hierarchy and proposed mobile/web navigation.
3. Annotated before/after wireframe or concise visual suggestion for a team
   game row and the box-score page, including logo and compact-name treatment.
4. Immediate fixes vs optional later ideas, with the smallest practical scope.
5. QA matrix separating passed, failed, not tested and blocked. Exact build/
   source snapshot identity and the complete evidence directory.

No automatic implementation is authorized in this review. Return recommendations
so Codex and Kali can evaluate them together.
