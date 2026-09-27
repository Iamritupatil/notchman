import { resolveEntitlement, type Entitlement } from "./entitlements.js";
import { PLANS, type SummaryLength } from "./plans.js";
import { dayKey, days, minuteKey, monthKey, type QuotaStore } from "./quota.js";
import { synthesize, type Speech } from "./speech.js";
import { MAX_INPUT_CHARACTERS, summarize, UpstreamError } from "./summarize.js";

export type ErrorCode = "invalid-argument" | "resource-exhausted" | "unavailable" | "internal";

export type Result =
  | { ok: true; body: Record<string, unknown> }
  | { ok: false; code: ErrorCode; message: string; details?: Record<string, unknown> };

export interface Dependencies {
  store: QuotaStore;
  entitlement?: (userId: string, transactions: string[]) => Promise<Entitlement>;
  summarize?: (text: string, length: SummaryLength) => Promise<string>;
  synthesize?: (text: string) => Promise<Speech>;
  /**
   * Beta: cloud TL;DRs per day for users without a paid plan (TestFlight
   * testing, before subscriptions go live). 0 or unset = Free gets none.
   */
  betaDailyTLDRs?: number;
  /** Requests per user per minute, to stop runaway loops and abuse. */
  perMinuteLimit?: number;
  now?: () => Date;
}

const LENGTHS: SummaryLength[] = ["thirtySeconds", "oneMinute", "twoMinutes", "detailed"];

function transactionsFrom(input: Record<string, unknown>): string[] {
  return Array.isArray(input.transactions)
    ? input.transactions.filter((t): t is string => typeof t === "string" && t.length < 20_000).slice(0, 10)
    : [];
}

function usage(entitlement: Entitlement, used: number) {
  const limit = PLANS[entitlement.plan].monthlyTLDRs;
  return { plan: entitlement.plan, used, limit, remaining: Math.max(0, limit - used) };
}

/** The `tldr` callable. `userId` comes from Firebase Auth, never from the request body. */
export async function handleTLDR(userId: string, data: unknown, deps: Dependencies): Promise<Result> {
  const input = (data ?? {}) as Record<string, unknown>;
  const text = typeof input.text === "string" ? input.text.trim() : "";
  if (text.length < 20) return { ok: false, code: "invalid-argument", message: "Text is too short to summarize." };
  if (text.length > MAX_INPUT_CHARACTERS * 2) {
    return { ok: false, code: "invalid-argument", message: "Text is too long." };
  }
  const length = LENGTHS.includes(input.length as SummaryLength) ? (input.length as SummaryLength) : "oneMinute";
  const now = deps.now?.() ?? new Date();

  const rate = await deps.store.consume(`rate_${userId}_${minuteKey(now)}`, deps.perMinuteLimit ?? 6, days(1, now));
  if (!rate.allowed) return { ok: false, code: "resource-exhausted", message: "Slow down a little and try again.", details: { reason: "rate" } };

  const entitlement = await (deps.entitlement ?? resolveEntitlement)(userId, transactionsFrom(input));
  const planLimit = PLANS[entitlement.plan].monthlyTLDRs;
  const beta = planLimit === 0 && (deps.betaDailyTLDRs ?? 0) > 0;
  if (planLimit === 0 && !beta) {
    // No paid plan: the app makes this TL;DR on device instead.
    return { ok: false, code: "resource-exhausted", message: "Cloud TL;DRs need Pro or Pro+.",
             details: { reason: "monthly_limit", ...usage(entitlement, 0) } };
  }
  const limit = beta ? deps.betaDailyTLDRs! : planLimit;
  const monthly = beta ? `beta_${entitlement.accountKey}_${dayKey(now)}` : `usage_${entitlement.accountKey}_${monthKey(now)}`;
  const reserved = await deps.store.consume(monthly, limit, days(beta ? 2 : 40, now));
  const allowance = { plan: entitlement.plan, used: reserved.count, limit, remaining: Math.max(0, limit - reserved.count) };
  if (!reserved.allowed) {
    return { ok: false, code: "resource-exhausted", message: beta ? "Today's beta TL;DRs are used up." : "Monthly TL;DRs used up.",
             details: { reason: "monthly_limit", ...allowance } };
  }

  let summary: string;
  try {
    summary = await (deps.summarize ?? summarize)(text, length);
  } catch (error) {
    // Never charge a user for our failure.
    await deps.store.refund(monthly);
    console.error("summary failed", error instanceof UpstreamError ? error.message : error);
    return { ok: false, code: "internal", message: "The summary couldn't be created. Please try again." };
  }

  // The voice is best-effort: if ElevenLabs fails, the app reads the summary
  // with Apple's on-device voice instead, so the TL;DR still works.
  let audio: Speech | undefined;
  try {
    audio = await (deps.synthesize ?? synthesize)(summary);
  } catch (error) {
    console.error("voice failed", error instanceof UpstreamError ? error.message : error);
  }
  return {
    ok: true,
    body: { summary, ...(audio ? { audio: audio.audioBase64, audioFormat: audio.format } : {}), ...allowance },
  };
}

/** The `usage` callable. */
export async function handleUsage(userId: string, data: unknown, deps: Dependencies): Promise<Result> {
  const input = (data ?? {}) as Record<string, unknown>;
  const entitlement = await (deps.entitlement ?? resolveEntitlement)(userId, transactionsFrom(input));
  const now = deps.now?.() ?? new Date();
  const betaLimit = deps.betaDailyTLDRs ?? 0;
  if (PLANS[entitlement.plan].monthlyTLDRs === 0 && betaLimit > 0) {
    const used = await deps.store.count(`beta_${entitlement.accountKey}_${dayKey(now)}`);
    return { ok: true, body: { plan: entitlement.plan, used, limit: betaLimit, remaining: Math.max(0, betaLimit - used) } };
  }
  const used = await deps.store.count(`usage_${entitlement.accountKey}_${monthKey(now)}`);
  return { ok: true, body: usage(entitlement, used) };
}
