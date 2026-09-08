import * as admin from "firebase-admin";
import {AUTHORIZATION_SCHEMA_VERSION} from "./authorization";

export interface AuthorizedRecipient {
  uid: string;
  displayName: string;
  teamId: string | null;
  divisionId: string | null;
  fcmTokens: string[];
  notificationPrefs: Record<string, unknown>;
}

interface RecipientOptions {
  divisionId?: string | null;
  userIds?: string[];
  preference?: "ackReminders" | "statReminders" | "newPosts";
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
