/**
 * Notchman API on AWS Lambda (Function URL).
 *
 *   POST /tldr   { text, length?, transactions? } → { summary, audio?, audioFormat?, plan, used, limit, remaining }
 *   POST /usage  { transactions? }                → { plan, used, limit, remaining }
 *   POST /speak  { text, previousText?, nextText? } → { audio, audioFormat, charactersUsed, characterLimit }
 *   POST /account { action: signin | refresh | delete, identityToken?, name?, transactions? } → { signedIn, plan }
 *
 * Header: `X-Notchman-Install: <install UUID>`. Errors are
 * `{ code, message, details? }` with a matching HTTP status.
 *
 * Message text is never stored or logged.
 */
import type { APIGatewayProxyEventV2, APIGatewayProxyStructuredResultV2 } from "aws-lambda";
import { createHmac, timingSafeEqual } from "node:crypto";
import { AuthError, installIdFrom } from "./auth.js";
import { linkInstall, recordBetaSignup, recordSignup } from "./signups.js";
import { alertOnce, snsNotify, usageCheck, usageReport, type Notify } from "./alerts.js";
import { applyWebhook, dodoKeyCheck, dodoSubscribers, linkSubscription, verifyWebhook, type WebhookOutcome } from "./billing.js";
import { DynamoQuotaStore } from "./dynamo.js";
import { days, type QuotaStore } from "./quota.js";
import { handleAccount, handleCheckout, handleSpeak, handleTLDR, handleUsage, type Dependencies, type ErrorCode, type Result } from "./handlers.js";
import { configuredSecrets, loadSecrets } from "./secrets.js";
import { countFunnel, DOWNLOAD_FILES, recordAppEvents, recordAppHello, recordDownload, recordSiteEvent, siteReport, siteStats, type SiteEvent } from "./site-analytics.js";
import { elevenLabsRemaining } from "./speech.js";

const STATUS: Record<ErrorCode, number> = {
  "invalid-argument": 400,
  "resource-exhausted": 429,
  unavailable: 503,
  internal: 500,
};

function json(status: number, body: unknown): APIGatewayProxyStructuredResultV2 {
  return { statusCode: status, headers: { "content-type": "application/json" }, body: JSON.stringify(body) };
}

let store: DynamoQuotaStore | undefined;

export interface LambdaOverrides {
  // deps.notify replaces the owner email in tests.
  deps?: Partial<Dependencies>;
  authenticate?: (headers: Record<string, string | undefined>) => Promise<string>;
}

async function authenticate(headers: Record<string, string | undefined>): Promise<string> {
  return installIdFrom(headers);
}

/** The desktop app's hashed computer ID (64 hex characters), if it sent one. */
function deviceFrom(headers: Record<string, string | undefined>): string | undefined {
  const value = headers["x-notchman-device"]?.trim().toLowerCase();
  return value && /^[0-9a-f]{64}$/.test(value) ? value : undefined;
}

