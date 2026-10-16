import { createPublicKey, createVerify, type JsonWebKey } from "node:crypto";
import { cleanEmail } from "./billing.js";
import { days, type QuotaStore } from "./quota.js";
import type { PlanID } from "./plans.js";

/**
 * iPhone accounts: Sign in with Apple. The app sends Apple's identity token
 * once, when the person signs in; the server checks Apple's signature and
 * keeps the account with this install, and the plan it's on:
 *
 *   account_<apple user ID>   { appleUserId, email, privateEmail, name, plan, subscription, installs: [...], firstAt, lastAt }
 *   accountinstall_<install>  { appleUserId }
 *
 * After that, the install alone refreshes the plan (after a purchase, or when
 * the app opens). Delete Account removes both records.
 */

const APPLE_ISSUER = "https://appleid.apple.com";
const APPLE_KEYS_URL = "https://appleid.apple.com/auth/keys";
const KEEP = 3650; // days: an account stays until it's deleted

export class IdentityError extends Error {}

export interface AppleIdentity {
  /** Apple's stable user ID for this app (the token's `sub`). */
  appleUserId: string;
  email?: string;
  /** True for a "Hide My Email" relay address. */
  privateEmail: boolean;
}

interface Jwk extends JsonWebKey { kid?: string }
let keyCache: { keys: Jwk[]; at: number } | undefined;

async function appleKeys(fetchImpl: typeof fetch, now: number, refresh = false): Promise<Jwk[]> {
  if (!refresh && keyCache && now - keyCache.at < 3_600_000) return keyCache.keys;
  const response = await fetchImpl(APPLE_KEYS_URL, { signal: AbortSignal.timeout(5000) });
  if (!response.ok) throw new IdentityError(`Apple's keys: HTTP ${response.status}`);
  const body = await response.json() as { keys?: Jwk[] };
  keyCache = { keys: body.keys ?? [], at: now };
  return keyCache.keys;
}

const decode = (part: string) => JSON.parse(Buffer.from(part, "base64url").toString("utf8")) as Record<string, unknown>;

/** Checks a Sign in with Apple identity token (signed by Apple, for this app, not expired). */
export async function verifyIdentityToken(token: string, audience: string,
                                          options: { now?: number; fetchImpl?: typeof fetch } = {}): Promise<AppleIdentity> {
  const now = options.now ?? Date.now();
  const fetchImpl = options.fetchImpl ?? fetch;
  const parts = token.split(".");
  if (parts.length !== 3) throw new IdentityError("Not a token.");
  let header: Record<string, unknown>, claims: Record<string, unknown>;
  try {
    header = decode(parts[0]);
    claims = decode(parts[1]);
  } catch {
    throw new IdentityError("Unreadable token.");
  }
  if (header.alg !== "RS256") throw new IdentityError("Unexpected signature type.");
  let key = (await appleKeys(fetchImpl, now)).find((k) => k.kid === header.kid);
  if (!key) key = (await appleKeys(fetchImpl, now, true)).find((k) => k.kid === header.kid);
  if (!key) throw new IdentityError("Unknown signing key.");
  const verifier = createVerify("RSA-SHA256");
  verifier.update(`${parts[0]}.${parts[1]}`);
  if (!verifier.verify(createPublicKey({ key, format: "jwk" }), Buffer.from(parts[2], "base64url"))) {
    throw new IdentityError("Bad signature.");
  }
  if (claims.iss !== APPLE_ISSUER) throw new IdentityError("Not from Apple.");
  const audiences = Array.isArray(claims.aud) ? claims.aud : [claims.aud];
  if (!audiences.includes(audience)) throw new IdentityError("Not for this app.");
  if (typeof claims.exp !== "number" || claims.exp * 1000 < now) throw new IdentityError("Expired.");
  if (typeof claims.sub !== "string" || !claims.sub) throw new IdentityError("No user.");
  const email = cleanEmail(claims.email);
  const privateEmail = claims.is_private_email === true || claims.is_private_email === "true";
  return { appleUserId: claims.sub, ...(email ? { email } : {}), privateEmail };
}

export interface AccountPlan {
  plan: PlanID;
  /** The App Store subscription's original transaction ID, for a paid plan. */
  subscription?: string;
}

const short = (value: unknown, max: number) => (typeof value === "string" ? value.trim().slice(0, max) : "");

/** Saves a signed-in account with this install. Returns whether the account is new. */
export async function signIn(store: QuotaStore, install: string, identity: AppleIdentity,
                             details: { name?: unknown } & AccountPlan, now = new Date()): Promise<{ new: boolean; record: Record<string, unknown> }> {
  const key = `account_${identity.appleUserId}`;
  const before = await store.getRecord(key);
  const installs = Array.isArray(before?.installs) ? before.installs as { install?: string }[] : [];
  if (!installs.some((entry) => entry.install === install)) {
    installs.push({ install, at: now.toISOString() } as { install: string });
    if (installs.length > 20) installs.shift();
  }
  const record: Record<string, unknown> = {
    ...before,
    appleUserId: identity.appleUserId,
    // Apple sends the email every time in the token, the name only the first time.
    email: identity.email ?? before?.email ?? null,
    privateEmail: identity.email ? identity.privateEmail : before?.privateEmail ?? false,
    name: short(details.name, 80) || before?.name || null,
    plan: details.plan,
    subscription: details.subscription ?? before?.subscription ?? null,
    installs,
    firstAt: before?.firstAt ?? now.toISOString(),
    lastAt: now.toISOString(),
  };
  await store.putRecord(key, record, days(KEEP, now));
  await store.putRecord(`accountinstall_${install}`, { appleUserId: identity.appleUserId }, days(KEEP, now));
  return { new: !before || Boolean(before.deleted), record };
}

/** Updates the plan of the account signed in on this install (after a purchase, or on launch). */
export async function refreshAccount(store: QuotaStore, install: string, plan: AccountPlan,
                                     now = new Date()): Promise<{ record: Record<string, unknown>; upgraded: boolean } | null> {
  const link = await store.getRecord(`accountinstall_${install}`);
  const appleUserId = typeof link?.appleUserId === "string" ? link.appleUserId : undefined;
  if (!appleUserId) return null;
  const key = `account_${appleUserId}`;
  const before = await store.getRecord(key);
  if (!before || before.deleted) return null;
  const record = { ...before, plan: plan.plan, subscription: plan.subscription ?? before.subscription ?? null, lastAt: now.toISOString() };
  await store.putRecord(key, record, days(KEEP, now));
  return { record, upgraded: before.plan === "free" && plan.plan !== "free" };
}

/** Delete Account: removes the account and this install's link to it. */
export async function deleteAccount(store: QuotaStore, install: string, now = new Date()): Promise<boolean> {
  const link = await store.getRecord(`accountinstall_${install}`);
  const appleUserId = typeof link?.appleUserId === "string" ? link.appleUserId : undefined;
  // Records can't be removed one by one here: they're emptied and expire within a day.
  await store.putRecord(`accountinstall_${install}`, { deleted: true }, days(1, now));
  if (!appleUserId) return false;
  const before = await store.getRecord(`account_${appleUserId}`);
  for (const entry of Array.isArray(before?.installs) ? before.installs as { install?: string }[] : []) {
    if (entry.install && entry.install !== install) {
      await store.putRecord(`accountinstall_${entry.install}`, { deleted: true }, days(1, now));
    }
  }
  await store.putRecord(`account_${appleUserId}`, { deleted: true }, days(1, now));
  return true;
}
