# JBL local presentation import

Local-only historical data, not a deployment or a current-season roster.

**Subsequent live replacement:** The local-only work below was followed by the
authorized live migration recorded in [JBL_LIVE_MIGRATION.md](JBL_LIVE_MIGRATION.md).
That migration publishes JBL to both existing environments; it does not publish
the local supporting-sponsor examples or convert historical rows into current
registrations.

## Source and boundaries

Kurt supplied `NBL total stats1ist round (1).xls` and the JBL, team and FOSKA
artwork. The workbook is dated April 10, 2025. Its 188 player rows cover ten
teams and reconcile to 5,555 points. Display it as **2025 First Round**.
Points, rebounds, assists, steals and blocks are cumulative totals. Per-game
averages divide those totals by each player's own recorded game count.
All recorded players are included; no official qualifying minimum was supplied.
The workbook does not establish current registrations, fixtures, individual game
results, quarter scores, official standings, or shooting attempts. None are invented.

The internal `jbl-2025-first-round` partition uses the existing division-scoped
data contract, but its display name is the historical period, not an official
division. JBL is the parent league. No `Open` or `Premier` division is asserted.
`WIZZARDS'25` maps to the supplied Tivoli Wizards artwork. Original player
spelling is retained; unexplained trailing asterisks are removed only from display.

FOSKA Oats is Main Sponsor. ShipSafe SDK and YardCourt are separately labeled
demo supporting-sponsor examples, not claims of actual JBL sponsorship.
The JaBA concept image is preserved in the local source folder but not adopted.
Existing association identity and unrelated leagues remain unchanged.

## Reproduce and roll back

Sources and three original-file rollback copies are under
`.local/jbl-import-20260917/`, ignored by Git. Source images are copied byte-for-byte.
`node scripts/build_jbl_presentation.js` regenerates only the bundled presentation
JSON and thirteen explicitly named image assets. `--check` compares without writing.
It requires the local xlrd environment and original workbook. It has no Firebase
dependency. The old QA seeds and share test fixtures are deliberately unchanged;
they are regression fixtures, not the JBL historical import.

To undo this isolated import, restore the bundled JSON from its rollback copy
and reverse only the JBL-specific source changes. Do not reset the dirty worktree,
run the broad staging seed, or delete unrelated league data. New image files can
remain unused safely until the rollback has been verified.

Normal app builds still read their server-published snapshot. This bundle is used
only by explicitly flagged presentation builds and the offline presentation QA
entrypoint. A local change does not change Firebase, store binaries, or tester links.

Compile the safe local web harness with:

```
flutter build web --release --no-pub --target lib/main_presentation_qa.dart --dart-define=HOOPSCONNECT_LOCAL_PRESENTATION_QA=true --output .local/jbl-import-20260917/web
```

Serve that output on loopback only. The harness refuses non-loopback hosts and
does not initialize Firebase. It renders the actual public widgets with bundled
data and an offline share validator. Its sign-in destination is deliberately
disconnected, and it is not a mobile store or production release target.

## Roadmap only: externally hosted highlight videos

Future idea, not implemented: staff/admin supplies a YouTube video URL for a media
item. HoopsConnect displays/embeds that externally hosted highlight content. It
does not upload, store, or host the video itself. URL validation, embedding/privacy
behavior, rights to publish, and unavailable-video handling need design and review
before implementation. No upload flow, player integration, or new video field is
included in this change.

## Local verification, September 17

- Three Node import tests pass: scope preservation, ambiguity rejection, and
  actual bundled team/player totals. Regeneration check passes, including exact
  equality of thirteen copied PNGs against source originals.
- Focused Flutter regression run: 86 tests passed across nine files. The three
  JBL-specific tests were rerun after adding sponsor-disclaimer scroll checks and
  all pass. Phone-width selector/tab overflows found during testing were fixed.
- Targeted analysis passes with no issues. The loopback-only release web build
  compiles, including its Wasm compatibility dry run.
- Hands-on browser checks at 1280×720 and 390×844: JBL overview, team logos,
  supporting-demo disclaimer, team/player navigation, source totals, leaderboards,
  and player/leader share previews. FOSKA and the period appear on the cards.
  Save Image produced a PNG in Downloads; its team, JBL and FOSKA marks were
  visually inspected. No relevant browser warnings/errors were observed.
- No physical-device or native simulator test of this JBL change, sign-in test,
  store build, distribution update, live-data mutation or hosting deployment was
  performed. Other-league records and source rollback copies remain preserved.