export async function route(event: APIGatewayProxyEventV2, overrides: LambdaOverrides = {}): Promise<APIGatewayProxyStructuredResultV2> {
  const path = event.rawPath.replace(/\/+$/, "");
  // notchman.app's download links: count, then send the browser to the installer.
  const download = /^\/dl\/([a-z-]+)$/.exec(path);
  if (download && (event.requestContext.http.method === "GET" || event.requestContext.http.method === "HEAD")) {
    const headers = event.headers ?? {};
    // One line per download hit (no IP), to tell people from checkers in the logs.
    console.log("download hit", JSON.stringify({ platform: download[1], method: event.requestContext.http.method,
      fetchMode: headers["sec-fetch-mode"] ?? null, referer: (headers.referer ?? "").slice(0, 60), ua: (headers["user-agent"] ?? "").slice(0, 120) }));
    const file = DOWNLOAD_FILES[download[1]];
    if (!file) return json(404, { code: "invalid-argument", message: "Not found." });
    store ??= new DynamoQuotaStore(process.env.QUOTA_TABLE ?? "");
    if (event.requestContext.http.method === "GET") {
      // A person clicking the link sends the browser's navigation headers
      // (or comes from notchman.app); link checkers and scanners don't.
      const automated = !headers["sec-fetch-mode"] && !/notchman\.app/.test(headers.referer ?? "");
      await recordDownload(overrides.deps?.store ?? store, download[1], {
        ip: event.requestContext.http.sourceIp, userAgent: headers["user-agent"], pepper: process.env.DODO_WEBHOOK_SECRET, automated,
        referer: headers.referer, source: event.queryStringParameters?.s,
      }).catch((error) => console.warn("download count failed", error instanceof Error ? error.message : error));
    }
    const base = (process.env.DOWNLOADS_URL ?? "https://dy7adwloxsruv.cloudfront.net").replace(/\/+$/, "");
    return { statusCode: 302, headers: { location: `${base}/latest/${file}`, "cache-control": "no-store" }, body: "" };
  }
  if (event.requestContext.http.method !== "POST") return json(405, { code: "invalid-argument", message: "Use POST." });
  // Dodo Payments calls this (signed), not the apps.
  if (path === "/dodo-webhook") return dodoWebhook(event, overrides);
  // notchman.app's cookieless analytics (site-analytics.ts).
  if (path === "/event") return siteEvent(event, overrides);
  // The owner's dashboard: the website, downloads and app numbers as JSON.
  if (path === "/stats") return stats(event, overrides);
  // The email asked on notchman.app before a download (signups.ts).
  if (path === "/signup") return signup(event, overrides);
  // "Join the iPhone beta" on notchman.app (signups.ts).
  if (path === "/beta") return betaSignup(event, overrides);
  // Which keys are set up (yes/no only), for the server check.
  if (path === "/status") {
    return json(200, { keys: configuredSecrets(), region: process.env.AWS_REGION ?? null, dodo: await dodoKeyCheck() });
  }
  if (path !== "/tldr" && path !== "/usage" && path !== "/speak" && path !== "/checkout" && path !== "/hello" && path !== "/events"
      && path !== "/account") {
    return json(404, { code: "invalid-argument", message: "Not found." });
  }

  let userId: string;
  try {
    userId = await (overrides.authenticate ?? authenticate)(event.headers ?? {});
  } catch (error) {
    if (error instanceof AuthError) {
      // Visible in CloudWatch; no tokens or message text are logged.
      console.warn("auth failed", error.message);
      return json(401, { code: "unauthenticated", message: error.message });
    }
    throw error;
  }

  let data: unknown = {};
  try {
    const raw = event.body ? (event.isBase64Encoded ? Buffer.from(event.body, "base64").toString("utf8") : event.body) : "{}";
    data = JSON.parse(raw);
  } catch {
    return json(400, { code: "invalid-argument", message: "Body must be JSON." });
  }

  store ??= new DynamoQuotaStore(process.env.QUOTA_TABLE ?? "");
  const deps: Dependencies = {
    store,
    betaMonthlyTLDRs: Number(process.env.BETA_MONTHLY_TLDRS ?? 0),
    betaMonthlyVoiceCharacters: Number(process.env.BETA_MONTHLY_VOICE_CHARACTERS ?? 0),
    freeTrialVoiceCharacters: Number(process.env.FREE_TRIAL_VOICE_CHARACTERS ?? 0),
    voiceReserveCredits: Number(process.env.VOICE_RESERVE_CREDITS ?? 0),
    standardInstallMonthlyCharacters: Number(process.env.STANDARD_INSTALL_MONTHLY_CHARACTERS ?? 40_000),
    standardMonthlyCharacters: Number(process.env.STANDARD_MONTHLY_CHARACTERS ?? 0),
    globalDailyTLDRs: Number(process.env.GLOBAL_DAILY_TLDRS ?? 1_000),
    globalDailyVoiceCharacters: Number(process.env.GLOBAL_DAILY_VOICE_CHARACTERS ?? 400_000),
    freeMonthlyVoiceCharacters: Number(process.env.FREE_MONTHLY_VOICE_CHARACTERS ?? 0),
    ipMonthlyTLDRs: Number(process.env.IP_MONTHLY_TLDRS ?? 0),
    ipMonthlyVoiceCharacters: Number(process.env.IP_MONTHLY_VOICE_CHARACTERS ?? 0),
    device: deviceFrom(event.headers ?? {}),
    clientIp: event.requestContext.http.sourceIp || undefined,
    ...overrides.deps,
  };
  if (path === "/events") {
    // The apps' anonymous usage statistics (see site-analytics.ts).
    const counted = await recordAppEvents(deps.store, userId, (data ?? {}) as Record<string, unknown>)
      .catch((error) => { console.warn("events failed", error instanceof Error ? error.message : error); return 0; });
    return json(200, { ok: true, counted });
  }
  if (path === "/hello") {
    // The desktop app's daily hello: counts installs and opens (see site-analytics.ts),
    // and links a new install to the email given before its download (signups.ts).
    const info = (data ?? {}) as Record<string, unknown>;
    const hello = await recordAppHello(deps.store, userId, info)
      .catch((error) => { console.warn("hello failed", error instanceof Error ? error.message : error); return null; });
    if (hello?.new) {
      await linkInstall(deps.store, userId, { ip: deps.clientIp, pepper: process.env.DODO_WEBHOOK_SECRET, device: deps.device,
                                               platform: info.platform, version: info.version })
        .catch((error) => console.warn("signup link failed", error instanceof Error ? error.message : error));
    }
    return json(200, { ok: true });
  }
  const result: Result = path === "/usage" ? await handleUsage(userId, data, deps)
    : path === "/speak" ? await handleSpeak(userId, data, deps)
    : path === "/checkout" ? await handleCheckout(userId, data, deps)
    : path === "/account" ? await handleAccount(userId, data, deps)
    : await handleTLDR(userId, data, deps);
  return result.ok ? json(200, result.body)
                   : json(STATUS[result.code], { code: result.code, message: result.message, details: result.details });
}

