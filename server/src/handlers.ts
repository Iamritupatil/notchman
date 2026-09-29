import { resolveEntitlement, type Entitlement } from "./entitlements.js";
import { PLANS, type SummaryLength } from "./plans.js";
import { dayKey, days, minuteKey, monthKey, type QuotaStore } from "./quota.js";
import { synthesize, type Speech, type SpeechContext } from "./speech.js";
import { MAX_INPUT_CHARACTERS, summarize, UpstreamError } from "./summarize.js";

export type ErrorCode = "invalid-argument" | "resource-exhausted" | "unavailable" | "internal";

export type Result =
  | { ok: true; body: Record<string, unknown> }
  | { ok: false; code: ErrorCode; message: string; details?: Record<string, unknown> };

export interface Dependencies {
  store: QuotaStore;
  entitlement?: (userId: string, transactions: string[]) => Promise<Entitlement>;
  summarize?: (text: string, length: SummaryLength) => Promise<string>;
  synthesize?: (text: string, context?: SpeechContext) => Promise<Speech>;
  /**
   * Beta: cloud TL;DRs per day for users without a paid plan (TestFlight
   * testing, before subscriptions go live). 0 or unset = Free gets none.
   */
  betaDailyTLDRs?: number;
  /** Beta: ElevenLabs characters per user per day for Read and TL;DR audio. */
  betaDailyVoiceCharacters?: number;
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
  const length = LENGTHS.includes(input.length as SummaryLength) ? (input.length as SummaryLength) : "detailed";
  // The app voices the summary itself with /speak (in pieces, so audio starts
  // sooner); older apps still get the audio here.
  const wantsVoice = input.voice !== false;
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
  let voiceError: string | undefined;
  if (wantsVoice) {
    try {
      audio = await (deps.synthesize ?? synthesize)(summary);
    } catch (error) {
      voiceError = error instanceof UpstreamError ? error.message : "The voice couldn't be made.";
      console.error("voice failed", voiceError);
    }
  }
  return {
    ok: true,
    body: {
      summary,
      ...(audio ? { audio: audio.audioBase64, audioFormat: audio.format } : {}),
      // Lets testers see why the natural voice was missing (no secrets in it).
      ...(voiceError ? { voiceError: voiceError.slice(0, 200) } : {}),
      ...allowance,
    },
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

/** Longest piece of text voiced in one request; the app sends text in pieces. */
export const MAX_SPEAK_CHARACTERS = 2_500;

/**
 * The `speak` endpoint: ElevenLabs audio for one piece of text (Read, or a
 * TL;DR). Counted in characters against a daily allowance, since that's what
 * ElevenLabs charges for.
 */
export async function handleSpeak(userId: string, data: unknown, deps: Dependencies): Promise<Result> {
  const input = (data ?? {}) as Record<string, unknown>;
  const text = typeof input.text === "string" ? input.text.trim() : "";
  if (!text) return { ok: false, code: "invalid-argument", message: "Nothing to read." };
  if (text.length > MAX_SPEAK_CHARACTERS) return { ok: false, code: "invalid-argument", message: "Text piece is too long." };
  const context: SpeechContext = {
    previousText: typeof input.previousText === "string" ? input.previousText : undefined,
    nextText: typeof input.nextText === "string" ? input.nextText : undefined,
  };
  const now = deps.now?.() ?? new Date();

  // A long Read arrives as many pieces, so allow more requests per minute.
  const rate = await deps.store.consume(`speakrate_${userId}_${minuteKey(now)}`, 40, days(1, now));
  if (!rate.allowed) return { ok: false, code: "resource-exhausted", message: "Slow down a little and try again.", details: { reason: "rate" } };

  const entitlement = await (deps.entitlement ?? resolveEntitlement)(userId, transactionsFrom(input));
  const paid = PLANS[entitlement.plan].monthlyTLDRs > 0;
  const limit = paid ? 1_000_000 : deps.betaDailyVoiceCharacters ?? 0;
  if (limit <= 0) {
    return { ok: false, code: "resource-exhausted", message: "The Notchman voice needs Pro or Pro+.", details: { reason: "voice_limit" } };
  }
  const key = `voice_${entitlement.accountKey}_${dayKey(now)}`;
  const reserved = await deps.store.consume(key, limit, days(2, now), text.length);
  if (!reserved.allowed) {
    return { ok: false, code: "resource-exhausted", message: "Today's listening time is used up. It resets tomorrow.",
             details: { reason: "voice_limit", used: reserved.count, limit } };
  }

  try {
    const audio = deps.synthesize ? await deps.synthesize(text, context) : await synthesize(text, fetch, context);
    return { ok: true, body: { audio: audio.audioBase64, audioFormat: audio.format,
                               charactersUsed: reserved.count, characterLimit: limit } };
  } catch (error) {
    await deps.store.refund(key, text.length);
    console.error("voice failed", error instanceof UpstreamError ? error.message : error);
    return { ok: false, code: "unavailable", message: "The voice couldn't be made. Please try again." };
  }
}
