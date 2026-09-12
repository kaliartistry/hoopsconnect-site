# HoopsConnect independent QA acceptance ledger

Owner: Workstream Q

Prepared: 11 September 2026

Status: integrated local candidate accepted for continued release-gate evaluation; no production, deployment, migration, merge, or store action authorized

## Acceptance source and checkpoint

- Remediation plan: `docs/planning/qa-remediation-execution-plan-2026-09-11.md`.
- Claude source audit: `HoopsConnect QA Run`, artifact
  `fda8d11d-c797-4b44-bfe1-2da9c19b87a5`.
- Independently matched local audit SHA-256:
  `a099df5dc1da2445619c12cdaf9e0903f491f6d696323911b4014150a1302ee8`.
- Stage 0 implementation checkpoint:
  `6e74ba13faf316da2c506c2cafcfca985dd774cc`.
- Integrated code candidate checkpoint: `7fdf4b0` on
  `codex/qa-remediation-integration`.
- Synthetic target: `demo-hoopsconnect-stage0-platform` through
  `lib/main_qa.dart` and loopback emulators only.

The Claude audit is evidence of the original failures, not the acceptance
oracle. Where its literal recommendation conflicts with the remediation plan,
the plan controls. In particular:

- F-12 uses an explicit versioned candidate profile until JBA records its
  adopted NBL rules and exceptions. The current date does not select a ruleset.
- F-13 uses explicit play/review state. A passed start time does not prove a
  game was played.
- F-15 treats winning percentage as a valid ordering. Division scope,
  qualification and tie policy are the unresolved requirements.
- F-16 requires the adopted number of ready starters and an explained repair
  path. It does not add a universal under-five start override. Starting and
  continuing after an injury or disqualification are separate cases.
- F-17 enables Flutter semantics and uses keyboard plus VoiceOver/TalkBack
  evidence. DOM focus counts and absence of custom `Semantics` widgets are not
  enough to pass or fail the finding.
- F-18 may tolerate optional display data, but authorization, scope, canonical
  results and publication still fail closed.
- F-11 never invents shooting detail or zeroes for legacy records.
- Division deletion is re-tested for discovery and reference safety; the
  existing action is not duplicated.

## Stage 0 independent readback

The following checks were run without production credentials, production data,
deployment or external delivery:

| Check | Result | Evidence boundary |
| --- | --- | --- |
| Exact audit artifact | Pass | Local artifact hash matched the plan's recorded SHA-256 |
| Stage 0 source checkpoint | Pass | `HEAD` initially resolved to the full Stage 0 SHA above |
| Static platform/safety suite | Pass, 18/18 | CSP, target isolation, role fixtures, delivery guard, Hosting config and toolchain diagnostics |
| Shared UI/login focused suite | Pass, 26/26 | Widget semantics, Return-to-submit, pending de-duplication, themes, large text and QA environment configuration |
| Complete isolated Stage 0 run | Pass | Fixture, web boot and delivery-guard markers all emitted; both Functions codebases loaded; emulators stopped cleanly |

The complete run used the already-installed Android Studio Java 21 runtime via
`HOOPSCONNECT_QA_JAVA`; the default shell Java is 26 and is intentionally
rejected. Locked dependencies were installed from the existing lockfiles before
the run. The pinned runner selected Node 22.22.2, Java 21.0.3, Flutter 3.41.2,
Dart 3.11.0 and Firebase CLI 15.8.0.

Successful markers:

```text
HOOPSCONNECT_QA_FIXTURES_OK users=14 teams=4 players=24 publicGames=6 leaderboards=5 callable=true storage=true password=LocalQa-Only-42!
HOOPSCONNECT_WEB_BOOT_OK fresh=true update=true newDocument=true staleWorkerRemoved=true
HOOPSCONNECT_QA_DELIVERY_GUARD_OK codebases=default,public
```

This accepts the Stage 0 platform as the base for later checkpoint testing. It
does not claim that live Hosting, social-provider flows, physical devices,
screen readers, poor-network recovery or any Stage 1/2 feature is verified.

## Integrated candidate readback