async function signup(event: APIGatewayProxyEventV2, overrides: LambdaOverrides): Promise<APIGatewayProxyStructuredResultV2> {
  let body: Record<string, unknown> = {};
  try {
    const raw = event.body ? (event.isBase64Encoded ? Buffer.from(event.body, "base64").toString("utf8") : event.body) : "{}";
    if (raw.length < 2000) body = JSON.parse(raw);
  } catch { /* ignore junk */ }
  store ??= new DynamoQuotaStore(process.env.QUOTA_TABLE ?? "");
  const saved = await recordSignup(overrides.deps?.store ?? store, body, {
    ip: event.requestContext.http.sourceIp, pepper: process.env.DODO_WEBHOOK_SECRET,
  }).catch((error) => { console.warn("signup failed", error instanceof Error ? error.message : error); return false; });
  return { statusCode: saved ? 204 : 400, headers: { "access-control-allow-origin": "https://notchman.app" }, body: "" };
}

async function betaSignup(event: APIGatewayProxyEventV2, overrides: LambdaOverrides): Promise<APIGatewayProxyStructuredResultV2> {
  let body: Record<string, unknown> = {};
  try {
    const raw = event.body ? (event.isBase64Encoded ? Buffer.from(event.body, "base64").toString("utf8") : event.body) : "{}";
    if (raw.length < 2000) body = JSON.parse(raw);
  } catch { /* ignore junk */ }
  store ??= new DynamoQuotaStore(process.env.QUOTA_TABLE ?? "");
  const target = overrides.deps?.store ?? store;
  const saved = await recordBetaSignup(target, body, { ip: event.requestContext.http.sourceIp, pepper: process.env.DODO_WEBHOOK_SECRET })
    .catch((error) => { console.warn("beta signup failed", error instanceof Error ? error.message : error); return null; });
  if (saved?.new) {
    const r = saved.record;
    const device = ({ "iphone-island": "iPhone with Dynamic Island", "iphone-other": "another iPhone", ipad: "iPad", android: "Android" } as Record<string, string>)[String(r.device)] ?? "another device";
    await alertOnce(target, `beta_${r.email}`, `Notchman: ${r.email} wants the iPhone beta`,
      `${r.email} asked to join the iPhone beta on notchman.app.\n\nDevice: ${device}\nWants to listen to: ${r.wants || "(not said)"}\nCame from: ${r.source}\n\n` +
      "Invite them in App Store Connect → TestFlight → External testers.",
      days(400, new Date()), overrides.deps?.notify).catch(() => {});
  }
  return { statusCode: saved ? 204 : 400, headers: { "access-control-allow-origin": "https://notchman.app" }, body: "" };
}

