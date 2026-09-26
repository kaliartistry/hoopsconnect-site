import * as admin from "firebase-admin";
import {AUTHORIZATION_SCHEMA_VERSION, capabilities} from "./authorization";

export interface AuthorizedRecipient {
  uid: string;
  displayName: string;
  teamId: string | null;
  divisionId: string | null;
  fcmTokens: string[];
  notificationPrefs: Record<string, unknown>;
}

export interface TeamAcknowledgmentRecipient extends AuthorizedRecipient {
  teamId: string;
  teamName: string;
}

export interface FavoriteTeamAudienceRecipient extends AuthorizedRecipient {
  favoriteTeamIds: string[];
  favoriteLeagueIds: string[];
}

interface RecipientOptions {
  divisionId?: string | null;
  userIds?: string[];
  preference?: "ackReminders" | "statReminders" | "newPosts";
}

export async function loadFavoriteTeamRecipients(
  db: admin.firestore.Firestore,
  associationId: string,
  teamIds: readonly string[],
  leagueIds: readonly string[] = [],
): Promise<AuthorizedRecipient[]> {
  return selectFavoriteTeamRecipients(
    await loadFavoriteTeamAudience(db, associationId), teamIds, leagueIds,
  );
}

export function selectFavoriteTeamRecipients(
  audience: readonly FavoriteTeamAudienceRecipient[],
  teamIds: readonly string[],
  leagueIds: readonly string[] = [],
): FavoriteTeamAudienceRecipient[] {
  const followedTeams = new Set(teamIds.filter((teamId) => teamId.length > 0));
  const followedLeagues = new Set(leagueIds.filter((leagueId) => leagueId.length > 0));
  if (followedTeams.size === 0 && followedLeagues.size === 0) return [];
  return audience.filter((recipient) =>
    recipient.favoriteTeamIds.some((teamId) => followedTeams.has(teamId)) ||
    recipient.favoriteLeagueIds.some((leagueId) => followedLeagues.has(leagueId))
  );
}

export async function loadFavoriteTeamAudience(
  db: admin.firestore.Firestore,
  associationId: string,
): Promise<FavoriteTeamAudienceRecipient[]> {
  const memberships = await db
    .collection("memberships")
    .where("associationId", "==", associationId)
    .get();
  const active = memberships.docs.filter((doc) => {
    const data = doc.data();
    return data.authorizationSchemaVersion === AUTHORIZATION_SCHEMA_VERSION &&
      data.status === "active";
  });
  if (active.length === 0) return [];
  const profiles = await db.getAll(...active.map((doc) => db.doc(`users/${doc.id}`)));
  const result: FavoriteTeamAudienceRecipient[] = [];
  for (let index = 0; index < active.length; index += 1) {
    const profile = profiles[index];
    const user = profile.data() ?? {};
    const favorites = Array.isArray(user.favoriteTeamIds) ?
      user.favoriteTeamIds.filter((value): value is string => typeof value === "string") : [];
    const favoriteLeagues = Array.isArray(user.favoriteLeagueIds) ?
      user.favoriteLeagueIds.filter((value): value is string => typeof value === "string") : [];
    const prefs = user.notificationPrefs && typeof user.notificationPrefs === "object" ?
      user.notificationPrefs as Record<string, unknown> : {};
    if (!profile.exists ||
      user.authorizationSchemaVersion !== AUTHORIZATION_SCHEMA_VERSION ||
      user.associationId !== associationId ||
      typeof user.displayName !== "string" ||
      (favorites.length === 0 && favoriteLeagues.length === 0)) {
      continue;
    }
    result.push({
      uid: active[index].id,
      displayName: user.displayName,
      teamId: null,
      divisionId: null,
      fcmTokens: Array.isArray(user.fcmTokens) ?
        user.fcmTokens.filter((token): token is string =>
          typeof token === "string" && token.length > 0) : [],
      notificationPrefs: prefs,
      favoriteTeamIds: favorites,
      favoriteLeagueIds: favoriteLeagues,
    });
  }
  return result;
}

