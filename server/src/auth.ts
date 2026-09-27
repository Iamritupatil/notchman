import { createRemoteJWKSet, jwtVerify, type JWTVerifyGetKey } from "jose";

/**
 * Every request must carry two Firebase tokens (both free on Firebase's Spark
 * plan; no Blaze needed):
 * - App Check (App Attest): proves the call comes from the genuine Notchman app
 *   on a real iPhone.
 * - Firebase Auth ID token (anonymous sign-in): a stable per-user identity for
 *   counting TL;DRs.
 * Both are JWTs signed by Google; we check them against Google's public keys.
 */
const APP_CHECK_KEYS = createRemoteJWKSet(new URL("https://firebaseappcheck.googleapis.com/v1/jwks"));
const ID_TOKEN_KEYS = createRemoteJWKSet(
  new URL("https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com"));

export class AuthError extends Error {}

export interface FirebaseProject {
  id: string;
  number: string;
  /** Optional: only accept App Check tokens for this app (the iOS app's Firebase App ID). */
  appId?: string;
}

export async function verifyAppCheck(token: string | undefined, project: FirebaseProject,
                                     keys: JWTVerifyGetKey = APP_CHECK_KEYS): Promise<void> {
  if (!token) throw new AuthError("Missing App Check token.");
  try {
    const { payload } = await jwtVerify(token, keys, {
      issuer: `https://firebaseappcheck.googleapis.com/${project.number}`,
      audience: `projects/${project.number}`,
      algorithms: ["RS256"],
    });
    if (project.appId && payload.sub !== project.appId) throw new AuthError("App Check token is for another app.");
  } catch (error) {
    throw error instanceof AuthError ? error : new AuthError("Invalid App Check token.");
  }
}

/** Returns the Firebase user ID. */
export async function verifyIdToken(token: string | undefined, project: FirebaseProject,
                                    keys: JWTVerifyGetKey = ID_TOKEN_KEYS): Promise<string> {
  if (!token) throw new AuthError("Missing sign-in token.");
  try {
    const { payload } = await jwtVerify(token, keys, {
      issuer: `https://securetoken.google.com/${project.id}`,
      audience: project.id,
      algorithms: ["RS256"],
    });
    if (!payload.sub) throw new AuthError("Sign-in token has no user.");
    return payload.sub;
  } catch (error) {
    throw error instanceof AuthError ? error : new AuthError("Invalid sign-in token.");
  }
}
