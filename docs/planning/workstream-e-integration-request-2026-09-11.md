# Workstream E integration request: public routes and result release

Status: candidate implementation only; no route, rule, trigger, or production
activation change is in this branch.

Baseline: Stage 0 integration commit `6e74ba13faf316da2c506c2cafcfca985dd774cc`.

## What E now provides

- A compatibility public snapshot fingerprint shared by the league screen,
  public game/team/player detail models, media result view, share payload, and
  CSV exports.
- Explicit published, unavailable, and retracted states. Retracted documents
  discard stale rows in the client model and the public snapshot builder.
- Public-only result detail screens. They receive a `PublicLeagueSnapshot` and
  cannot import private game, user, post, acknowledgment, or roster readers.
- Result artifacts require one versioned published snapshot and one matching
  result version. `resultVersion` is now the canonical SHA-256 digest of the
  displayed game/team identity, score, period rows, allowlisted player rows,
  and recap. A supplied `publicResultVersion` that does not exactly match that
  content aborts projection; the Dart DTO recomputes the same digest before an
  artifact becomes eligible. The compatibility fingerprint is not an
  official-stat v2 certificate or release ID.
- The media dashboard uses that same public snapshot for result discovery,
  today's schedule, leaders, recap/detail, and capability-gated game/season CSV.
  It has no private result, schedule, or leader fallback.
- Player rows cross the compatibility projector only through the explicitly
  pre-whitelisted `publicPlayerLines[].publicDisplayName` and
  `rankings[].publicDisplayName` fields. Legacy name/player maps are not a
  fallback.
- The client keeps legacy v1 games and standings readable but suppresses legacy
  player/leader identity rows. Those rows return only with the v1.1 allowlist
  and an explicit privacy epoch, so integration should expect Leaders to remain
  unavailable until that policy-bound snapshot exists.
- Media Head-to-Head now reads teams, records, games, players, and metrics only
  from the same public snapshot. It has no imports of the private season, team,
  roster, or stats providers.
- The dormant projector prepares immutable `public-release-v2` release data:
  a manifest plus content pages capped at a conservative 480 KiB JSON budget.
  A release is rejected if one item, the manifest, or the 64-page bound would
  be exceeded. There is no silent row truncation.
- Source reads filter by the exact current `seasonId` before each 200-document
  page and paginate deterministically by document ID until exhaustion.
- A current pointer can advance only after an exact transaction-time match of
  the server-owned source token, monotonic source sequence, and source commit
  time, current season, publication state, privacy epoch, and protocol. The
  trusted writer must atomically issue a unique, never-reused token, increment
  the sequence, and persist the commit time on every source mutation. A pointer
  never moves to a lower sequence. This
  prevents an older or mixed rebuild from overwriting a newer publication or
  retraction.
- The compatibility builder reports `compatibilityCandidate`, never
  `certified` or `legacyApproved`. No Cloud Function trigger is registered in
  this candidate, so it cannot mutate the live public projection by deployment.
- `DormantVersionedPublicReleaseRepository` is the matching, unmounted v2
  client. It reads the exact pointer path, manifest, and every referenced page;
  verifies page/release/source digests, ordering, counts, size bounds, state,
  season, and privacy epoch; then rereads the pointer before returning. Missing,
  duplicate, changed, oversized, or stale data fails closed.
- Public artifact actions use an injected current-release validator. The
  active legacy adapter performs a Firestore `Source.server` document read; the
  dormant v2 repository uses `Source.server` for its pointer, manifest, every
  page, and final pointer reread under the same contract. There is no cache
  fallback for artifact eligibility, so offline actions fail closed. Display
  streams retain their normal cache behavior. Game share, copy,
  and CSV actions validate immediately before the action and after any
  asynchronous platform handoff. The share sheet also validates before image
  capture, immediately before its platform call, and before reporting success.
  If a handoff may already have completed, the UI says the artifact may be
  outdated instead of claiming that nothing was written.
  Validation binds the v2 release ID when present and otherwise binds the
  legacy publication timestamp in addition to snapshot/result versions, so an
  exact-content republish is still treated as a different release.
- The active `publicLeagueSnapshotProvider` still reads the legacy monolithic
  snapshot. It is intentionally not pointed at v2 while v2 has no deployed
  projector/rules. The dormant projector and dormant v2 client must be enabled
  together, never one at a time.

## Request to A: publish the public route namespace

Integration must mount the already accepted canonical `PublicRoutePaths`
names and builders for these destinations before E edits `lib/app/`:

1. public league landing;
2. public game detail by stable game ID;
3. public team detail by stable team ID;
4. public player detail by stable player ID.

The routes must be classified as unauthenticated public routes before the global
auth redirect, preserve browser Back/refresh and permitted requested deep links,
and expose a canonical URI builder to the share layer. Unknown IDs must remain a
public 404/unavailable state and must never redirect to a similarly named private
detail route. Query parameters for division/season filters may be added after
their canonical encoding is agreed.