/**
 * Resolve notification recipients from server-owned membership authority.
 * The user document is joined only for presentation and delivery data.
 */
export async function loadAuthorizedRecipients(
  db: admin.firestore.Firestore,
  associationId: string,
  capability: string,
  options: RecipientOptions = {},
): Promise<AuthorizedRecipient[]> {
  const requestedIds = options.userIds ? new Set(options.userIds) : null;
  const membershipSnapshot = await db
    .collection("memberships")
    .where("associationId", "==", associationId)
    .get();

  const authorities = membershipSnapshot.docs.filter((doc) => {
    const data = doc.data();
    return data.authorizationSchemaVersion === AUTHORIZATION_SCHEMA_VERSION
      && data.status === "active"
      && Array.isArray(data.capabilities)
      && data.capabilities.includes(capability)
      && (!options.divisionId || data.divisionId === options.divisionId)
      && (!requestedIds || requestedIds.has(doc.id));
  });
  if (authorities.length === 0) return [];

  const profiles = await db.getAll(...authorities.map((doc) => db.doc(`users/${doc.id}`)));
  const result: AuthorizedRecipient[] = [];
  for (let index = 0; index < authorities.length; index += 1) {
    const authority = authorities[index].data();
    const profile = profiles[index];
    if (!profile.exists) continue;
    const user = profile.data() ?? {};
    if (
      user.authorizationSchemaVersion !== AUTHORIZATION_SCHEMA_VERSION
      || user.associationId !== associationId
      || typeof user.displayName !== "string"
    ) {
      continue;
    }
    const notificationPrefs = user.notificationPrefs && typeof user.notificationPrefs === "object"
      ? user.notificationPrefs as Record<string, unknown>
      : {};
    if (options.preference && notificationPrefs[options.preference] === false) continue;
    result.push({
      uid: authorities[index].id,
      displayName: user.displayName,
      teamId: typeof authority.teamId === "string" ? authority.teamId : null,
      divisionId: typeof authority.divisionId === "string" ? authority.divisionId : null,
      fcmTokens: Array.isArray(user.fcmTokens)
        ? user.fcmTokens.filter((token): token is string => typeof token === "string" && token.length > 0)
        : [],
      notificationPrefs,
    });
  }
  return result;
}

/**
 * Acknowledgment posts target active team representatives, not every role that
 * happens to hold the acknowledgment capability. Resolve the display name from
 * the authoritative team record so private posts never expose a raw team ID.
 */
export async function loadTeamAcknowledgmentRecipients(
  db: admin.firestore.Firestore,
  associationId: string,
  options: Pick<RecipientOptions, "divisionId"> = {},
): Promise<TeamAcknowledgmentRecipient[]> {
  const recipients = (await loadAuthorizedRecipients(
    db,
    associationId,
    capabilities.postsAcknowledge,
    options,
  )).filter((recipient): recipient is AuthorizedRecipient & {teamId: string} =>
    typeof recipient.teamId === "string" && recipient.teamId.length > 0
  );
  if (recipients.length === 0) return [];

  const teamIds = [...new Set(recipients.map((recipient) => recipient.teamId))];
  const teamDocs = await db.getAll(
    ...teamIds.map((teamId) => db.doc(`associations/${associationId}/teams/${teamId}`))
  );
  const teamNames = new Map<string, string>();
  for (let index = 0; index < teamIds.length; index += 1) {
    const team = teamDocs[index];
    const name = team.exists ? team.data()?.name : null;
    if (typeof name === "string" && name.trim().length > 0) {
      teamNames.set(teamIds[index], name.trim());
    }
  }

  return recipients.flatMap((recipient) => {
    const teamName = teamNames.get(recipient.teamId);
    return teamName ? [{...recipient, teamName}] : [];
  });
}
