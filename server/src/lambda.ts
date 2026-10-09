/**
 * Notchman API on AWS Lambda (Function URL).
 *
 *   POST /tldr   { text, length?, transactions? } → { summary, audio?, audioFormat?, plan, used, limit, remaining }
 *   POST /usage  { transactions? }                → { plan, used, limit, remaining }
 *   POST /speak  { text, previousText?, nextText? } → { audio, audioFormat, charactersUsed, characterLimit }
 *
 * Header: `X-Notchman-Install: <install UUID>`. Errors are
 * `{ code, message, details? }` with a matching HTTP status.
 *
 * Message text is never stored or logged.
 */
import type { APIGatewayProxyEventV2, APIGatewayProxyStructuredResultV2 } from "aws-lambda";
import { AuthError, installIdFrom } from "./auth.js";
import { alertOnce, snsNotify, usageCheck, usageReport, type Notify } from "./alerts.js";
import { applyWebhook, dodoKeyCheck, dodoSubscribers, linkSubscription, verifyWebhook, type WebhookOutcome } from "./billing.js";
import { DynamoQuotaStore } from "./dynamo.js";
import { days, type QuotaStore } from "./quota.js";
import { handleCheckout, handleSpeak, handleTLDR, handleUsage, type Dependencies, type ErrorCode, type Result } from "./handlers.js";
import { configuredSecrets, loadSecrets } from "./secrets.js";
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
  if (event.requestContext.http.method !== "POST") return json(405, { code: "invalid-argument", message: "Use POST." });
  const path = event.rawPath.replace(/\/+$/, "");
  // Dodo Payments calls this (signed), not the apps.
  if (path === "/dodo-webhook") return dodoWebhook(event, overrides);
  // Which keys are set up (yes/no only), for the server check.
  if (path === "/status") {
    return json(200, { keys: configuredSecrets(), region: process.env.AWS_REGION ?? null, dodo: await dodoKeyCheck() });
  }
  if (path !== "/tldr" && path !== "/usage" && path !== "/speak" && path !== "/checkout") {
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
    betaDailyTLDRs: Number(process.env.BETA_DAILY_TLDRS ?? 0),
    betaDailyVoiceCharacters: Number(process.env.BETA_DAILY_VOICE_CHARACTERS ?? 0),
    freeTrialVoiceCharacters: Number(process.env.FREE_TRIAL_VOICE_CHARACTERS ?? 0),
    voiceReserveCredits: Number(process.env.VOICE_RESERVE_CREDITS ?? 0),
    standardDailyCharacters: Number(process.env.STANDARD_DAILY_CHARACTERS ?? 20_000),
    standardMonthlyCharacters: Number(process.env.STANDARD_MONTHLY_CHARACTERS ?? 0),
    globalDailyTLDRs: Number(process.env.GLOBAL_DAILY_TLDRS ?? 1_000),
    globalDailyVoiceCharacters: Number(process.env.GLOBAL_DAILY_VOICE_CHARACTERS ?? 400_000),
    ipDailyTLDRs: Number(process.env.IP_DAILY_TLDRS ?? 0),
    ipDailyVoiceCharacters: Number(process.env.IP_DAILY_VOICE_CHARACTERS ?? 0),
    device: deviceFrom(event.headers ?? {}),
    clientIp: event.requestContext.http.sourceIp || undefined,
    ...overrides.deps,
  };
  const result: Result = path === "/usage" ? await handleUsage(userId, data, deps)
    : path === "/speak" ? await handleSpeak(userId, data, deps)
    : path === "/checkout" ? await handleCheckout(userId, data, deps)
    : await handleTLDR(userId, data, deps);
  return result.ok ? json(200, result.body)
                   : json(STATUS[result.code], { code: result.code, message: result.message, details: result.details });
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
      `Someone just subscribed to Notchman ${name} on the desktop app. Their plan is already active in the app.\n\n` +
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
  return json(200, { received: true });
}

type Task = { warm: true } | { task: "usage-check" | "usage-report" | "test-alert" | "link"; installId?: string; subscriptionId?: string };

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
