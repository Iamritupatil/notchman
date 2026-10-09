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
import { snsNotify, usageCheck, usageReport } from "./alerts.js";
import { applyWebhook, dodoKeyCheck, dodoSubscribers, verifyWebhook } from "./billing.js";
import { DynamoQuotaStore } from "./dynamo.js";
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
  const outcome = await applyWebhook(payload, overrides.deps?.store ?? store);
  console.log("dodo webhook", outcome);
  return json(200, { received: true });
}

type Task = { warm: true } | { task: "usage-check" | "usage-report" | "test-alert" };

/** The owner's hourly usage check (template.yaml), and by hand from GitHub Actions. */
async function runTask(task: string): Promise<APIGatewayProxyStructuredResultV2> {
  store ??= new DynamoQuotaStore(process.env.QUOTA_TABLE ?? "");
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
      if ("task" in event) return await runTask(event.task);
      // The keep-warm schedule (template.yaml): secrets loaded, nothing else to do.
      return json(200, { warm: true });
    }
    return await route(event);
  } catch (error) {
    console.error("request failed", error instanceof Error ? error.message : error);
    return json(500, { code: "internal", message: "Something went wrong. Please try again." });
  }
}