async function siteEvent(event: APIGatewayProxyEventV2, overrides: LambdaOverrides): Promise<APIGatewayProxyStructuredResultV2> {
  let body: SiteEvent = {};
  try {
    const raw = event.body ? (event.isBase64Encoded ? Buffer.from(event.body, "base64").toString("utf8") : event.body) : "{}";
    if (raw.length < 2000) body = JSON.parse(raw);
  } catch { /* ignore junk */ }
  store ??= new DynamoQuotaStore(process.env.QUOTA_TABLE ?? "");
  await recordSiteEvent(overrides.deps?.store ?? store, body, {
    ip: event.requestContext.http.sourceIp,
    userAgent: event.headers?.["user-agent"],
    pepper: process.env.DODO_WEBHOOK_SECRET,
  }).catch((error) => console.warn("site event failed", error instanceof Error ? error.message : error));
  return { statusCode: 204, headers: { "access-control-allow-origin": "https://notchman.app" }, body: "" };
}

/** Tells the owner about new, cancelled and unmatched subscriptions. */
async function ownerEmail(outcome: WebhookOutcome, target: QuotaStore, notify?: Notify) {
  if (outcome.test || !outcome.subscriptionId || !outcome.plan) return;
  const name = outcome.plan === "proplus" ? "Pro+ ($9.99/month)" : "Pro ($4.99/month)";
  const now = new Date();
  if (outcome.result === "unlinked") {
    await alertOnce(target, `unlinked_${outcome.subscriptionId}`, "Notchman: a payment needs linking",
      `Someone subscribed to Notchman ${name}, but Dodo's message didn't say which computer it was for ` +
      `(subscription ${outcome.subscriptionId}). It usually links itself within a minute when Dodo sends the payment.\n\n` +
      "If the customer writes that they paid but still see Free: ask for their Install ID (Notchman → Settings → Privacy), " +
      "then run GitHub → Actions → Link payment with the Install ID and this subscription ID.",
      days(400, now), notify);
  } else if (outcome.type === "subscription.active" && outcome.status === "active") {
    await alertOnce(target, `new_${outcome.subscriptionId}`, `Notchman: new ${outcome.plan === "proplus" ? "Pro+" : "Pro"} subscriber`,
      `${outcome.email ?? "Someone"} just subscribed to Notchman ${name} on the desktop app. Their plan is already active in the app.\n\n` +
      "Each paying user can use up to 25,000 (Pro) or 60,000 (Pro+) ElevenLabs characters a month: " +
      "top up at https://elevenlabs.io/app/subscription when your revenue allows.",
      days(400, now), notify);
  } else if (outcome.type === "subscription.cancelled") {
    await alertOnce(target, `cancelled_${outcome.subscriptionId}`, "Notchman: a subscriber cancelled",
      `A Notchman ${name} subscriber cancelled. They keep their plan until the end of the period they paid for.`,
      days(400, now), notify);
  }
}

async function dodoWebhook(event: APIGatewayProxyEventV2, overrides: LambdaOverrides): Promise<APIGatewayProxyStructuredResultV2> {
  const raw = event.body ? (event.isBase64Encoded ? Buffer.from(event.body, "base64").toString("utf8") : event.body) : "";
  const secret = process.env.DODO_WEBHOOK_SECRET ?? "";
  if (!verifyWebhook(raw, event.headers ?? {}, secret)) {
    console.warn("dodo webhook: bad signature");
    return json(401, { code: "unauthenticated", message: "Bad signature." });
  }
  let payload: { type?: string; data?: Record<string, unknown> };
  try {
    payload = JSON.parse(raw);
  } catch {
    return json(400, { code: "invalid-argument", message: "Body must be JSON." });
  }
  store ??= new DynamoQuotaStore(process.env.QUOTA_TABLE ?? "");
  const target = overrides.deps?.store ?? store;
  const outcome = await applyWebhook(payload, target);
  // The shape (never the values) helps if Dodo ever changes its payloads.
  console.log("dodo webhook", JSON.stringify({ ...outcome, installId: undefined, dataKeys: Object.keys(payload.data ?? {}).sort() }));
  await ownerEmail(outcome, target, overrides.deps?.notify);
  // The dashboard's payment_completed: once per subscription.
  if (!outcome.test && outcome.subscriptionId && outcome.plan && outcome.type === "subscription.active" && outcome.status === "active") {
    const first = await target.consume(`paidcount_${outcome.subscriptionId}`, 1, days(400, new Date()));
    if (first.allowed) {
      await countFunnel(target, "payment_completed");
      await countFunnel(target, `payment_completed_${outcome.plan}`);
    }
  }
  return json(200, { received: true });
}

