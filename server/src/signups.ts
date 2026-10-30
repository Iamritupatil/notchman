import { createHash } from "node:crypto";
import { cleanEmail } from "./billing.js";
import { dayKey, days, minuteKey, networkOf, type QuotaStore } from "./quota.js";

/**
 * Emails people give on notchman.app before downloading the desktop app, and
 * the install they then make. When the app says its first hello from the same
 * network within two days, the email is kept with that install ID and the
 * computer's ID, so the owner knows who installed. The network address itself
 * isn't stored: only a one-way code made from it, kept for two days.
 *
 *   signup_<email>       { email, platform, source, firstAt, lastAt, installs: [{ install, device, platform, version, at }] }
 *   dlpending_<network>  { email }   (2 days)
 */

const PLATFORMS = new Set(["windows", "mac", "mac-intel"]);
const ALL = Number.MAX_SAFE_INTEGER;

function networkCode(ip: string, pepper = ""): string {
  return createHash("sha256").update(`notchman-download:${pepper}:${networkOf(ip)}`).digest("hex").slice(0, 32);
}

const short = (value: unknown, max: number) => (typeof value === "string" ? value.trim().slice(0, max) : "");

/** Saves an email given before a download. Returns false for a bad email or too many at once. */
export async function recordSignup(store: QuotaStore, body: { email?: unknown; platform?: unknown; source?: unknown },
                                   visitor: { ip?: string; pepper?: string }, now = new Date()): Promise<boolean> {
  const email = cleanEmail(body.email);
  if (!email) return false;
  const network = visitor.ip ? networkCode(visitor.ip, visitor.pepper) : undefined;
  if (network) {
    const rate = await store.consume(`signuprate_${network}_${minuteKey(now)}`, 5, days(1, now));
    if (!rate.allowed) return false;
  }
  const platform = PLATFORMS.has(String(body.platform)) ? String(body.platform) : "unknown";
  const key = `signup_${email}`;
  const before = await store.getRecord(key);
  await store.putRecord(key, {
    installs: [],
    ...before,
    email,
    platform,
    source: short(body.source, 60) || before?.source || "direct",
    firstAt: before?.firstAt ?? now.toISOString(),
    lastAt: now.toISOString(),
  }, days(400, now));
  if (network) await store.putRecord(`dlpending_${network}`, { email }, days(2, now));
  await store.consume(`site_${dayKey(now)}_signup_${platform}`, ALL, days(400, now));
  return true;
}

/**
 * A new install's first hello: if someone on this network gave their email
 * before downloading (in the last two days), keep the install and computer
 * IDs with it. Returns the email it was linked to, if any.
 */
export async function linkInstall(store: QuotaStore, installId: string,
                                  info: { ip?: string; pepper?: string; device?: string; platform?: unknown; version?: unknown },
                                  now = new Date()): Promise<string | undefined> {
  if (!info.ip) return undefined;
  const pending = await store.getRecord(`dlpending_${networkCode(info.ip, info.pepper)}`);
  const email = cleanEmail(pending?.email);
  if (!email) return undefined;
  const key = `signup_${email}`;
  const record = (await store.getRecord(key)) ?? { email, firstAt: now.toISOString() };
  const installs = Array.isArray(record.installs) ? record.installs as { install?: string }[] : [];
  if (!installs.some((entry) => entry.install === installId) && installs.length < 10) {
    installs.push({
      install: installId,
      ...(info.device ? { device: info.device } : {}),
      platform: short(info.platform, 10) || "unknown",
      version: short(info.version, 20) || "unknown",
      at: now.toISOString(),
    } as { install: string });
  }
  await store.putRecord(key, { ...record, installs }, days(400, now));
  return email;
}

// --- iPhone beta -----------------------------------------------------------------

const BETA_DEVICES = new Set(["iphone-island", "iphone-other", "ipad", "android", "other"]);

/**
 * Someone asking for the iPhone beta on notchman.app: their email, their
 * device and what they want to listen to, so the owner can invite them.
 *
 *   betasignup_<email>   { email, device, wants, source, firstAt, lastAt }
 *
 * Returns whether this email is new (the owner hears about new ones), or null
 * for a bad email or too many at once.
 */
export async function recordBetaSignup(store: QuotaStore, body: { email?: unknown; device?: unknown; wants?: unknown; source?: unknown },
                                       visitor: { ip?: string; pepper?: string }, now = new Date()): Promise<{ new: boolean; record: Record<string, unknown> } | null> {
  const email = cleanEmail(body.email);
  if (!email) return null;
  if (visitor.ip) {
    const rate = await store.consume(`betarate_${networkCode(visitor.ip, visitor.pepper)}_${minuteKey(now)}`, 5, days(1, now));
    if (!rate.allowed) return null;
  }
  const key = `betasignup_${email}`;
  const before = await store.getRecord(key);
  const record = {
    ...before,
    email,
    device: BETA_DEVICES.has(String(body.device)) ? String(body.device) : "other",
    wants: short(body.wants, 300),
    source: short(body.source, 60) || before?.source || "direct",
    firstAt: before?.firstAt ?? now.toISOString(),
    lastAt: now.toISOString(),
  };
  await store.putRecord(key, record, days(400, now));
  if (!before) {
    await store.consume(`site_${dayKey(now)}_beta_signup`, ALL, days(400, now));
    await store.consume(`site_${dayKey(now)}_betadevice_${record.device}`, ALL, days(400, now));
  }
  return { new: !before, record };
}
