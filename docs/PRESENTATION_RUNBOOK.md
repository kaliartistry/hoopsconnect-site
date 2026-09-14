# HoopsConnect presentation runbook

Last rehearsed: 2026-09-14

This runbook starts a local, release-mode HoopsConnect presentation with only
synthetic data. It cannot use production credentials, all Firebase services are
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

1. Games: start with the date-grouped Schedule, then switch to Calendar and
   choose a game day. Published regulation and overtime finals plus the upcoming
   schedule are available. Submitted, changes-requested, and in-progress states
   stay inside the signed-in operations views.
2. Game details: quarter scoring, box score, source/version label, and sharing.
3. Standings: Premier and Development are grouped separately so ranks restart
   clearly inside each division.
4. Leaders: switch PTS, REB, AST, STL, and BLK, then open a player.
5. Privacy boundary: the player page explicitly uses only cleared public fields
   and exposes no account, contact, school, or guardian data.

### 2. League operations

Sign in as `superadmin@hoopsconnect.test`.

1. Board: show the pinned public welcome post and the urgent internal
   game-day operations check-in.
2. Admin: show the active synthetic season, four teams, two divisions, games
   needing review/stats, and the acknowledgment tracker.
3. Open the acknowledgment tracker. The expected recipient is the assigned
   Kingston Lions representative and the UI displays the team name, never its
   internal ID.
4. Briefly show Teams & Rosters, User Management, Divisions / Leagues, Game
   Schedule, Branding & Sponsor, and role preview. Do not save presentation-time
   changes unless the walkthrough specifically needs them. Restarting the runner
   restores the exact seed.

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

Safe description:

> This is the current release candidate running locally with synthetic data. It
> demonstrates the public league experience and the role-based operations app
> without touching production. Build 13 was previously uploaded to the private
> iOS and Android test tracks, but the app has not been publicly launched.

Do not say that production Hosting, website integration, public store release,
or every physical-device path is live. The official-stat v2, courtside recovery,
and account-deletion candidates remain intentionally dormant until JBA approves
the competition, custody, and privacy rules they depend on.

## Quick recovery

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

## Next approval gate

After the presentation, record JBA's decisions on competition/ranking rules,
statistical qualification, roster authority, privacy/minors, account lifecycle,
staging region/billing, backup/recovery, monitoring, and rollout ownership. Only
then prepare a staging rehearsal and a separately approved production release.
