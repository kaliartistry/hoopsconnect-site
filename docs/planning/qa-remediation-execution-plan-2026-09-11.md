# HoopsConnect QA remediation and execution plan

Status: implementation in progress. Stage 0 is integrated and independently reviewed; Stage 1 dispatch follows the accepted Stage 0 platform, interface, and statistics contracts.

Prepared: 11 September 2026.

## 1. Outcome and verified starting point

Deliver a complete, coherent Jamaica Basketball Association app: people can reach the work their role permits, finish it with clear feedback, trust the scores and dates, and use the interface comfortably on a phone or a large screen. Include the account lifecycle and courtside recovery work needed to make those promises reliable.

Keep the existing Flutter application for iOS, Android, and the admin/statistician PWA. Preserve the successful acknowledgment interaction, media credential/share-card design, and responsive desktop shell while improving their incomplete paths.

Verified during this planning pass:

- Workspace: `/Users/kaliartistry-mac/Jamaica Basketball App`.
- Local `main` and GitHub `main` both point to `ccc53eace3d8b08b49400a033952db7f882f0fae`.
- Working tree was clean before this plan was added. GitHub had no open PRs.
- Several older worktrees exist. Their presence does not authorize reusing or deleting them; new work starts from an explicitly recorded integration commit.
- Source audit: [HoopsConnect QA Run](https://claude.ai/code/artifact/fda8d11d-c797-4b44-bfe1-2da9c19b87a5), including the completed admin follow-up.
- The local audit HTML inspected for this plan has SHA-256 `a099df5dc1da2445619c12cdaf9e0903f491f6d696323911b4014150a1302ee8`. Its F-01 through F-26 identifiers are retained below for traceability.
- The audit exercised synthetic data with Auth and Firestore emulators. It did not exercise Cloud Functions, successful invite redemption, real push delivery, physical devices, screen readers, or poor-network recovery. Its hosted-header test was local reproduction, not a readback of the live deployment.

This plan covers every audit finding and the important omissions. A finding can close as fixed, disproved with evidence, or superseded by a verified implementation. An untested feature cannot close as passed.

## 2. Corrections before coding

The audit is an input to implementation, not an instruction to apply every suggested fix literally.

| Audit claim or recommendation | Execution decision |
| --- | --- |
| F-01 says the deployed PWA is blank | Treat the exact-header local reproduction as strong evidence of a build/Hosting mismatch. Reproduce with the recorded production build command; verify the live URL separately before describing its current state. |
| F-16 suggests allowing a game to start with fewer than five players | Do not add a universal override. FIBA 2024 Article 9.3 requires five ready players per team at the start. Show the missing-starter count and a roster repair path; support other formats only through the adopted competition rules. Starting a game and continuing after an injury/disqualification are different cases. |
| F-12 assumes Jamaica has adopted a particular FIBA edition | The existing official-stat activation fixture explicitly says adoption is unresolved. Use a named, versioned rules profile; obtain the actual NBL edition and exceptions before activation. Do not pick rules based on today's date. |
| F-06/F-17 infer missing accessibility from DOM counts and no custom Semantics widgets | Flutter web semantics are opt-in and standard widgets supply semantics. Reproduce keyboard behavior through Flutter focus, activate semantics, and test a screen reader. The missing password-submit handler is visible in source; replacing all standard buttons with custom controls is not justified. |
| F-15 treats 7-3 ranking above 13-8 as necessarily wrong | That ordering is correct under winning percentage. The actual defects are missing division scope and an unstated ranking/qualification policy. Adopt the competition's policy rather than inventing tie-breakers. |
| The admin follow-up says Divisions has no Delete path | Current `division_management_screen.dart` has a popup with Edit and Delete and a confirmation dialog. Re-test discovery and reference safety; do not create a second deletion implementation. |
| F-22 observes a callable failure with Functions absent | The uncaught UI error is confirmed in source. The failed test is not evidence that the production callable is broken or that the server accepts nonexistent teams. Test both creation and redemption against the Functions emulator. |
| F-04/F-11 propose filling new statistics into all old games | Missing shooting detail cannot be reconstructed from points. Preserve unknown values and provenance; never backfill made/attempted shots with invented zeros. The existing v2 calculator already distinguishes played and awarded results. |
| F-13 proposes determining completion only from scheduled start time | A passed start time does not prove a game was played. Use explicit game/workflow state for final entry and review queues; retain access to upcoming-game preparation. |
| F-18 proposes permissive parser defaults everywhere | Tolerate optional display data where appropriate, but authorization, scope, official results, and canonical contracts must reject invalid data. Do not default an unknown role into a privileged role, guess a season, or silently omit data from certified totals. |

References: [FIBA 2024 rules, Articles 8 and 9](https://assets.fiba.basketball/image/upload/documents-corporate-fiba-official-rules-2024-v10a.pdf), [Flutter web accessibility](https://docs.flutter.dev/ui/accessibility/web-accessibility). The FIBA document is a reference profile, not proof of JBA adoption.

## 3. Work already present that must be reused

| Existing foundation | How it changes the implementation |
| --- | --- |
| Server-owned memberships, capability schema, transactional privileged invites | Repair UI and route checks against the existing authority model. Do not bring back client-written roles or static seed invite codes. |
| `docs/planning/official-stat-contract.md`, scoped authority, assigned-game bootstrap | Use the existing identity, scope, rules, assignment, revision, and certification boundaries for the statistics and roster work. |
| `docs/planning/normalized-box-score-calculator-v2.md`, Dart and TypeScript calculators | Connect and validate these components through a versioned integration. Do not build another independent basketball calculator in a widget. |
| `docs/planning/local-game-journal-v1.md`, SQLite and IndexedDB adapters | Complete preparation, UI, delivery/receipt, and recovery integration. Firestore pending writes are not proof that a play was safely accepted by the server. |
| Account deletion AD01 through AD05E, lifecycle, ownership, identity suppression, Storage and notification adapters | Complete the missing transport, orchestration, UI and operational evidence around the existing modules. Account deletion is not a one-button Auth delete. |
| `public_functions` and the current public snapshot | Preserve the public/private boundary. Public screens must never fall back to private repositories when public data is incomplete. Coordinate the existing snapshot with the planned versioned publication boundary. |
| Dormancy tests that hash production files and check import graphs | Plan a reviewed transition before changing pinned roots. Preserve the intent of each dormant boundary until its integration is deliberately approved and tested. |

Required implementation references include `AGENTS.md`, `docs/CODEX_HANDOFF.md`, `docs/production-foundation-contract.md`, `docs/stat-migration-inventory.md`, `docs/planning/official-stat-account-deletion-addendum.md`, and `docs/account-deletion-release-gates.md`. Some older prose describes past deployment status; verify the provider rather than interpreting a document date as current state.

## 4. Team structure and ownership

Use both persistent tasks and scoped subagents. Persistent tasks retain each workstream's decisions and evidence. Subagents may handle bounded tests or reviews within that workstream, with explicit file ownership. Start with one integration owner and at most three active workers. Queue the remaining tasks until dependencies and file ownership permit them to run.

| ID | Proposed task | Owns the outcome |
| --- | --- | --- |
| I | HoopsConnect integration and acceptance | Baseline, shared contracts, sequencing, shared-file integration, issue ledger, assembled candidate, release preparation |
| A | HoopsConnect platform and account access | Reliable startup/PWA, safe test environment, role navigation, sign-in/recovery, invitations and account access |
| B | HoopsConnect interface and accessibility | Shared visual system, form/feedback patterns, focus and screen-reader behavior, responsive consistency, final visual review |
| C | HoopsConnect league operations | Teams/rosters, rep responsibilities, divisions, schedule/generator, timezone, board/acknowledgments, branding and season management |
| D | HoopsConnect statistics and game recovery | Rules-aware scoring, complete statistics, review/revision, authority, immutable results, aggregation and durable courtside recovery |
| E | HoopsConnect fan and media experience | Guest detail pages, standings/leaders, press workflows, share/download/export, public data consumption |
| F | HoopsConnect account lifecycle | In-app deletion, provider reauthentication/revocation, ownership handoff, cleanup, privacy and lifecycle integration |
| Q | HoopsConnect independent release QA | Independent reproduction, combined-build workflow/visual testing, regression evidence and final disposition |

### File ownership rules

- A owns `lib/app/`, the auth feature, `auth_providers.dart`, `user_model.dart`, `membership_model.dart`, the auth/invite repositories, and admin user/invite screens. It owns profile/settings during its first pass; F receives those files explicitly later.
- B initially owns `lib/core/theme/`, common visual constants, shared widgets and `error_mapper.dart`. B supplies examples and screenshots for other owners to apply. It does not concurrently restyle their screens. A final screen-polish pass happens only after a recorded ownership handoff.
- C owns the remaining admin screens, `features/team/`, `features/board/`, `features/ack/`, `features/calendar/`, related repositories/providers/models, and a shared league-time formatter. `admin_panel_screen.dart` has staged ownership: A fixes its capability menu first, then C handles season/layout behavior.
- D owns stat entry/live-game screens and their widgets/notifiers/providers, stats repositories, official-stat contracts/calculators/journal and new statistics runtime modules. E owns the display screens: box score, standings, leaderboard and player card, consuming D's agreed interfaces.
- E owns `features/public/`, `features/press/`, the four statistics display screens, public model/provider, sharing and export code, and `public_functions/`.
- F owns the account-deletion and lifecycle modules and a new deletion feature. Auth roots, profile/settings and notification wiring are integrated only after explicit handoff from A/C.
- I is the single merger for `functions/src/index.ts`, live Firestore/Storage rules, indexes, Firebase/deployment configuration, CI, dependency manifests/locks, shared path constants, activation fixtures and dormancy-pin updates. Workers provide reviewed patch requests for those shared files instead of racing to edit them.
- Q owns new acceptance scenarios and evidence. Q reports defects to the responsible writer; it does not independently rewrite the same feature while that writer is active.
- Every new shared DTO, route, callable, enum or repository method needs an owner and compatibility contract before another worker consumes it. I records that contract in the dispatch brief.

Each implementation task gets its own Git worktree and `codex/qa-<workstream>-<packet>` branch. Use new checkouts from a recorded accepted commit; do not blindly resume the old worktrees. Do not put two writing agents in the saved checkout or the same worktree. One worker per emulator dataset/port set, or serialize tests through I's test environment.

## 5. Execution order

| Stage | Active work | Completion gate |
| --- | --- | --- |
| 0. Establish a usable common base | I coordinates; A builds the reproducible environment; B establishes UI patterns; D inventories and reconciles existing stat contracts | Baseline tests recorded, reliable emulators, shared interfaces/file boundaries agreed, audit corrections logged |
| 1. Restore core workflows | A completes access/navigation; C builds league/communication workflows; D builds statistics commands and review integrity | Users reach authorized work; key actions show honest state; the stat workflow validates and survives retry |
| 2. Complete connected features | D completes live/offline integration; E finishes public/media experience; F completes lifecycle integration | Full game-to-result journey, consistent exports/public views, recovery and deletion scenarios pass in isolated environments |
| 3. Finish visual and independent QA | B performs the integrated visual/accessibility pass; Q drives all journeys; one author fixes reported defects at a time | All findings have evidence-backed disposition and the combined candidate passes required checks |
| 4. Rehearse release and deliver | I coordinates Q and the relevant owner | Staging migration/restore and provider checks complete; exact builds/configuration ready for the release decision |

Stages are dependency gates, not a promise that every task takes the same amount of time. D and F are the substantial integration paths. Re-estimate after Stage 0 identifies reusable components and remaining activation work. Do not use the audit's individual hour estimates as a delivery promise.

UI is part of each stage: feature owners apply B's patterns and submit before/after screenshots with their behavior changes. Stage 3 catches cross-feature inconsistency rather than starting interface work at the end.

## 6. Work packets and acceptance criteria

### A. Platform, navigation and account access

1. Add repeatable development/QA configuration for Auth, Firestore, Functions, Storage and the public codebase. Install locked dependencies in the implementation environment. Use explicit synthetic project IDs and loopback endpoints. Fail if any client/callable targets production; stub FCM and external delivery in local tests. Include useful full-season fixtures and minimal empty fixtures for every role.
2. Reproduce the web boot failure under Hosting headers. Prefer bundled renderer/fonts where supported by the pinned Flutter toolchain. Validate CSP against renderer, fonts, OAuth, App Check, Functions, Storage and WebSockets without broadly permitting all origins. Add an actual browser boot smoke test, plus manifest/install, cache-version and update behavior tests. Keep private results out of persistent public caches.
3. Use a shared route/capability map for navigation and guards. Land fans on a visible destination; preserve a permitted requested deep link after sign-in. Make stat entry/revision reachable for authorized statisticians. Test manual URLs, old notification URLs, refresh and browser Back. Guard mutations with real authority even during role preview.
4. Gate each admin menu item on its actual capability. Keep denial/recovery copy understandable. Add role preview to all supported layouts; clearly mark preview as a display aid, not delegated authority.
5. Add password recovery and account settings access to it, generic authentication errors, a working Return-to-submit path and sensible keyboard traversal. Clear corrected validation errors; constrain desktop form width and preserve email input after failure. Exercise email, Google and Apple entry paths where provider configuration permits.
6. Repair invite creation/loading/errors and replace raw team ID entry with a scoped picker. Preserve the existing operation ID across retries; distinguish invite creation success from clipboard failure. Provide the newly issued secret once in an explicit success surface, with retryable Copy and an explanation that it will not be recoverable later. Test create, inspect, redeem, expire, revoke, duplicate tap, lost response and cross-association rejection with real local callables.
7. Test actual role-change confirmation, success/failure, owner protection and stale permissions. Show one user-facing Media role while continuing to read the historical `press` alias. Do not silently change existing membership wire values.

Acceptance: a role/route matrix for guest, fan, rep, statistician, media, legacy press, admin and superAdmin; real keyboard sign-in; successful local invite redemption; visible retryable failures; protected destinations reject unauthorized direct access; PWA boots under its intended headers.

### B. Interface, accessibility and presentation

1. Establish semantic colors for light/dark/high-contrast states. Keep JBA green/gold identity, and reserve urgency/status colors for meaning. Fix the invisible login heading, legal/link contrast, hardcoded white surfaces, navy/orange outliers and theme leakage.
2. Define shared form, loading, success, recoverable error, empty state, confirmation and table patterns using standard Flutter controls where practical. A disabled primary action explains what is missing; a pending action cannot be duplicated; failed actions retain input. Do not replace working framework semantics with unnecessary custom controls.
3. Verify focus order, visible focus, Enter/Space activation, Escape/cancel and focus restoration. Activate web semantics before evaluating the tree, then use VoiceOver and TalkBack in platform QA. Add explicit names/roles where custom controls need them; ensure target size and contrast are adequate, including role/status chips and live-stat controls.
4. Constrain single-column desktop content and keep row labels near controls. Keep useful navigation-rail and multi-pane layouts. Make standings names readable, tables usable on narrow screens, and horizontal scrolling discoverable; test text scaling and long real club names.
5. Apply coherent copy: viewer-appropriate empty states, correct plurals, one label per concept, clear counts, and primary actions named for what happens. Show installed app version/build from package metadata in About.
6. Evaluate branding changes with preview, color picker/swatches, contrast guidance and logo preview/error handling. Coordinate any actual media-upload implementation with C/F's Storage and privacy boundary; do not add a broad file upload feature merely to replace a URL field.

Acceptance: reviewed screenshots at 375, 768 and 1440 pixels, iOS/Android representative screens, light/dark modes, large text, keyboard journey and screen-reader results. Include every changed screen and its key error/empty/disabled states. Custom controls must expose name, role, selected/disabled state, adequate target size, visible focus, Enter/Space activation and no duplicate semantics. Feature writers must satisfy the same checks before B's final consistency pass.

### C. League operations and communications

1. Add team creation/editing with division selection, stable identifiers and duplicate-name guidance. Create/edit players through a roster model with stable person/registration identity, jersey number stored as a string, and optional position. Preserve `0` versus `00` and season/game roster history; adding a roster member must not fabricate season statistics.
2. Give representatives a useful My Team entry and a clearly scoped roster workflow. Recommended product default: reps propose changes for their own team; an authorized admin approves changes affecting eligibility/official registration. Build against the existing scoped-authority/registration contracts and keep this configurable until the league confirms its process. Do not give reps general `teams.manage`.
3. Complete division validation/error feedback, display names rather than IDs, and obvious edit controls. Re-test the existing Delete action; block deletion when referenced by games/teams/results and offer an appropriate inactive/archive path. Preserve historical references.
4. Use one timezone-aware league-time service. Store instants in UTC and scheduling/display zone explicitly, defaulting new JBA configuration to `America/Jamaica`; clearly label league time. Keep date-only season boundaries as calendar dates. Test DST changes in viewer locations and cases where local time crosses midnight. Inventory old timestamps before any migration; do not shift all existing dates by an assumed hour.
5. Repair manual schedule validation, division selection, distinct teams, duplicates/conflicts and state-appropriate actions. The generator must block infeasible progression, keep truthful step status, support revisiting/editing steps, regenerate its preview after changes and show final counts/scope before committing. Make create/retry idempotent. Empty preview and preview cancellation write nothing.
6. Preserve the rep acknowledgment success pattern. Offer acknowledgment only to assigned people and show real pending/success/failure states. Make admin pending/acknowledged counts, timestamps and reminders useful on large screens. Test full ack expansion, retries, completion and reminder behavior with Functions; route normal refusals to the UI rather than fatal crash reporting.
7. Align Create Announcement/Post naming and actual audience. For required acknowledgment, make a deadline or an explicit no-deadline choice visible; the recommended default requires a deadline before sending. Do not imply delivery from the mere existence of a post. Show accurate publication/delivery state without exposing backend implementation terminology. Filter notification settings by role capability.
8. Make season creation a clear prepare-and-activate flow. Warn exactly when the active season pointer will change; prevent duplicate IDs from overwriting an existing season, validate dates, preserve historical results and make cancellation safe. Keep Archive confirmation clear about consequences and reversibility. Label Season Leaderboard honestly as viewing unless an actual governed management workflow is implemented.

Acceptance: create a division and team, register players, submit/approve a rep roster change, generate and edit a schedule, send/acknowledge/remind within local test delivery, and change seasons in synthetic data without broken references. Delete an unused division, block deletion of a referenced division with understandable dependency details, archive without breaking historical routes, preserve stable team/player IDs and distinguish jersey `0` from `00`. Run one timezone case that crosses midnight between Jamaica and the viewer plus a New York DST transition through schedule, calendar, stat queue, reminders, public detail, recap, share and CSV. Repeat key workflows with ordinary admin and superAdmin separately.

### D. Statistics, review and courtside recovery

1. Inventory which official-stat packets are implemented, tested and dormant versus still missing. Pin the shared scope, identity, roster, rules, bootstrap, revision, result and public DTO interfaces before C/E start their dependent writes. Keep production activation decisions separate from local candidate wiring.
2. Integrate the existing v2 normalized calculator for shooting makes/attempts, turnovers, team-only statistics, participation, periods/overtime, fouls and minutes. Use the same validation rules on client and server. Reconcile player, team, period and final scores for normal played results; preserve separate administrative outcomes, forfeits, partial/suspended games and legacy unknowns. Avoid arbitrary caps that reject legitimate performance.
3. Establish an explicit lifecycle: preparation, live capture or post-game draft, submitted, under review, changes requested, resubmitted and approved/certified under the chosen contract. Keep play state distinct from review state and delivery state. Keep future preparations out of the review queue; determine completion explicitly.
4. Make send-back/revise/resubmit atomic and visible. Bind each action to the exact revision, preserve the reason, prevent stale approvals, and use the same status for worklists, calendar, reminders and detail screens. Verify retry/idempotency and aggregation after correction/re-approval. A preliminary timestamp-only filter is not a completed fix.
5. Route the game header, team table, recap, standings, leaders, share and exports through one consistent accepted result/version. Invalid or unverified historical records must not be presented as newly certified facts. Produce a dry-run migration inventory and adapters; do not invent missing shooting splits or rewrite canonical hash contracts to make a fixture pass.
6. Improve stat entry for the actual task: readable jersey/name roster, fixed identifying columns on large screens, reliable keyboard traversal, visible validation beside the relevant cell, save/draft/submission state, and a clear primary action for each game state. Preserve entered work when switching entry mode or leaving a screen. Start eligibility follows the adopted rules and displays why a game cannot start.
7. Integrate the existing durable journal with preparation, identity/assignment, writer ownership, server command delivery, durable receipts and foreground/resume recovery. Preserve unsent or response-unknown operations through refresh, crash, network loss, sign-out and stale assignment. Show honest distinctions between saved on device, queued, accepted and needs attention. Do not promise background upload after a closed PWA.
8. Test loss before/after local commit, duplicate/out-of-order delivery, app relaunch, second-device writer conflict, assignment revocation, storage quota/unavailability and correction of accepted work. Coordinate deletion reconciliation with F so account cleanup cannot silently destroy unsubmitted official work.

Acceptance: a complete synthetic match, post-game-only match, overtime, legitimate exceptional result, rejection/revision, corrected result and interrupted/recovered game. A named revision trace submits N, requests changes against N, rejects a stale approval, resubmits N+1, approves exactly N+1 and proves calendar, worklists, box score, standings, leaders, public detail, text/image share and CSV all expose N+1 once without duplicate aggregation. Courtside keyboard tests cover Tab/Shift-Tab, Escape, focus restoration, shortcuts while text fields/dialogs are focused, rebuild/caret preservation and leaving/re-entering without data loss. Scores and totals agree across every consumer. Replays do not double count, unauthorized writers fail, and accepted work survives failure. Existing Dart/Node/canonical/optimized-web/journal conformance stays green.

### E. Fans, guests, media and public data

1. Make guest Games, Standings and Leaders useful journeys with game, team and player detail destinations, browser Back/refresh and shareable URLs. Coordinate new routes with A. Keep the login-screen guest entry easy to find.
2. Publish and consume division/season scope through the permitted public boundary. Preserve privacy and publication status. Use shared presentation patterns with signed-in views without reusing their private data readers. If the accepted v2 contract requires HTTP projections, implement that boundary rather than exposing private Firestore models to save time.
3. Default category ordering to the product's agreed basketball vocabulary, including PTS first. Show games played, adopted qualification criteria, unresolved/tied ranks and readable team names. Add clear unavailable/loading/error states; do not use alphabetical order as a sporting tie-breaker.
4. Complete the media path from result discovery to box score, recap, share/download and per-game/per-season CSV. Keep all outputs on one result/publication version. Feature-detect sharing and provide explicit Copy/Download alternatives with honest success/failure; test permission denial and image/text fallback on each platform. Preserve the existing strong branded card design.
5. Include complete available shooting/turnover fields from D, show unknown historical fields honestly, escape spreadsheet-formula prefixes in CSV text, and enforce export capabilities and field-level privacy. A downloaded image/export must not claim a newer publication than its source.

Acceptance: first agree one public route namespace with A. Open every game/team/player public URL in a fresh unauthenticated browser, refresh, use Back and verify only public repositories/projections are touched. An unauthenticated user finds a result and shares its URL; a journalist can produce consistent text/image/CSV on desktop and phone; filtering, pagination, reload, stale/retracted release and privacy-denied cases behave correctly. Share acceptance covers image success, image-fail/text-success, both-fail, copy failure, cancel, unsupported platform and duplicate taps without false success. No public route can read internal posts, acknowledgments, user records or restricted identity fields.

### F. Account lifecycle, privacy and ownership

1. Reconcile the existing AD modules and their unresolved adapters against the source inventory. Complete missing candidate entrypoints, lifecycle authority, worker orchestration, provider handling and UI without reimplementing the contracts.
2. Add a clear account-deletion flow with appropriate reauthentication, consequences, progress and truthful completion/failure. Cover email, Google and Apple accounts, provider cancellation, retry and session/cache/listener/notification cleanup. Apple requires account-creation apps to let users initiate deletion in the app: [Apple account-deletion guidance](https://developer.apple.com/support/offering-account-deletion-in-your-app/).
3. Handle sole-owner custody/transfer, suspended or missing profiles, old sessions, repeat requests, cross-device local journals, retained official records and player identity/privacy separately. Do not equate deleting an account with erasing an athlete's official sporting history or invent retention authority.
4. Test fencing before provider mutation, durable cleanup tracking, failed/retried adapters, unknown provider responses, verified Auth absence and remaining cleanup, publication/export suppression, backup restore and stale client denial.
5. Produce the concrete evidence and policy decision packet for the existing G1-G11 gates. Engineering can prepare and test the candidate while retention/controller/guardian/provider/custody decisions are resolved. Only mark a gate passed when its owner and evidence exist; never silently toggle activation flags to satisfy a test.

Acceptance: first agree one lifecycle route contract with A. Prove deletion remains reachable for active, blocked/suspended, provider-cancelled, deleting and cleanup-pending accounts without a sign-in/deletion redirect loop. The local lifecycle scenario matrix passes, production integration is reviewable, and each release gate has an explicit status and evidence. Public activation waits for the actual required decisions and provider/staging proof. The feature is not called complete merely because a Delete button is visible.

## 7. Audit-to-workstream ledger

All entries start `planned`. I changes status to `reproduced`, `implemented`, `verified`, `disproved` or `blocked-decision`, with commit and evidence links. Split F-03, F-17, F-19 and F-25 into per-action checks when dispatched.

| ID | Fix or verification target | Primary owner | Required proof |
| --- | --- | --- | --- |
| F-01 | Web boot / Hosting CSP | A | Built app renders under intended headers; fresh/update boot |
| F-02 | Statistician post-game route | A | Actual statistician reaches assigned entry and revision; other users denied |
| F-03 | Ack, share and role-change feedback | C / E / A | Success, refusal, unavailable backend/platform and retry per action |
| F-04 | Contradictory scores / invalid final result | D | Normal result reconciles; exceptional outcomes explicit; all outputs consistent |
| F-05 | League time/date semantics | C | Same instant in Jamaica and viewer zones; correct date entry/filtering |
| F-06 | Keyboard sign-in | A + B | Real keyboard journey and submit handler; no DOM-count shortcut |
| F-07 | Fan landing and nav selection | A | First login, reload, deep link and tab selection agree |
| F-08 | Password recovery / auth wording | A | Recovery success/failure and provider-aware guidance |
| F-09 | Rep roster responsibilities | C | Own-team proposal/approval, unrelated team denied |
| F-10 | Admin per-tool capability checks | A | Ordinary admin and superAdmin compared with server authority |
| F-11 | Shooting and turnover statistics | D, consumed by E | Client/server agreement; new fields visible; missing historical fields unknown |
| F-12 | Rules-aware duration and validation | D | Adopted profile, overtime, time precision and exception scenarios |
| F-13 | Needs-stats queue | D | Prepared future games distinct from completed/reviewable games |
| F-14 | Rejection/revision state and reminders | D + C | Submit, reject, remind, revise, approve end to end without double aggregation |
| F-15 | Public discovery, scope and ranks | E | Guest drill-through, division filters, adopted ranking rules, direct URLs |
| F-16 | Live-stat identity and start guidance | D + B | JBA theme, explained start prerequisites, correct playing-rule behavior |
| F-17 | Semantics and navigable detail routes | B + A | Semantics enabled, screen-reader journey, refresh/Back/direct URL |
| F-18 | Malformed data and consistent error states | Domain owners + B | Recoverable display failure; authority/results remain closed on invalid data |
| F-19 | Role-aware copy/options | A / B / C | Media alias compatible, role-appropriate prefs/empty states, consistent labels |
| F-20 | Real app version/build | A | About matches installed package metadata |
| F-21 | Dark theme contrast | B, applied by each owner | All touched screens and main journeys reviewed in both themes |
| F-22 | Invite UX and real callable integration | A | One issuance on retries, team picker, visible errors, successful redemption |
| F-23 | Teams/player registration | C, contract coordinated with D | Team creation; stable identities; jersey/position; no fake aggregate records |
| F-24 | Generator progression and editability | C | Impossible setup blocked; changed step invalidates preview; retries safe |
| F-25 | Admin labels, ack deadline, season consequences | C | Labels match outcomes; explicit deadline policy and season activation warning |
| F-26 | Desktop role preview | A | All widths, clear preview state, no extra mutation authority |
| X-01 | Full account deletion | F | Existing release gates plus complete lifecycle/provider/privacy scenarios |
| X-02 | Courtside offline recovery | D | Restart/network/receipt/conflict/storage tests and visible recovery |
| X-03 | Functions and authorization gaps in audit | A / C / D / Q | Real local callables, rules, aggregation and simulated delivery |
| X-04 | Integrated visual coverage | B + Q | All roles, changed screens, responsive sizes, text scaling and error states |
| X-05 | Staging, migration and release rehearsal | I + Q | Exact candidate/version, dry run, restore proof and provider readback |

## 8. Definition of done and integration controls

Each PR contains a bounded outcome, owned paths, linked finding IDs, before/after behavior, proportionate tests, rendered evidence and known limitations. Documentation-only assertions or a passing unit-test count are insufficient for workflow completion.

The integration owner:

1. Pins the starting commit and captures a baseline before dispatch. Records existing worktree state and owner without changing other work.
2. Creates a transition record for pinned/dormant surfaces. For an ordinary root change, retain candidate-exclusion/import-graph assertions and update only reviewed baseline pins. For actual candidate integration, replace the applicable dormancy requirement with explicit activation/integration proof. Never delete a failing guard or regenerate every expected hash indiscriminately.
3. Integrates one tested packet at a time; workers start dependent work from the new accepted commit. Only I updates shared roots, resolves overlapping contracts and assembles release branches. GitHub PR/CI requirements continue to apply.
4. Runs the existing repository-safety, authorization/rules/callable, Dart, browser wire-contract, optimized Dart2JS, Unicode and journal tests when affected. Preserve the pinned tools and lockfiles unless a reviewed dependency change is needed.
5. Adds `public_functions` tests to integration validation and CI, since the current workflow installs/builds the default Functions package but does not test that separate public package.
6. Builds release web plus representative native candidates and has Q drive the assembled version. Test target/port identity and delivery stubs are checked before any scenario writes.
7. Keeps a live findings ledger. Every original F ID remains traceable, including a correction/disproof; newly discovered regressions get their own entries. Q verifies fixes on the integrated commit, not only the author's branch.

Core verification commands, run in the designated implementation/test checkout:

```text
npm --prefix scripts test
node scripts/check_repository_safety.js
node scripts/run_security_emulators.js
flutter analyze --no-pub --no-fatal-infos
flutter test --no-pub
npm --prefix functions run build
npm --prefix public_functions test
flutter build web --release --no-pub [the reviewed web build configuration]
```

The existing CI also runs individual Chrome wire/journal tests, optimized Dart2JS conformance and Unicode checks. Retain those actual commands from `.github/workflows/ci.yml`; the list above does not replace them. Install locked dependencies explicitly before using `--no-pub`.

### Independent acceptance journeys

- New/returning account: sign-up/provision, email/Google/Apple sign-in as supported, invalid credentials, recovery, invite redemption, blocked membership and sign-out.
- Guest/fan: find today's game, open a result/team/player, change division, compare standings, share and refresh a direct link.
- Rep: review an announcement, acknowledge once, see completion, propose a roster change and see its outcome.
- Statistician: prepare roster, run candidate-profile scenarios while the adopted-rule decision remains open, record/edit play, lose connection, restart, recover, submit, receive changes requested and resubmit. Keep F-12 `blocked-decision` until JBA records the adopted profile.
- Admin: see permitted tools, review discrepancies, request changes, approve the exact revision, and verify updated standings/leaders without duplicates.
- Media and historical press alias: find result, inspect complete stats, copy/download/share/export consistent output.
- SuperAdmin: manage users/invites/teams/divisions/schedule/branding, preview roles, and prepare/activate/archive a season with clear consequences.
- Account lifecycle: exercise the appropriate deletion scenarios for every account/ownership state, including old devices and local stat work, but keep production activation blocked until G1-G11 have real owners and evidence.

Run key journeys on iOS and Android, desktop Chrome, iOS Safari/PWA where supported, and phone/tablet widths. Include dark mode, larger text, keyboard, screen readers, empty season, partial data, denied permission, unavailable Functions, slow/offline network and duplicate/retried actions. Record any unavailable physical-device evidence instead of declaring it tested.

## 9. Decisions and release boundaries

The following decisions should be prepared during implementation, so they do not become surprises after coding. They do not block unrelated UI/access work.

| Decision | Proposed engineering position | Needed before |
| --- | --- | --- |
| Adopted NBL rules, overtime, standings/qualification/ties and exceptional results | Versioned explicit rules; no automatic latest-edition switch | Official-stat and public-ranking activation |
| Representative roster authority | Own-team proposals with admin approval for registration/eligibility changes | Activating rep mutation workflow |
| Player/guardian publication authority and retention/controller decisions | Unknown public identity permission remains restricted; prepare concrete policy choices | Expanded individual public views and deletion activation |
| Named certifiers/custodians and sole-owner recovery | Preserve separation of duties and recoverable ownership | Certification/deletion activation |
| Historical data treatment | Retain source, dry-run classification and mappings; unknown is not zero | Data migration/publication cutover |
| Production target, release order, provider configuration, backups and restore | Rehearse on isolated staging with exact build/configuration | Remote migration, deployment and store release |

These are already explicit concerns in `contracts/official_stats/v2/activation_gates.json` and the account-deletion release gates. No blanket permission question is needed to write and test the implementation candidate. Actual activation still needs its recorded policy/operational evidence and the user's release instruction.

The final release package identifies the exact commit, native build numbers, web assets, schema/configuration changes, migration manifest, test evidence, unresolved decisions and recovery procedure. Deploy ordering must follow the actual compatibility plan; a stale generic rules-first instruction must not be applied when compatible clients/Functions must land before tighter rules.

Do not erase old records or reopen unsafe legacy access to roll back. Preserve accepted journals/revisions and use the existing restore/replay strategy. No production seed, reset, notification campaign, migration or store publication is part of preparing this plan.

## 10. Dispatch briefs

When implementation is requested, create the stage-appropriate tasks with the brief below plus that task's packet from section 6. Do not launch all tasks immediately.

> Implement only workstream [ID] and packet [number] from `docs/planning/qa-remediation-execution-plan-2026-09-11.md` at integration commit [full SHA]. First verify your worktree, branch, baseline status, applicable instructions and predecessor contracts. You own [explicit files]. Shared roots listed in section 4 belong to I; propose changes there for integration rather than editing them concurrently. Reproduce your finding on the baseline, implement the smallest complete solution consistent with the approved contracts, and test the user journey including its error/retry state. Reuse the agreed UI patterns and attach rendered before/after evidence. Preserve unknown historical facts, tenant/capability boundaries and dormant modules outside your packet. Return the commit/patch, findings closed, changed paths, exact tests/evidence, compatibility notes and next dependency. Do not deploy or change real league data.

Q receives a different brief:

> Independently verify integrated commit [full SHA] against the findings ledger and acceptance journeys in this plan. Use real UI interaction and the complete isolated test backend. Verify the specific fix, relevant adjacent workflows, role denials, persistence and rendered states. Distinguish implementation failure, fixture error and unavailable infrastructure. Return reproducible findings with role/platform/state, expected/observed result, severity, evidence and responsible workstream. Close findings only with evidence on the integrated commit. Do not change production or independently rewrite files another worker owns.

The first dispatch is Stage 0. Its output is the reproducible base and reviewed contracts that make the three-worker implementation stages safe to start.

## 11. Execution ledger

- Baseline: `ccc53eace3d8b08b49400a033952db7f882f0fae` on `main`, clean when planning began.
- Integration: `codex/qa-remediation-integration`, planning commits `9164169b112a62338cfa2e94e08ccaded2dc4fa3` and `e8d3169`.
- Stage 0 A: platform/test/web boot integrated through `a803b11`; its full isolated emulator and browser run passed with Node 22.22.2, Java 21.0.3, Flutter 3.41.2, Dart 3.11.0, and Firebase CLI 15.8.0.
- Stage 0 B: shared interface/accessibility/login patterns integrated through `2ad0198`; integration-owner branded theme wiring landed in `b2a6f7b`.
- Stage 0 D: dormant statistics migration adapter/contracts integrated through `f6f8a67`; candidate activation remains deliberately off.
- Stage 0 shared integration: CSP, CI, public Functions coverage, exact dormancy-pin transition, and path-safe delivery isolation validated on the assembled branch before commit.
- Safety state: all 50 dormancy tests passed before and after the reviewed root transition. Production activation flags, deploy roots and real Firebase data remain unchanged.

Stage 0 integration gates are: the public route contract before A/E, lifecycle route contract before A/F, official result/revision contract before C/D/E, shared accessibility harness before broad feature UI work, and one-at-a-time use of fixed local emulator ports.
