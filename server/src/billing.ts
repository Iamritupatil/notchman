import { createHmac, timingSafeEqual } from "node:crypto";
import type { PlanID } from "./plans.js";
import { days, type QuotaStore } from "./quota.js";

/**
 * Desktop subscriptions through Dodo Payments (merchant of record: it collects
 * sales tax worldwide and pays out to India).
 *
 * 1. The app asks /checkout for a link, with the buyer's email; we create a Dodo
 *    checkout for the plan's product with the email filled in and this install's
 *    (and computer's) ID in its metadata, and keep a note of who started it.
 * 2. Dodo calls /dodo-webhook on every subscription change (signed, Standard
 *    Webhooks). We save the subscription under the install ID.
 * 3. resolveEntitlement reads it: active (or cancelled but paid until a
 *    date) means the plan.
 *
 * Needs DODO_API_KEY and DODO_WEBHOOK_SECRET (Parameter Store) and the two
 * product IDs (template.yaml).
 */

export type Fetch = typeof fetch;

const LIVE = "https://live.dodopayments.com";
const TEST = "https://test.dodopayments.com";
/** The mode that worked last ("auto" tries live first, then test). */
let detected: string | undefined;
/** Dodo's answer to the last failed checkout (status and its message, no keys), for /status. */
let lastFailure: string | undefined;

export function dodoBaseURLs(): string[] {
  const mode = process.env.DODO_ENVIRONMENT;
  if (mode === "test_mode") return [TEST];
  if (mode === "live_mode") return [LIVE];
  if (detected) return [detected, detected === LIVE ? TEST : LIVE];
  return [LIVE, TEST];
}

export function productFor(plan: PlanID): string | undefined {
  if (plan === "pro") return process.env.DODO_PRO_PRODUCT_ID || undefined;
  if (plan === "proplus") return process.env.DODO_PROPLUS_PRODUCT_ID || undefined;
  return undefined;
}

export function planForProduct(productId: string | undefined): PlanID | undefined {
  if (!productId) return undefined;
  if (productId === process.env.DODO_PRO_PRODUCT_ID) return "pro";
  if (productId === process.env.DODO_PROPLUS_PRODUCT_ID) return "proplus";
  return undefined;
}

export class BillingError extends Error {}

/** Who is buying: the email they gave in the app, and their computer's ID (see device-id.js). */
export interface Buyer {
  email?: string;
  device?: string;
}

const EMAIL = /^[^\s@]{1,64}@[^\s@]+\.[^\s@]{2,}$/;
const DEVICE = /^[0-9a-f]{64}$/;

/** A plausible email, trimmed and lowercased; undefined otherwise. */
export function cleanEmail(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const email = value.trim().toLowerCase();
  return email.length <= 254 && EMAIL.test(email) ? email : undefined;
}

/** A Dodo checkout link for this install and plan. */
export async function createCheckout(installId: string, plan: PlanID, fetchImpl: Fetch = fetch, buyer: Buyer = {}): Promise<string> {
  const key = process.env.DODO_API_KEY;
  const product = productFor(plan);
  if (!key || !product) throw new BillingError("Payments aren't set up yet.");
  const device = buyer.device && DEVICE.test(buyer.device) ? buyer.device : undefined;
  const payload = (withEmail: boolean) => JSON.stringify({
    product_cart: [{ product_id: product, quantity: 1 }],
    // Filled in on Dodo's page, so the buyer doesn't type it twice.
    ...(withEmail && buyer.email ? { customer: { email: buyer.email } } : {}),
    metadata: { install_id: installId, plan, ...(device ? { device_id: device } : {}) },
    return_url: process.env.CHECKOUT_RETURN_URL || "https://notchman.app/thanks",
  });
  let lastStatus = 0;
  for (const base of dodoBaseURLs()) {
    const post = (withEmail: boolean) => fetchImpl(`${base}/checkouts`, {
      method: "POST",
      headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
      body: payload(withEmail),
      signal: AbortSignal.timeout(10_000),
    });
    let response = await post(true);
    if (buyer.email && (response.status === 400 || response.status === 422)) {
      // Never lose a sale over the pre-filled email: Dodo asks for it on its page anyway.
      console.warn("dodo checkout: pre-filled email not accepted, opening without it", response.status);
      response = await post(false);
    }
    const body = await response.json().catch(() => ({})) as { checkout_url?: string; message?: string };
    if (response.ok && body.checkout_url) {
      detected = base;
      return body.checkout_url;
    }
    lastStatus = response.status;
    lastFailure = `${base === LIVE ? "live" : "test"} ${response.status} ${JSON.stringify(body).slice(0, 200)}`;
    console.error("dodo checkout failed", base, response.status, JSON.stringify(body).slice(0, 300));
    // A key or product from the other mode answers 401/403/404: try the other.
    if (![401, 403, 404].includes(response.status)) break;
  }
  throw new BillingError(lastStatus === 401 ? "Payments aren't set up yet." : "Checkout couldn't be opened. Please try again.");
}

