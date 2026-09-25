# Follow and notification inbox status

This branch adds fan team, league, and player follows, a signed-in notification
bell and inbox, and a server trigger for final scores and schedule changes in a
certified public snapshot. A team representative continues to be bound to one
authoritative team membership, with a My Team shortcut in the app. There is no
player account role or player claim flow.

The notification trigger reads only `publicData/{associationId}/snapshots/current`
after a certified published change. It does not send from private stat approval.
The production repository currently has no writer for that public snapshot;
the only writer is the local QA seed. The bell, inbox, and trigger can be tested
locally, but live result and schedule alerts require the separate certified
public publisher and its approval gates. Do not deploy or describe these alerts
as operational before that publisher exists and a live end-to-end check passes.

New bulk schedule releases produce one digest instead of one alert per new game.
Existing certified-to-certified changes are compared. A retraction followed by
republishing cannot be compared to the previous certified version until a
durable release-history source exists, so that transition currently sends no
alert. Retries use the release's server update time and skip an event once a
newer current snapshot supersedes it. Push remains best effort; the in-app
inbox is the durable record.

Account deletion remains dormant. Its AD05-C notification adapter is still
`notApplicableOnly`, although `users/{uid}/notifications` now exists. Before
account deletion activation, implement and verify an erase adapter for that
subcollection, including retry and terminal evidence.

Player discovery and following are limited to player detail records in the
published leaderboards. Player follows do not create notification events in
this branch. The user can unfollow a player from Settings even if the player
is absent from the current release.