/** The dashboard's password: derived from a server secret, emailed to the owner by the `dashboard-token` task. */
export function dashboardToken(): string | undefined {
  const secret = process.env.DODO_WEBHOOK_SECRET || process.env.GROQ_API_KEY;
  return secret ? createHmac("sha256", secret).update("notchman-dashboard").digest("hex").slice(0, 32) : undefined;
}

const CORS = { "access-control-allow-origin": "*" };

/** POST /stats with the body `{ "token": "…" }` (sent as text/plain so browsers don't preflight). */
async function stats(event: APIGatewayProxyEventV2, overrides: LambdaOverrides): Promise<APIGatewayProxyStructuredResultV2> {
  let token = "";
  try {
    const raw = event.body ? (event.isBase64Encoded ? Buffer.from(event.body, "base64").toString("utf8") : event.body) : "{}";
    token = String((JSON.parse(raw) as { token?: unknown }).token ?? "");
  } catch {
    // an empty token fails below
  }
  const expected = dashboardToken();
  const a = Buffer.from(token), b = Buffer.from(expected ?? "");
  if (!expected || a.length !== b.length || !timingSafeEqual(a, b)) {
    return { ...json(401, { code: "unauthenticated", message: "Wrong token." }), headers: { "content-type": "application/json", ...CORS } };
  }
  store ??= new DynamoQuotaStore(process.env.QUOTA_TABLE ?? "");
  const data = await siteStats(overrides.deps?.store ?? store, new Date());
  return { statusCode: 200, headers: { "content-type": "application/json", "cache-control": "no-store", ...CORS }, body: JSON.stringify(data) };
}

type Task = { warm: true } | { task: "usage-check" | "usage-report" | "test-alert" | "link" | "site-report" | "site-report-email" | "dashboard-token"; installId?: string; subscriptionId?: string };

/** The owner's hourly usage check (template.yaml), and by hand from GitHub Actions. */
async function runTask(task: string, input: { installId?: string; subscriptionId?: string } = {}): Promise<APIGatewayProxyStructuredResultV2> {
  store ??= new DynamoQuotaStore(process.env.QUOTA_TABLE ?? "");
  if (task === "link") {
    try {
      const record = await linkSubscription(String(input.installId ?? "").trim(), String(input.subscriptionId ?? "").trim(), store);
      return json(200, { linked: `${record.plan} ${record.status}, paid until ${record.paidUntil.slice(0, 10)}` });
    } catch (error) {
      return json(400, { error: error instanceof Error ? error.message : String(error) });
    }
  }
  const options = {
    budget: Number(process.env.ELEVENLABS_MONTHLY_BUDGET ?? 27_000),
    balance: () => elevenLabsRemaining(),
    subscribers: () => dodoSubscribers(),
  };
  if (task === "usage-check") return json(200, await usageCheck(store, new Date(), options));
  if (task === "dashboard-token") {
    const token = dashboardToken();
    if (!token) return json(500, { error: "No server secret to derive the token from." });
    await snsNotify("Notchman dashboard password", `Your dashboard password (keep it private):\n\n${token}`);
    return json(200, { emailed: true });
  }
  if (task === "site-report" || task === "site-report-email") {
    const text = await siteReport(store, new Date());
    if (task === "site-report-email") await snsNotify("Notchman: your website this week", text);
    return json(200, { report: text });
  }
  const report = await usageReport(store, new Date(), options);
  if (task === "test-alert") {
    await snsNotify("Notchman alerts are on", `You'll get an email here when the Notchman voice nears your ElevenLabs budget or free users hit the daily cap.\n\nRight now:\n${report.text}`);
  }
  return json(200, { report: report.text });
}

export async function handler(event: APIGatewayProxyEventV2 | Task): Promise<APIGatewayProxyStructuredResultV2> {
  try {
    await loadSecrets();
    if (!("requestContext" in event)) {
      if ("task" in event) return await runTask(event.task, event);
      // The keep-warm schedule (template.yaml): secrets loaded, nothing else to do.
      return json(200, { warm: true });
    }
    return await route(event);
  } catch (error) {
    console.error("request failed", error instanceof Error ? error.message : error);
    return json(500, { code: "internal", message: "Something went wrong. Please try again." });
  }
}