The integration owner and independent packet reviewers subsequently assembled
and exercised the candidate through `7fdf4b0`. No production credentials,
production data, deployment, external delivery, live activation, migration, or
store action was used.

| Check | Result | Evidence boundary |
| --- | --- | --- |
| Flutter test suite | Pass: 926 passed, 16 intentionally skipped | Complete repository suite; skips are the documented activation/provider cases |
| Security emulator gate | Pass | Contracts, Functions, notifications, callables, Firestore Rules, Storage Rules, and dormant account-lifecycle suites ran against the isolated demo project |
| Public Functions suite | Pass: 23/23 | Version-bound public output and private-data separation remain enforced |
| CSP and QA fixture regression suite | Pass: 13/13 | Exact font origin, isolated Hosting headers, certified synthetic legacy projection, and ranked fixture rows are covered |
| Rendered sign-in | Pass in local Chromium | Real keyboard Return submitted the form and reached the super-admin shell with no console errors or warnings |
| Rendered public journey | Pass at desktop and phone viewports | The login surface promotes guest access with the latest result and next upcoming game; games, standings, and team details use canonical `/public/...` URLs with direct load, refresh, in-app Back, and browser Back |
| Rendered admin journey | Pass at desktop and phone viewports | Branding preview/discard protection and the locked season-management surface rendered and behaved as designed |

This readback accepts the local web candidate, not the live product. Physical
iOS/Android devices, VoiceOver/TalkBack, live Firebase/App Check and identity
providers, production Hosting, poor-network recovery, and JBA policy adoption
remain explicit external gates.

## Finding ledger

`Planned` means the scenario is ready but the integrated implementation has not
been independently driven. `Partial Stage 0` means a foundation or automated
slice passed, but the complete user-facing closure proof remains open. A finding
becomes `Verified` only on a named full integrated SHA with the required
rendered, backend and persistence evidence.