/**
 * Standard Webhooks signature check: HMAC-SHA256 of `id.timestamp.body` with
 * the base64 key after `whsec_`, compared with each `v1,<base64>` signature;
 * timestamps more than 5 minutes off are rejected (replays).
 */
export function verifyWebhook(rawBody: string, headers: Record<string, string | undefined>, secret: string,
                              now = Date.now()): boolean {
  const lower = Object.fromEntries(Object.entries(headers).map(([k, v]) => [k.toLowerCase(), v]));
  const id = lower["webhook-id"];
  const timestamp = lower["webhook-timestamp"];
  const signatures = lower["webhook-signature"];
  if (!id || !timestamp || !signatures || !secret) return false;
  const seconds = Number(timestamp);
  if (!Number.isFinite(seconds) || Math.abs(now / 1000 - seconds) > 300) return false;
  const key = Buffer.from(secret.startsWith("whsec_") ? secret.slice(6) : secret, "base64");
  const expected = createHmac("sha256", key).update(`${id}.${timestamp}.${rawBody}`).digest();
  return signatures.split(" ").some((entry) => {
    const [version, signature] = entry.split(",");
    if (version !== "v1" || !signature) return false;
    const given = Buffer.from(signature, "base64");
    return given.length === expected.length && timingSafeEqual(given, expected);
  });
}

