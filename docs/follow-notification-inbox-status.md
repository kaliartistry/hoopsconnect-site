# Follow and notification inbox status

This branch adds fan team, league, and player follows, a signed-in notification
bell and inbox, and a server trigger for final scores and schedule changes in a
certified public snapshot. A team representative continues to be bound to one
authoritative team membership, with a My Team shortcut in the app. There is no
player account role or player claim flow.

The notification trigger reads only `publicData/{associationId}/snapshots/current`
after a certified published change. It does not send from private stat approval.
The integration branch has no production writer for that public snapshot.
However, a September 26 provider read confirmed that production already runs
`onPublicLeagueSourceWritten`, deployed September 17. Its separate
`legacy_live.js` entrypoint writes this exact path under the enabled,
server-owned `publicSnapshotControls/jba` v1.1 control. The current snapshot is
published, has `certificationStatus: certified`, and records
`verificationStatus: legacyApproved`. This compatibility publication is not an
official-stat v2 certificate. The notification trigger accepts its format.

The deployed compatibility source and the newer native app source are present
in the original uncommitted checkout, not this branch's Git baseline. Reconcile
them into a reviewed release candidate before deployment or mobile upload.
The new inbox trigger is not deployed yet. A live end-to-end check remains
required before describing alerts as operational.

New bulk schedule releases produce one digest instead of one alert per new game.
Existing certified-to-certified changes are compared. A retraction followed by
republishing cannot be compared to the previous certified version until a
durable release-history source exists, so that transition currently sends no
alert. Retries use the release's server update time and compare each outcome
to the latest certified snapshot, dropping only outcomes that have since been
changed or removed. Push remains best effort; the in-app inbox is the durable
record.

Account deletion remains dormant. Its AD05-C notification adapter is still
`notApplicableOnly`, although `users/{uid}/notifications` now exists. Before
account deletion activation, implement and verify an erase adapter for that
subcollection, including retry and terminal evidence.

Player discovery and following are limited to player detail records in the
published leaderboards. Player follows do not create notification events in
this branch. The user can unfollow a player from Settings even if the player
is absent from the current release.