| ID | Q scenario(s) | Current Q state | Closure condition |
| --- | --- | --- | --- |
| F-01 | `F01-WEB-BOOT` | Candidate pass locally: fresh/update boot and rendered Chromium load pass under exact QA/production-header CSP profiles | Read the live URL separately after deployment authorization before describing production state |
| F-02 | `F02-STATISTICIAN-ROUTES` | Planned | Assigned statistician reaches entry/revision; every unauthorized role is denied by route and backend |
| F-03 | `F03-ACK-FEEDBACK`, `F03-SHARE-FEEDBACK`, `F03-ROLE-CHANGE-FEEDBACK` | Planned, intentionally split | Success, refusal, unavailable backend/platform, lost response, duplicate action and retry for each action |
| F-04 | `F04-RESULT-INTEGRITY` | Planned | Contradictions cannot certify/publish; normal and exceptional results remain consistent everywhere |
| F-05 | `F05-LEAGUE-TIME` | Planned | Cross-midnight Jamaica/New York case and New York DST fold agree across every consumer |
| F-06 | `F06-KEYBOARD-SIGNIN` | Candidate partial: focused widgets and real Chromium Return-to-submit pass | Add visible-focus and physical assistive-technology evidence |
| F-07 | `F07-FAN-LANDING` | Candidate partial: prominent public-data-only guest preview, public routing, refresh, direct URL and Back pass locally | Complete first/returning authenticated fan and native-device journeys |
| F-08 | `F08-PASSWORD-RECOVERY` | Planned | Generic non-enumerating recovery plus provider-aware failure/retry behavior |
| F-09 | `F09-REP-ROSTER` | Planned | Own-team proposal/approval works; unrelated team and stale authority fail closed |
| F-10 | `F10-ADMIN-CAPABILITIES` | Planned | Each menu/route/mutation follows its actual capability for admin and superAdmin |
| F-11 | `F11-COMPLETE-STATS` | Planned | Client/server calculations and all consumers agree; missing historical fields remain unknown |
| F-12 | `F12-RULES-PROFILE` | Blocked-decision for activation | Candidate-profile tests pass; JBA adoption evidence names exact profile and exceptions before activation |
| F-13 | `F13-WORKLIST`, `F13-POST-GAME-ONLY-MATCH` | Planned | Preparation, live, completed, review, revision and approved states appear only in correct queues; post-game matching uses explicit state rather than elapsed time |
| F-14 | `F14-REVISION-N-NPLUS1` | Planned | N is sent back, stale approval fails, N+1 is approved and appears once in every consumer |
| F-15 | `F15-PUBLIC-DISCOVERY`, `F15-CSV-SAFETY` | Candidate partial: public direct URLs, drill-through, refresh/Back, division labels, ranked rows and public-only reads pass locally | Adopt ranking/qualification policy and complete stale/retracted plus rendered CSV coverage |
| F-16 | `F16-LIVE-START`, `F16-COURTSIDE-INTERACTION` | Planned | JBA identity, rule-correct start/continuation behavior, scoped shortcuts and durable leave/re-enter state pass |
| F-17 | `F17-ACCESSIBILITY`, `F17-DETAIL-ROUTES`, `F16-COURTSIDE-INTERACTION` | Candidate partial: keyboard submit and public detail direct URL, refresh and Back pass in Chromium | Complete dialog focus/caret, VoiceOver/TalkBack, native semantics, and courtside evidence |
| F-18 | `F18-MALFORMED-DISPLAY`, `F18-FAIL-CLOSED` | Planned | Optional display faults recover; authority/scope/result/publication faults remain closed |
| F-19 | `F19-MEDIA-ALIAS`, `F19-COPY-OPTIONS` | Planned, intentionally split | Legacy `press` remains compatible; one Media choice and role-appropriate copy/options pass |
| F-20 | `F20-VERSION-METADATA` | Planned | About matches installed package and artifact metadata on each candidate |
| F-21 | `F21-DARK-CONTRAST` | Candidate partial: theme/widget suite plus responsive custom-brand editor and preview pass | Complete all-screen dark/high-contrast and physical assistive-technology review |
| F-22 | `F22-INVITE-LIFECYCLE` | Candidate partial: one issuance across retries, once-visible secret, picker, callable errors and local redemption pass | Complete physical-platform clipboard/share and live-provider evidence |
| F-23 | `F23-LEAGUE-SETUP`, `F23-DIVISION-LIFECYCLE` | Planned | Stable team/player/registration IDs, `0`/`00`, history, no fabricated aggregates, and safe unused/referenced/archive division behavior |
| F-24 | `F24-SCHEDULE-GENERATOR`, `F24-MANUAL-SCHEDULE` | Planned | Impossible progression blocked; generated and manual scheduling enforce division, distinct-team, duplicate/conflict and idempotency rules |
| F-25 | `F25-LABELS`, `F25-ACK-DEADLINE`, `F25-SEASON-CONSEQUENCES` | Candidate partial: labels, explicit deadline state, locked season UI, callables, cancellation and exact recovery pass locally | Adopt JBA lifecycle consequences and complete authorized staging rehearsal before activation |
| F-26 | `F26-ROLE-PREVIEW` | Planned | Preview works at 375/768/1440, stays visibly marked and grants no mutation authority |
| X-01 | `X01-DELETION-ROUTES`, `X01-PROVIDERS-CUSTODY`, `X01-DISPOSITION-PRIVACY`, `X01-CLIENT-CLEANUP`, `X01-RELEASE-GATES` | Candidate contracts dormant; all G1-G11 remain closed | Lifecycle/provider/custody/27-adapter/privacy/restore plus session/listener/cache/token cleanup scenarios pass and every gate has real owner/evidence |
| X-02 | `X02-OFFLINE-RECOVERY`, `F16-COURTSIDE-INTERACTION` | Journal contract dormant | Loss/restart/receipt/conflict/quota/revocation/correction/deletion plus courtside shortcut/caret/leave-reenter cases pass with honest visible state |
| X-03 | `X03-LOCAL-BACKEND` | Candidate pass: complete isolated security emulator gate covers contracts, Functions, callables, Rules, Storage, delivery guards and dormant lifecycle modules | Repeat against the exact release checkpoint and authorized isolated staging when that gate opens |
| X-04 | `X04-VISUAL-MATRIX` | Candidate partial: the guest-preview login, public, branding, and season screens pass desktop/phone Chromium review with zero console findings | Complete every role/state at 375/768/1440 plus native and assistive-technology evidence |
| X-05 | `X05-RELEASE-REHEARSAL` | Planned for Stage 4 | Exact candidate, authorized isolated staging, dry run, restore/rollback and authoritative provider readback |