export interface StoredSubscription {
  subscriptionId: string;
  plan: PlanID;
  status: string;
  /** Paid until (ISO). */
  paidUntil: string;
  updatedAt: string;
  /** The customer's email at Dodo, for the owner (receipts, help). */
  email?: string;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** The server's name for an install ("install:<uuid>"), from either form; undefined if it isn't one. */
export function installKey(id: unknown): string | undefined {
  if (typeof id !== "string") return undefined;
  const bare = id.trim().replace(/^install:/i, "");
  return UUID.test(bare) ? `install:${bare.toLowerCase()}` : undefined;
}

export const subscriptionKey = (installId: string) => `dodo_${installKey(installId) ?? installId}`;

/** Active desktop subscriptions by plan (for the owner's usage email), or undefined. */
export async function dodoSubscribers(fetchImpl: Fetch = fetch): Promise<{ pro: number; proplus: number } | undefined> {
  const key = process.env.DODO_API_KEY;
  if (!key) return undefined;
  for (const base of dodoBaseURLs()) {
    try {
      const counts = { pro: 0, proplus: 0 };
      for (let page = 0; page < 20; page++) {
        const response = await fetchImpl(`${base}/subscriptions?status=active&page_size=100&page_number=${page}`, {
          headers: { Authorization: `Bearer ${key}` }, signal: AbortSignal.timeout(8_000),
        });
        if (!response.ok) throw new Error(`dodo ${response.status}`);
        const body = await response.json() as { items?: { product_id?: string; status?: string }[] };
        const items = body.items ?? [];
        for (const item of items) {
          const plan = planForProduct(item.product_id);
          if (plan === "pro" || plan === "proplus") counts[plan]++;
        }
        if (items.length < 100) return counts;
      }
      return counts;
    } catch {
      // try the other mode
    }
  }
  return undefined;
}

/** How Dodo answers this key in each mode (HTTP status only), for /status. */
export async function dodoKeyCheck(fetchImpl: Fetch = fetch): Promise<Record<string, number | string>> {
  const key = process.env.DODO_API_KEY;
  if (!key) return { live: "no key", test: "no key" };
  const check = async (base: string, path = "/products?page_size=1") => {
    try {
      const response = await fetchImpl(`${base}${path}`, {
        headers: { Authorization: `Bearer ${key}` },
        signal: AbortSignal.timeout(5_000),
      });
      return response.status;
    } catch {
      return "unreachable";
    }
  };
  const [live, test, pro, proplus] = await Promise.all([
    check(LIVE), check(TEST),
    check(LIVE, `/products/${process.env.DODO_PRO_PRODUCT_ID}`), check(LIVE, `/products/${process.env.DODO_PROPLUS_PRODUCT_ID}`),
  ]);
  // Product IDs and names aren't secret: lets the check show which live products exist.
  let liveProducts = "unknown";
  try {
    const response = await fetchImpl(`${LIVE}/products?page_size=20`, { headers: { Authorization: `Bearer ${key}` }, signal: AbortSignal.timeout(5_000) });
    const body = await response.json() as { items?: { product_id?: string; name?: string }[] };
    liveProducts = (body.items ?? []).map((p) => `${p.name}=${p.product_id}`).join(", ") || "none";
  } catch { /* leave unknown */ }
  return { live, test, liveProProduct: pro, liveProPlusProduct: proplus, liveProducts, lastCheckoutFailure: lastFailure ?? "none" };
}

/** What a webhook did, for logs, owner emails and tests. */
export interface WebhookOutcome {
  /** "saved", "linked" (saved via the payment's link), "unlinked" (paid, but no install to give it to), "ignored". */
  result: "saved" | "linked" | "unlinked" | "ignored";
  type: string;
  plan?: PlanID;
  status?: string;
  subscriptionId?: string;
  installId?: string;
  /** The customer's email, for the owner's "new subscriber" email. */
  email?: string;
  /** Simulated by our own end-to-end check (no owner email). */
  test?: boolean;
}

const linkKey = (subscriptionId: string) => `dodosub_${subscriptionId}`;
const pendingKey = (subscriptionId: string) => `dodopending_${subscriptionId}`;

function installFrom(data: Record<string, unknown>): string | undefined {
  return installKey(((data.metadata ?? {}) as Record<string, unknown>).install_id);
}

/** The buyer's computer ID from the checkout's metadata, if it's one. */
function deviceFrom(data: Record<string, unknown>): string | undefined {
  const value = ((data.metadata ?? {}) as Record<string, unknown>).device_id;
  return typeof value === "string" && DEVICE.test(value) ? value : undefined;
}

/** A computer's name in the subscription records: Pro follows the computer, so a reinstall keeps it. */
export const deviceAccount = (device: string) => `device:${device}`;

/** Saves a subscription for an install (and its computer): the app sees the plan on its next /usage. */
export async function saveSubscription(store: QuotaStore, installId: string, record: StoredSubscription, now = new Date(),
                                       device?: string) {
  await store.putRecord(subscriptionKey(installId), record as unknown as Record<string, unknown>, days(400, now));
  await store.putRecord(linkKey(record.subscriptionId), { installId, ...(device ? { device } : {}) }, days(400, now));
  if (device) await store.putRecord(subscriptionKey(deviceAccount(device)), record as unknown as Record<string, unknown>, days(400, now));
}

export function subscriptionRecord(data: Record<string, unknown>, fallbackStatus: string, now = new Date()): StoredSubscription | null {
  const plan = planForProduct(typeof data.product_id === "string" ? data.product_id : undefined);
  const subscriptionId = typeof data.subscription_id === "string" ? data.subscription_id : undefined;
  if (!plan || !subscriptionId) return null;
  const nextBilling = typeof data.next_billing_date === "string" ? data.next_billing_date : undefined;
  const email = cleanEmail(((data.customer ?? {}) as Record<string, unknown>).email);
  return {
    subscriptionId,
    plan,
    ...(email ? { email } : {}),
    status: typeof data.status === "string" ? data.status : fallbackStatus,
    // A day of grace after the billing date, so a renewal that's a little late
    // doesn't lock anyone out.
    paidUntil: new Date((nextBilling ? Date.parse(nextBilling) : now.getTime()) + 86_400_000).toISOString(),
    updatedAt: now.toISOString(),
  };
}

/**
 * Handles a verified Dodo webhook. The install ID comes from the checkout's
 * metadata; if a subscription event arrives without it, the subscription is
 * kept as pending and linked when a payment event (or the owner, with
 * Actions → Link payment) names the install.
 */
export async function applyWebhook(event: { type?: string; data?: Record<string, unknown> }, store: QuotaStore,
                                   now = new Date()): Promise<WebhookOutcome> {
  const type = event.type ?? "";
  const data = event.data ?? {};
  const test = ((data.metadata ?? {}) as Record<string, unknown>).notchman_test === "true";
  const subscriptionId = typeof data.subscription_id === "string" ? data.subscription_id : undefined;
  let installId = installFrom(data);
  let device = deviceFrom(data);

  // A payment for a subscription links the two (and saves one that was waiting).
  if (type.startsWith("payment.")) {
    if (!subscriptionId || !installId) return { result: "ignored", type };
    await store.putRecord(linkKey(subscriptionId), { installId, ...(device ? { device } : {}) }, days(400, now));
    const waiting = await store.getRecord(pendingKey(subscriptionId)) as unknown as StoredSubscription | null;
    if (!waiting) return { result: "ignored", type, subscriptionId, installId, test };
    await saveSubscription(store, installId, waiting, now, device);
    return { result: "linked", type, plan: waiting.plan, status: waiting.status, subscriptionId, installId, test };
  }

  if (!type.startsWith("subscription.")) return { result: "ignored", type };
  const record = subscriptionRecord(data, type.slice("subscription.".length), now);
  if (!record) return { result: "ignored", type, subscriptionId };
  if (!installId || !device) {
    const link = await store.getRecord(linkKey(record.subscriptionId));
    if (!installId && typeof link?.installId === "string") installId = link.installId;
    if (!device && typeof link?.device === "string" && DEVICE.test(link.device)) device = link.device;
  }
  if (!installId) {
    await store.putRecord(pendingKey(record.subscriptionId), record as unknown as Record<string, unknown>, days(400, now));
    return { result: "unlinked", type, plan: record.plan, status: record.status, subscriptionId: record.subscriptionId, test };
  }
  await saveSubscription(store, installId, record, now, device);
  return { result: "saved", type, plan: record.plan, status: record.status, subscriptionId: record.subscriptionId, installId,
           email: record.email, test };
}

/** Owner fix: gives a paid subscription (looked up at Dodo) to an install. */
export async function linkSubscription(installId: string, subscriptionId: string, store: QuotaStore,
                                       fetchImpl: Fetch = fetch, now = new Date()): Promise<StoredSubscription> {
  const key = process.env.DODO_API_KEY;
  if (!key) throw new BillingError("Payments aren't set up yet.");
  const install = installKey(installId);
  if (!install) throw new BillingError("That isn't an install ID (Notchman → Settings → Privacy).");
  for (const base of dodoBaseURLs()) {
    const response = await fetchImpl(`${base}/subscriptions/${encodeURIComponent(subscriptionId)}`, {
      headers: { Authorization: `Bearer ${key}` }, signal: AbortSignal.timeout(10_000),
    });
    if (!response.ok) continue;
    const record = subscriptionRecord(await response.json() as Record<string, unknown>, "active", now);
    if (!record) throw new BillingError("That subscription isn't for Pro or Pro+.");
    await saveSubscription(store, install, record, now);
    return record;
  }
  throw new BillingError("Dodo doesn't know that subscription.");
}

/** The desktop plan Dodo has for this install, if any. */
export async function dodoEntitlement(installId: string, store: QuotaStore, now = Date.now()):
  Promise<{ plan: PlanID; accountKey: string } | null> {
  const record = await store.getRecord(subscriptionKey(installId)) as unknown as StoredSubscription | null;
  if (!record) return null;
  // Active, renewing or cancelled-but-paid: entitled until the paid date.
  const ended = ["failed", "expired", "on_hold", "paused"].includes(record.status);
  if (ended || Date.parse(record.paidUntil) < now) return null;
  return { plan: record.plan, accountKey: `dodo:${record.subscriptionId}` };
}