Until that contract lands, `PublicLeagueScreen` uses local `Navigator` pushes so
the detail UI can be tested without claiming shareable public URLs. Share text
therefore omits a URL unless a canonical URI is explicitly supplied.

## Request to D: publish the accepted result interface

E needs the following immutable, read-only fields from the accepted D release:

- release ID, projection version, publication epoch, privacy epoch, state, and
  generated/published time;
- stable game ID, result revision/hash, schedule revision, status, team IDs and
  display names, score, period scores, and public recap;
- nullable, provenance-preserving player fields for minutes, 2PM/2PA, 3PM/3PA,
  FTM/FTA, offensive/defensive rebounds, assists, steals, blocks, turnovers,
  fouls, and points;
- division/season scope, published standings order/rank state and policy label,
  leaderboard qualification label, team IDs, player IDs, and field-level public
  identity decisions.

When D activates the official-stat v2 publication contract, E's Firestore
compatibility repository must be replaced by the bounded HTTP projection client
specified in `docs/planning/official-stat-contract.md`. HTTP `409`, `410`, and
`404` must map to stale, retracted, and unavailable/private UI states without a
private-model fallback. Do not reinterpret E's compatibility snapshot hash as a
v2 `releaseId` or legacy `approved` as certification.

There is also a deliberate compatibility gate in the current branch:
`firestore.rules` only permits public snapshot reads when
`certificationStatus == 'certified'` and `published == true`. E's dormant
projector emits `compatibilityCandidate`, and a retracted snapshot emits
`published == false`. Therefore the revised projector must not be deployed by
itself: clients would receive a denied/unavailable read, and they could not
distinguish a retraction. D/I must either keep the existing projector dormant
until the v2 HTTP `404`/`409`/`410` transport lands, or review and atomically
publish an explicit compatibility rule/status contract. Do not restore the
`certified` label merely to satisfy the old rule, and do not loosen the public
rule to any private source collection.

## Request to I: integration and cutover

- Merge E after A's route patch and D's adapter decision, resolving only the
  published interfaces above.
- Mount every public destination through canonical `PublicRoutePaths`; do not
  preserve E's temporary local `Navigator` destinations as the route contract.
- Replace every E-side `DateTime.toLocal()` display/day-boundary calculation
  with the accepted Stage 1 `LeagueTime` Jamaica-zone utility. This branch did
  not duplicate that later baseline implementation.
- Treat rules, the v2 manifest/page reader, the current-pointer check, and the
  server-owned source-token writer as one atomic cutover. Do not expose an
  immutable release page directly; reads must be authorized through the exact
  current pointer, release digest, state, and privacy epoch.
- During that cutover, replace the active legacy repository/provider with
  `DormantVersionedPublicReleaseRepository`; do not leave both transports live
  or silently fall back from a failed v2 integrity check to the legacy document.
- Keep the app and `public_functions` compatibility update in one candidate so
  artifact creation is not enabled against an unversioned live snapshot.
- Add the accepted public projection path to the I-owned shared
  `FirestorePaths` constants and switch E's read-only repository to that helper
  during integration. This branch keeps the exact legacy path local rather than
  editing a shared root concurrently.
- Run public Functions tests, Flutter model/widget/export/share tests, the frozen
  security/account-deletion suite, optimized web build, and unauthenticated
  browser URL refresh/Back checks.
- At cutover, add a Firebase Emulator Suite integration test that runs two
  contending rebuilds while the trusted source transaction changes publication
  state/version, and an identical immutable batch-create retry. This branch
  unit-tests the exact source/pointer guards and immutable-document replay
  predicate, but cannot honestly exercise rules or transaction contention
  while the trigger, trusted writer, and v2 rules are intentionally absent.
- Do not add a trigger around `rebuildVersionedPublicRelease`, rebuild a live
  snapshot, migrate data, or activate v2 as part of merging this branch. Those
  remain separate provider-readback and release gates.
- Update the isolated QA seed through I so synthetic player/leader rows use the
  explicit `publicDisplayName`/`publicPlayerLines` allowlist. E intentionally
  removed the legacy `name` and `playerLines` privacy fallbacks, so the current
  Stage 1 seed's public-snapshot wait condition will otherwise fail.
- Seed an explicit `publicLeagueState: published` and a nonnegative
  `publicPrivacyEpoch` only in the isolated QA project. Missing or unrecognized
  publication state now fails closed as unavailable, and missing privacy epoch
  suppresses every player-identity row.

## Remaining acceptance dependencies

- Canonical `PublicRoutePaths` mounting and canonical URLs.
- D's actual accepted revision/publication transport and complete stat fields.
- I's atomic public-rule, source-token writer, manifest/page reader, pointer
  authorization, and explicit-public-field QA fixture.
- The approved standings/qualification policy.
- The player/guardian field-level publication policy and privacy-epoch source.
- Platform browser/device checks for share permission denial, image/text
  fallback, download behavior, refresh, Back, and stale/retracted responses.
