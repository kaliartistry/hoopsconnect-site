# Stage 1 official-stat candidate foundation

Status: **implemented as candidate-only logic; not routed, deployed, or
production-activated**

Baseline: `6e74ba13faf316da2c506c2cafcfca985dd774cc`

This packet implements the client-side integrity boundary needed before server
commands, local-journal delivery, or public projections can be activated. It
does not change Firestore Rules, Functions entrypoints, routes, deployment
configuration, canonical dormancy pins, or production data.

## Lifecycle dimensions

`candidate_review_workflow.dart` keeps four dimensions independent:

| Dimension | States |
| --- | --- |
| Play | the v2 `PlayState` contract: scheduled through administratively terminated |
| Capture | preparation, live draft, post-game draft, sealed |
| Human review | draft, submitted, under review, changes requested, resubmitted, approved |
| Delivery | saved on device, queued, sending, accepted, needs attention |

Review approval in this candidate is not certification. Certification remains
the server-owned v2 certificate contract and still requires fresh authority,
validation/evidence, separation of duties, and the activation gates.

The review command envelope binds a stable command ID, actor, expected workflow
version, full game scope, and an exact revision ID/number/hash/predecessor fact.
Request-changes commands retain a stable reason code and human explanation.
Resubmission binds both the rejected revision N and a distinct immutable
successor N+1 whose `supersedesRevisionId` is exactly N. The successor must
first be opened locally and reach an accepted delivery receipt state. Retrying
the identical successor is a no-op that preserves that receipt and workflow
version; a different successor conflicts. An approval for N after N+1 is
submitted fails `staleRevision`.

Exact command replay returns the prior state. Reusing the same command ID with
different immutable content fails `payloadKeyConflict`. Saved-on-device or a
pending transport state cannot satisfy submission.

## Work queue

`StatsWorkItem` deliberately has no scheduled timestamp. Its section derives
from explicit assignment, play, and review state:

- scheduled work is preparation;
- in-progress or suspended work is live capture;
- completed or administratively terminated draft work needs stats;
- changes requested is its own actionable queue;
- submitted, under-review, and resubmitted work awaits review;
- approved work is complete;
- unassigned, cancelled, or postponed work is not actionable.

A scheduled/postponed game carrying live capture or a non-draft review state,
and an in-progress game carrying a review/approval state, is classified as
inconsistent. It cannot leak into a review or complete queue.

This candidate classifier must replace the legacy `statsStatus == pending`
Firestore query only after the server schema and migration below are accepted.

## Rules and calculator boundary

`candidate_stats_runtime.dart` is the sole Stage 1 bridge between:

1. the Stage 0 read-only legacy adapter;
2. a reviewed v2 calculator input; and
3. the dormant normalized box-score calculator v2.

Every call receives a named `CandidateRulesProfile` with association-scoped
ruleset version/hash and one explicit decision state: unresolved, reference
only, or adopted. Runtime dates select nothing. An adopted state cannot be
constructed without adoption evidence. The supplied canonical rules artifact
must hash exactly to `rulesetVersion.sha256`; a changed duration, overtime,
penalty, or exceptional-scoring value rejects before calculator invocation.

Legacy evidence never reaches the calculator. The wrapper preserves its raw
candidate hash, source payload hash, evidence classification, unmapped paths,
and blocker list, including unknown shooting, turnover, participation, time,
and identity facts. Reviewed complete v2 inputs may run deterministic arithmetic
for candidate testing, including overtime and adjudicated/exceptional results,
but every wrapper result keeps `activationAllowed` and
`certificationAllowed` false.

The active legacy screens and `StatsValidator` remain byte-for-byte compatible
with the Stage 1 baseline. Their existing universal 48-minute, five-foul,
240-team-minute, and box-score assumptions are not reused by this candidate and
are not claimed fixed. They must move together to the accepted preparation
package and server contract before the candidate can replace the production
flow. This packet does not claim that a client-only validation change can be
activated independently.

