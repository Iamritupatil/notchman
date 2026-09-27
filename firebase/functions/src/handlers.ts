import { resolveEntitlement, type Entitlement } from "./entitlements.js";
import { PLANS, type SummaryLength } from "./plans.js";
import { days, dayKey, minuteKey, monthKey, type QuotaStore } from "./quota.js";
import { MAX_INPUT_CHARACTERS, summarize, UpstreamError } from "./summarize.js";

export type ErrorCode = "invalid-argument" | "resource-exhausted" | "unavailable" | "internal";

export type Result =
  | { ok: true; body: Record<string, unknown> }
  | { ok: false; code: ErrorCode; message: string; details?: Record<string, unknown> };

export interface Dependencies {
  store: QuotaStore;
  entitlement?: (userId: string, transactions: string[]) => Promise<Entitlement>;
  summarize?: (text: string, length: SummaryLength) => Promise<string>;
  /** Most Free TL;DRs per day across everyone: a hard ceiling on free spend. */
  freeDailyCap?: number;
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
  const limit = PLANS[entitlement.plan].monthlyTLDRs;
  const monthly = `usage_${entitlement.accountKey}_${monthKey(now)}`;
  const reserved = await deps.store.consume(monthly, limit, days(40, now));
  if (!reserved.allowed) {
    return { ok: false, code: "resource-exhausted", message: "Monthly TL;DRs used up.",
             details: { reason: "monthly_limit", ...usage(entitlement, reserved.count) } };
  }

  const isFree = entitlement.plan === "free";
  const globalKey = `free-global_${dayKey(now)}`;
  if (isFree && deps.freeDailyCap) {
    const global = await deps.store.consume(globalKey, deps.freeDailyCap, days(2, now));
    if (!global.allowed) {
      await deps.store.refund(monthly);
      return { ok: false, code: "unavailable", message: "Notchman is very busy. Try again later." };
    }
  }

  try {
    const summary = await (deps.summarize ?? summarize)(text, length);
    return { ok: true, body: { summary, ...usage(entitlement, reserved.count) } };
  } catch (error) {
    // Never charge a user for our failure.
    await deps.store.refund(monthly);
    if (isFree && deps.freeDailyCap) await deps.store.refund(globalKey);
    console.error("summary failed", error instanceof UpstreamError ? error.message : error);
    return { ok: false, code: "internal", message: "The summary couldn't be created. Please try again." };
  }
}

/** The `usage` callable. */
export async function handleUsage(userId: string, data: unknown, deps: Dependencies): Promise<Result> {
  const input = (data ?? {}) as Record<string, unknown>;
  const entitlement = await (deps.entitlement ?? resolveEntitlement)(userId, transactionsFrom(input));
  const now = deps.now?.() ?? new Date();
  const used = await deps.store.count(`usage_${entitlement.accountKey}_${monthKey(now)}`);
  return { ok: true, body: usage(entitlement, used) };
}
