import { resolveEntitlement, type Entitlement } from "./entitlements.js";
import { PLANS, type SummaryLength } from "./plans.js";
import { MAX_INPUT_CHARACTERS, summarize, UpstreamError } from "./summarize.js";
import { currentUsage, release, reserve, type UsageStore } from "./usage.js";

export interface Result {
  status: number;
  body: Record<string, unknown>;
}

export interface Dependencies {
  store: UsageStore;
  entitlement?: (installId: string, transactions: string[]) => Promise<Entitlement>;
  summarize?: (text: string, length: SummaryLength) => Promise<string>;
  freeDailyCap?: number;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const LENGTHS: SummaryLength[] = ["thirtySeconds", "oneMinute", "twoMinutes", "detailed"];

function parseCommon(body: unknown): { installId: string; transactions: string[] } | Result {
  const input = (body ?? {}) as Record<string, unknown>;
  const installId = typeof input.installId === "string" ? input.installId : "";
  if (!UUID.test(installId)) return { status: 400, body: { error: "invalid_install_id" } };
  const transactions = Array.isArray(input.transactions)
    ? input.transactions.filter((t): t is string => typeof t === "string" && t.length < 20_000)
    : [];
  return { installId, transactions };
}

function usageBody(entitlement: Entitlement, used: number) {
  const limit = PLANS[entitlement.plan].monthlyTLDRs;
  return { plan: entitlement.plan, used, limit, remaining: Math.max(0, limit - used) };
}

/** POST /api/tldr — { installId, text, length?, transactions? } */
export async function handleTLDR(body: unknown, deps: Dependencies): Promise<Result> {
  const common = parseCommon(body);
  if ("status" in common) return common;
  const input = body as Record<string, unknown>;
  const text = typeof input.text === "string" ? input.text.trim() : "";
  if (text.length < 20) return { status: 400, body: { error: "text_too_short" } };
  if (text.length > MAX_INPUT_CHARACTERS * 2) return { status: 413, body: { error: "text_too_long" } };
  const length = LENGTHS.includes(input.length as SummaryLength) ? (input.length as SummaryLength) : "oneMinute";

  const entitlement = await (deps.entitlement ?? resolveEntitlement)(common.installId, common.transactions);
  const limit = PLANS[entitlement.plan].monthlyTLDRs;
  const isFree = entitlement.plan === "free";
  const quota = await reserve(deps.store, entitlement.accountKey, limit, { isFree, freeDailyCap: deps.freeDailyCap });
  if (!quota.allowed) {
    return quota.reason === "free_capacity"
      ? { status: 503, body: { error: "busy", ...usageBody(entitlement, quota.used) } }
      : { status: 402, body: { error: "quota_exceeded", ...usageBody(entitlement, quota.used) } };
  }

  try {
    const summary = await (deps.summarize ?? summarize)(text, length);
    return { status: 200, body: { summary, ...usageBody(entitlement, quota.used) } };
  } catch (error) {
    // Don't charge the user for our failure.
    await release(deps.store, entitlement.accountKey, isFree);
    const message = error instanceof UpstreamError ? error.message : "Summary failed.";
    return { status: 502, body: { error: "upstream", message } };
  }
}

/** POST /api/usage — { installId, transactions? } */
export async function handleUsage(body: unknown, deps: Dependencies): Promise<Result> {
  const common = parseCommon(body);
  if ("status" in common) return common;
  const entitlement = await (deps.entitlement ?? resolveEntitlement)(common.installId, common.transactions);
  const used = await currentUsage(deps.store, entitlement.accountKey);
  return { status: 200, body: usageBody(entitlement, used) };
}
