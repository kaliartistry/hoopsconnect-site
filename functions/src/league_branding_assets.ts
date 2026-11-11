import {createHash, randomUUID} from "crypto";
import * as admin from "firebase-admin";
import {getStorage} from "firebase-admin/storage";
import {CallableRequest, HttpsError, onCall} from "firebase-functions/v2/https";
import {capabilities} from "./authorization";
import {exactKeys, id, LEAGUE_CALLABLE_OPTIONS, object} from "./league_operations";
import {authorityFromSnapshot} from "./membership";

const maxBytes = 2 * 1024 * 1024;

function imageType(bytes: Buffer): {extension: string; contentType: string} {
  if (bytes.length > 24 && bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))) {
    return {extension: "png", contentType: "image/png"};
  }
  if (bytes.length > 4 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
    return {extension: "jpg", contentType: "image/jpeg"};
  }
  if (bytes.length > 20 && bytes.toString("ascii", 0, 4) === "RIFF" && bytes.toString("ascii", 8, 12) === "WEBP") {
    return {extension: "webp", contentType: "image/webp"};
  }
  throw new HttpsError("invalid-argument", "Choose a PNG, JPG or WebP image.");
}

export async function uploadLeagueBrandingAssetHandler(request: CallableRequest<unknown>) {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in to upload a league image.");
  const data = object(request.data);
  exactKeys(data, ["leagueId", "imageBase64"]);
  const leagueId = id(data.leagueId, "league ID");
  const encoded = data.imageBase64;
  if (typeof encoded !== "string" || encoded.length > 4 * Math.ceil(maxBytes / 3) ||
      !/^[A-Za-z0-9+/]+={0,2}$/.test(encoded)) {
    throw new HttpsError("invalid-argument", "Choose an image up to 2 MB.");
  }
  const bytes = Buffer.from(encoded, "base64");
  if (!bytes.length || bytes.length > maxBytes) throw new HttpsError("invalid-argument", "Choose an image up to 2 MB.");
  const type = imageType(bytes);
  const db = admin.firestore();
  const membership = await db.doc(`memberships/${request.auth.uid}`).get();
  const authority = authorityFromSnapshot(membership, capabilities.associationManage);
  const associationId = id(authority.associationId, "association ID");
  const digest = createHash("sha256").update(bytes).digest("hex");
  const file = getStorage().bucket().file(
    `associations/${associationId}/league-branding/${leagueId}/${digest}.${type.extension}`,
  );
  let token: string = randomUUID();
  try {
    await file.save(bytes, {
      resumable: false,
      preconditionOpts: {ifGenerationMatch: 0},
      metadata: {
        contentType: type.contentType,
        cacheControl: "public,max-age=86400",
        metadata: {firebaseStorageDownloadTokens: token},
      },
    });
  } catch (error) {
    if ((error as {code?: number}).code !== 412) throw error;
    const [metadata] = await file.getMetadata();
    const storedToken = metadata.metadata?.firebaseStorageDownloadTokens;
    if (typeof storedToken !== "string" || !storedToken) {
      throw new HttpsError("internal", "The image download link could not be created.");
    }
    token = storedToken;
  }
  const endpoint = process.env.STORAGE_EMULATOR_HOST ?? "https://firebasestorage.googleapis.com";
  return {
    url: `${endpoint}/v0/b/${file.bucket.name}/o/${encodeURIComponent(file.name)}?alt=media&token=${encodeURIComponent(token)}`,
  };
}

export const uploadLeagueBrandingAsset = onCall(
  {...LEAGUE_CALLABLE_OPTIONS, maxInstances: 2},
  uploadLeagueBrandingAssetHandler,
);
