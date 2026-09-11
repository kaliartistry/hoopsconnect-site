# Access and route contract v1

Status: Stage 1 client contract. Public detail destinations and account-deletion
orchestration remain owned by their later workstreams; this document reserves
their stable URLs and access behavior.

## Authority boundary

`lib/app/router/app_route_contract.dart` is the shared client navigation matrix.
It improves discoverability and denies protected direct URLs, but it is not the
data authority. Every read/write remains subject to the server-owned membership,
Firestore Rules, and callable authorization. Route guards always inspect the
real membership-backed user. Super Admin role preview changes presentation only.

## Stable paths

| Path | Session contract | Current destination |
| --- | --- | --- |
| `/public/games` | Public | Mounted public snapshot Games surface |
| `/public/standings` | Public | Reserved for public experience packet |
| `/public/leaders` | Public | Reserved for public experience packet |
| `/public/games/:eventId` | Public | Reserved public game detail |
| `/public/teams/:teamId` | Public | Reserved public team detail |
| `/public/players/:playerId` | Public | Reserved public player detail |
| `/stats/assigned` | Active membership plus `stats.enter` | Assigned game selection |
| `/stats/assigned/:eventId` | Active membership plus `stats.enter` | Post-game entry |
| `/stats/assigned/:eventId/revision` | Active membership plus `stats.enter` | Requested revision entry |
| `/account/delete` | Authenticated, active membership not required | Deletion request handoff |
| `/account/deletion/status` | Public route plus future read-only status capability | Coarse cleanup status handoff |
| `/account/deletion/reconcile-device` | Authenticated, active membership not required | Local official-work reconciliation handoff |

`/admin/stats`, `/admin/stats/:eventId`, and `/live-stats?eventId=...` remain
compatible notification/bookmark aliases. They require `stats.enter` and do not
require Admin-panel access. Media is the only new user-facing label, while the
historical `press` wire value retains the same route behavior as `media`.

## Sign-in and denial behavior

- A signed-out protected URL is carried as an encoded same-app `from` value.
- After sign-in, it is restored only when the path is registered and the real
  membership permits it. External, scheme-relative, unknown, or unauthorized
  values are discarded.
- A fan without an internal Board capability starts at `/standings`, which is a
  visible selected navigation destination.
- An authenticated account with a missing, suspended, outdated, or mismatched
  membership is sent to `/access-blocked`, except that deletion request, status,
  and device-reconciliation routes remain reachable.
- A valid active membership that lacks a destination capability is sent to the
  explicit `/access-denied` recovery screen. Refresh and browser Back run the
  same guard again.

## Integration requests

- The public experience owner should mount the reserved Standings, Leaders, and
  detail paths using public projections only. No reserved route may fall back to
  a private repository.
- The account lifecycle owner should replace the three handoff screens without
  changing their reachability. `/account/deletion/status` must validate its
  future read-only capability before returning status data.
- The integration owner must review the `app_router.dart` dormancy hash
  transition. Preserve every candidate-exclusion and import-graph assertion;
  update only the exact reviewed router baseline pin.
- Add `package_info_plus` and a concrete `AppVersionLoader` adapter at
  integration. The current dependency-free loader reports unavailable metadata
  unless the build supplies explicit `FLUTTER_BUILD_NAME` and
  `FLUTTER_BUILD_NUMBER` defines; it never guesses a version.
