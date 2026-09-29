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
import { DynamoQuotaStore } from "./dynamo.js";
import { handleSpeak, handleTLDR, handleUsage, type Dependencies, type ErrorCode, type Result } from "./handlers.js";
import { loadSecrets } from "./secrets.js";

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

export async function route(event: APIGatewayProxyEventV2, overrides: LambdaOverrides = {}): Promise<APIGatewayProxyStructuredResultV2> {
  if (event.requestContext.http.method !== "POST") return json(405, { code: "invalid-argument", message: "Use POST." });
  const path = event.rawPath.replace(/\/+$/, "");
  if (path !== "/tldr" && path !== "/usage" && path !== "/speak") return json(404, { code: "invalid-argument", message: "Not found." });

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
    globalDailyTLDRs: Number(process.env.GLOBAL_DAILY_TLDRS ?? 1_000),
    globalDailyVoiceCharacters: Number(process.env.GLOBAL_DAILY_VOICE_CHARACTERS ?? 400_000),
    ...overrides.deps,
  };
  const result: Result = path === "/usage" ? await handleUsage(userId, data, deps)
    : path === "/speak" ? await handleSpeak(userId, data, deps)
    : await handleTLDR(userId, data, deps);
  return result.ok ? json(200, result.body)
                   : json(STATUS[result.code], { code: result.code, message: result.message, details: result.details });
}

export async function handler(event: APIGatewayProxyEventV2): Promise<APIGatewayProxyStructuredResultV2> {
  try {
    await loadSecrets();
    return await route(event);
  } catch (error) {
    console.error("request failed", error instanceof Error ? error.message : error);
    return json(500, { code: "internal", message: "Something went wrong. Please try again." });
  }
}