## Executable scenario catalog

The machine-readable catalog is
`scripts/qa/acceptance_scenarios.v1.json`. It contains 47 scenarios covering all
31 findings and eight ordered cross-cutting journeys:

- `role-route`
- `error-retry`
- `responsive-accessibility`
- `revision-n-nplus1`
- `public-privacy`
- `offline-recovery`
- `deletion-lifecycle`
- `staging-release`

Validate the catalog before every checkpoint:

```text
node scripts/qa/acceptance_scenarios.js validate
```

List a finding or journey:

```text
node scripts/qa/acceptance_scenarios.js list --finding F-03
node scripts/qa/acceptance_scenarios.js list --journey revision-n-nplus1
```

Generate the exact runbook for the checked-out integrated commit:

```text
node scripts/qa/acceptance_scenarios.js runbook --checkpoint HEAD --journey role-route
node scripts/qa/acceptance_scenarios.js runbook --checkpoint HEAD --scenario F14-REVISION-N-NPLUS1
```

The runbook command exits nonzero and emits no runnable body when the requested
checkpoint is not `HEAD` or the worktree is dirty. Check out the exact commit
and make the worktree clean before generating instructions.

## Execution and evidence protocol

1. Record the full integrated SHA, branch/worktree and `git status` before the
   run. Do not test a writer's unintegrated branch as closure evidence.
2. Run only against the isolated QA project and fixed loopback ports. Serialize
   suites that use those ports. Check the target, entrypoint and delivery guard
   before any synthetic write.
3. Drive the requested finding plus its relevant cross-cutting journey. Test
   the specific fix, adjacent success path, role denials, error/retry state,
   persistence and rendered state.
4. For a mutation, record the operation/revision ID and read the authoritative
   emulator state after the UI result. A toast alone is not proof.
5. Classify the result as `pass`, `product-defect`, `fixture-error`,
   `infrastructure-unavailable`, `blocked-decision` or `not-run`. Do not convert
   unavailable evidence into a pass.
6. A defect report must include role, platform, viewport/theme/text scale,
   fixture state, exact steps, expected result, observed result, severity,
   evidence and responsible workstream.
7. Preserve original F/X traceability. Newly found regressions receive a new Q
   identifier and link back to the triggering scenario.

Evidence records are JSON objects or arrays with these required fields:

```json
{
  "scenarioId": "F14-REVISION-N-NPLUS1",
  "checkpoint": "0123456789abcdef0123456789abcdef01234567",
  "executedAt": "2026-09-11T16:00:00Z",
  "tester": "Q",
  "classification": "product-defect",
  "role": "admin",
  "platform": "web-chrome",
  "dataState": "stale-approval",
  "expected": "The stale approval is rejected.",
  "observed": "Describe the exact rendered and backend result.",
  "severity": "P0",
  "responsibleWorkstream": "D",
  "evidence": ["absolute/or/reviewable/evidence-reference"]
}
```

Validate an evidence file from the exact clean checked-out commit before
attaching it to the integration ledger:

```text
node scripts/qa/acceptance_scenarios.js verify-evidence evidence.json
```

Validation rejects evidence whose checkpoint is not current `HEAD`, a dirty
worktree, an invalid UTC date, or a role, platform, data state, responsible
workstream or severity outside the selected scenario. The catalog itself also
fails closed on any non-loopback host, missing forbidden action, non-allowlisted
automation command, driver, platform or stage, substituted Stage 0 marker, or
duplicate finding-to-scenario link.

## Release boundary

These scenarios authorize synthetic emulator writes and, only when I provides
an explicitly approved target, isolated staging rehearsal. They do not
authorize production reads or writes, deployment, notification delivery,
migration, activation flags, store submission or deletion of real data.
Physical-device, provider, live Hosting and store evidence must be named as
unavailable until it is actually collected at the appropriate gate.
