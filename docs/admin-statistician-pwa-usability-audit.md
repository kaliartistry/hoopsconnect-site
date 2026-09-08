# Admin/Statistician PWA Usability Audit

Date: 2026-06-30

Status: FAIL-NON-BLOCKING

Reason: static code review shows the core admin/statistician web workflows are present and likely usable for a controlled demo or pilot, but live browser/tablet testing with seeded Firebase data and role-specific accounts was not available in this workspace.

## Screens Reviewed

- Login: `lib/features/auth/login_screen.dart`
- App shell/navigation: `lib/app/app_shell.dart`
- Admin dashboard: `lib/features/admin/admin_panel_screen.dart`
- Team management: `lib/features/admin/team_list_screen.dart`
- Roster management: `lib/features/team/team_view_screen.dart`
- Schedule hub/add game/generator: `lib/features/admin/schedule_hub_screen.dart`, `add_game_screen.dart`, `schedule_generator_screen.dart`
- Game stats game picker: `lib/features/stats/stat_game_select_screen.dart`
- Post-game stat entry/approval: `lib/features/stats/stat_entry_screen.dart`
- Live stats: `lib/features/stats/live_stats_screen.dart`
- Standings: `lib/features/stats/standings_screen.dart`
- Leaderboards: `lib/features/stats/leaderboard_screen.dart`
- Posts/announcements: `lib/features/board/board_screen.dart`
- Acknowledgment tracker: `lib/features/ack/ack_tracker_screen.dart`
- User/role management: `lib/features/admin/user_management_screen.dart`
- Invite code management: `lib/features/admin/invite_code_management_screen.dart`

## What Looks Ready Enough For Demo/Pilot

- The app shell switches to `NavigationRail` on wider screens.
- Admin dashboard has a desktop-specific sidebar/main layout.
- Board has a desktop two-column list/detail layout.
- Live stats includes desktop/web keyboard shortcuts and layout handling.
- Live stats setup constrains content width and adapts starter selection layout.
- Post-game stat entry has horizontally scrollable stat grids.
- Stat entry lifecycle is clear: draft/save, submit, approve, send back, locked approved state.
- Game stat picker clearly separates live stats and post-game entry.
- Empty, loading, and error states exist on most reviewed screens.
- SPA rewrite in `firebase.json` should support browser refresh on deep routes once hosted.

## Critical Issues

- Full usability is not verified without real browser/device testing against Firebase data.
- No demo accounts or seeded production-like data were verified.
- Some admin screens are still mobile/list-first rather than dense desktop tables.
- User management reads all users and displays emails; acceptable for super-admin workflow, but not public-facing.
- Invite-code creation asks for a raw Team ID instead of a team picker, which is error-prone for JBA staff.
- Post-game stat entry creates a new `TextEditingController` per cell build; this can be acceptable for a demo but should be profiled/polished for large rosters.

## Nice-To-Have Issues

- Add desktop table views for teams, users, divisions, invite codes, and acknowledgment tracking.
- Add filters/search to game stats picker and schedule/admin lists.
- Add team picker to invite-code creation.
- Add browser route refresh smoke tests after hosting.
- Add tablet portrait and landscape QA checklist with screenshots.
- Add keyboard shortcut discovery/testing for live stats.
- Add explicit permission-denied screens instead of silent redirects for admin/stat routes.

## Pilot-Blocking Assessment

Not blocking for a controlled demo:

- List-first admin screens.
- Missing desktop tables.
- Lack of website public API.

Potentially blocking for a real game-day pilot:

- No live venue/tablet test.
- No confirmation of seeded rosters, active season, and scheduled games.
- No confirmed demo/statistician accounts.
- No verified network/offline behavior at venues.

## Recommended Fixes

Before a JBA demo:

1. Create demo users for admin, statistician, rep, media, and fan.
2. Seed one active season, divisions, teams, rosters, and at least two games.
3. Walk through login, admin dashboard, game stat picker, post-game entry, live stats setup, and ack tracker on laptop.
4. Use the role preview only as a supplement; real role accounts should be tested.

Before a pilot:

1. Test on an actual tablet in landscape and portrait.
2. Test a laptop/touchscreen stat-table scenario.
3. Run a complete stats lifecycle: scheduled game -> stat entry -> submit -> admin approval -> standings/leaderboards rebuild.
4. Run an ack lifecycle: create post -> expected reps populated -> rep acks -> tracker updates.
5. Confirm venue network conditions and decide whether offline stat entry is required for the pilot.

## Verification

Static inspection only:

- `flutter analyze`: PASS after role fix.
- `flutter test`: PASS after role fix.
- `flutter build web --release`: PASS after role fix.

Live browser/device verification: BLOCKED-EXTERNAL pending Firebase data, demo users, and hosted/local authenticated session.