## Candidate status UI

`CandidateWorkflowStatusCard` uses the shared state-message pattern and reports
delivery and review separately. It distinguishes saved on this device, queued,
sending, server accepted, and needs attention. It also distinguishes draft,
submitted, under review, changes requested, resubmitted, and approved, shows the
exact revision number, retains the latest reviewer reason, offers retry only for
delivery attention, and says explicitly that certification/publication are
separate. During correction it shows both the reviewed N identity and active
N+1 identity, including the revision ID and a short hash, while delivery status
tracks N+1.

Preparation with no active revision is labelled as package preparation and not
ready for review. It never claims that nonexistent work is saved or uploadable.

The widget is not imported by an app route in this packet.

## Integration-owner requests

The following changes touch server, Rules, shared routes, or dormancy roots and
belong to the integration owner:

1. Define one server command endpoint per lifecycle action, or one typed command
   endpoint, with the exact envelope and stable errors from the v2 contract.
   Transactions must compare full scope, membership/grant, assignment version,
   writer epoch, workflow version, revision ID/hash, validation report hash, and
   separation-of-duties policy. Command ID replay returns the original result;
   changed reuse fails `payloadKeyConflict`.
2. Store request-changes and resubmission events append-only. Never overwrite the
   reason on revision N when N+1 is created. Certification must target exactly
   the reviewed N+1 manifest/hash and must not mutate N.
3. Add server-owned explicit play and review state to the game worklist. Migrate
   legacy pending/submitted/approved values through a reviewed classification;
   do not infer completion from `startTime`. Replace the legacy pending query
   only after indexed emulator tests prove preparation and needs-stats behavior.
4. Add the agreed statistician/admin routes and capability guards after the A/D
   route contract is accepted. The candidate status widget and runtime must stay
   unreachable until the server endpoint, Rules, and local-journal provider are
   integrated together.
5. Keep new v2 revision/review paths server-write-only. Add emulator denial tests
   for direct client writes, cross-association scope, unassigned games, stale
   assignment/writer epochs, self-approval when disabled, and stale revision
   approval.
6. Construct the local-journal preparation package from an authoritative
   bootstrap. Foreground delivery must preserve the command ID and payload after
   lost responses, bind accepted receipts to the exact revision head, and retain
   conflict branches. Do not treat Firestore pending-write metadata as a receipt.
7. Record the JBA/NBL adopted playing rules, overtime, foul/disqualification,
   exceptional-result treatment, and competition policy with evidence before
   changing the current rules decision from unresolved. Then remove the old
   live-capture assumptions by injecting that accepted package throughout its
   notifier and widgets.
8. Before any production import reaches these files, deliberately replace the
   applicable candidate dormancy/import-graph guard and exact hash pins with
   reviewed integration proof. Do not regenerate unrelated pins.

## Focused evidence

The packet tests prove:

- submit N, begin review N, send back N with retained reason, open and deliver
  N+1, resubmit N+1, reject stale approval of N, and approve exactly N+1;
- exact retry idempotency and changed-payload conflict;
- exact successor retry preservation, different-successor conflict, full-scope
  rejection, and explicit predecessor rejection;
- submission refusal before an accepted delivery receipt;
- queue placement from explicit workflow state without a timestamp;
- double overtime, played score separate from an administrative result,
  accidental own basket, defensive goaltending, and an alternate overtime
  penalty policy through their injected named fixture profiles;
- mismatched rules profiles reject before calculator invocation;
- canonical rules-artifact hash mismatch rejects before calculator invocation;
- contradictory future/live review-state combinations classify as inconsistent;
- legacy unknown shooting/turnover facts and unmapped source paths remain
  preserved and never invoke the calculator; and
- rendered status copy distinguishes local persistence, server acceptance, and
  human review, including retryable delivery failure.

Activation remains blocked by unresolved JBA rules adoption, server command and
Rules integration, authoritative preparation/journal delivery, staging evidence,
and the existing official-stat activation gates.
