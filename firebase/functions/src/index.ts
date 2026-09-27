/**
 * Notchman Cloud Functions.
 *
 * Every function:
 * - requires App Check (App Attest on iOS), so only the genuine Notchman app on a
 *   real device can call it; tokens are single-use to stop replays
 * - requires Firebase Auth (anonymous sign-in is fine), so allowances are per user
 * - reads the Groq and ElevenLabs keys from Secret Manager; they never exist in the app
 * - never stores or logs message text
 */
import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { defineSecret } from "firebase-functions/params";
import { HttpsError, onCall, type CallableRequest } from "firebase-functions/v2/https";
import { handleTLDR, handleUsage, type Result } from "./handlers.js";
import { FirestoreQuotaStore } from "./quota.js";

initializeApp();

const GROQ_API_KEY = defineSecret("GROQ_API_KEY");
const ELEVENLABS_API_KEY = defineSecret("ELEVENLABS_API_KEY");

const store = new FirestoreQuotaStore(getFirestore());

const secure = {
  region: "us-central1",
  enforceAppCheck: true,
  maxInstances: 20,
  timeoutSeconds: 60,
  memory: "256MiB" as const,
};

function requireUser(request: CallableRequest): string {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Sign-in required.");
  return request.auth.uid;
}

function respond(result: Result) {
  if (result.ok) return result.body;
  throw new HttpsError(result.code, result.message, result.details);
}

export const tldr = onCall(
  { ...secure, consumeAppCheckToken: true, secrets: [GROQ_API_KEY, ELEVENLABS_API_KEY] },
  async (request) => respond(await handleTLDR(requireUser(request), request.data, { store })),
);

export const usage = onCall(secure, async (request) => respond(await handleUsage(requireUser(request), request.data, { store })));
