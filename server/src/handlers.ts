import { createHash } from "node:crypto";
import { deleteAccount, IdentityError, refreshAccount, signIn, verifyIdentityToken, type AccountPlan, type AppleIdentity } from "./accounts.js";
import { alertOnce, countVoice, type Notify } from "./alerts.js";
import { BillingError, cleanEmail, createCheckout, type Buyer } from "./billing.js";
import { resolveEntitlement, type Entitlement } from "./entitlements.js";
import { FREE_MAX_CHARACTERS, PLANS, type SummaryLength } from "./plans.js";
import { dayKey, days, minuteKey, monthKey, type QuotaStore } from "./quota.js";
import { elevenLabsRemaining, spendBalance, synthesize, synthesizeAzure, VOICE_ID, type Speech, type SpeechContext } from "./speech.js";
import { MAX_INPUT_CHARACTERS, SUMMARY_VERSION, summarizeTLDR, UpstreamError } from "./summarize.js";

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
  /**
   * Free plan: ElevenLabs characters per install, once (a taste of the
   * Notchman voice, ~3 TL;DRs). After it, the apps use their free voices.
   * When set, it replaces the daily beta voice allowance.
   */
  freeTrialVoiceCharacters?: number;
  /**
   * ElevenLabs credits kept in reserve: below this, free users get no
   * ElevenLabs audio; below a fifth of it, nobody does (apps fall back).
   */
  voiceReserveCredits?: number;
  /** Reads the ElevenLabs balance (tests replace it). */
  voiceBalance?: () => Promise<number | undefined>;
  /** Creates a Dodo checkout link (tests replace it). */
  checkout?: (installId: string, plan: "pro" | "proplus", buyer: Buyer) => Promise<string>;
  /** The standard voice (Azure); tests replace it. */
  synthesizeStandard?: (text: string, context?: SpeechContext) => Promise<Speech>;
  /** Standard-voice characters per install per day. */
  standardDailyCharacters?: number;
  /** Standard-voice characters per month across everyone (Azure's free tier is 500,000). 0 = no cap. */
  standardMonthlyCharacters?: number;
  /** Spending caps across all users per day (unset = no cap). */
  globalDailyTLDRs?: number;
  globalDailyVoiceCharacters?: number;
  /**
   * Free users' share of the Notchman voice (ElevenLabs) per month, across
   * everyone: past it they hear the free voices, so the credits paying users
   * need are never used up by free previews. 0 = no monthly cap.
   */
  freeMonthlyVoiceCharacters?: number;
  /**
   * A one-way hash of the computer's own ID (desktop), the same after a
   * reinstall: free limits are counted per computer, not per install.
   */
  device?: string;
  /** The caller's IP address: free limits are also capped per network per day. */
  clientIp?: string;
  /** Free TL;DRs per network (IP) per day, across every install on it. 0/unset = no cap. */
  ipDailyTLDRs?: number;
  /** Free Notchman-voice characters per network (IP) per day. 0/unset = no cap. */
  ipDailyVoiceCharacters?: number;
  /** Owner email alerts (tests replace it). */
  notify?: Notify;
  /** Checks a Sign in with Apple identity token (tests replace it). */
  verifyIdentity?: (token: string) => Promise<AppleIdentity>;
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

/** The caller's plan: App Store receipts, a desktop (Dodo) subscription, RevenueCat. */
async function entitlementFor(userId: string, input: Record<string, unknown>, deps: Dependencies): Promise<Entitlement> {
  const entitlement = await (deps.entitlement
    ? deps.entitlement(userId, transactionsFrom(input))
    : resolveEntitlement(userId, transactionsFrom(input), Date.now(), deps.store, deps.device));
  // Free limits follow the computer, so reinstalling doesn't reset them.
  if (entitlement.plan === "free" && deps.device) return { ...entitlement, accountKey: `device:${deps.device}` };
  return entitlement;
}

/** A network's key for the per-IP caps (the address itself isn't stored). */
function networkKey(ip: string): string {
  return createHash("sha256").update(`notchman-ip:${ip}`).digest("hex").slice(0, 32);
}

/**
 * The `checkout` endpoint (desktop): a Dodo Payments link for Pro or Pro+.
 * The app asks for the buyer's email first: it's filled in at Dodo, and kept
 * with the install and computer IDs (lead_<install>) so the owner knows who
 * started buying, even if they didn't finish. Older apps send no email.
 */
export async function handleCheckout(userId: string, data: unknown, deps: Dependencies): Promise<Result> {
  const input = (data ?? {}) as Record<string, unknown>;
  const plan = input.plan === "pro" || input.plan === "proplus" ? input.plan : null;
  if (!plan) return { ok: false, code: "invalid-argument", message: "Choose Pro or Pro+." };
  const email = cleanEmail(input.email);
  if (input.email !== undefined && !email) {
    return { ok: false, code: "invalid-argument", message: "That email doesn't look right. Check it and try again." };
  }
  const buyer: Buyer = { email, device: deps.device };
  try {
    const url = await (deps.checkout ? deps.checkout(userId, plan, buyer) : createCheckout(userId, plan, fetch, buyer));
    if (email) await noteBuyer(userId, plan, email, deps);
    return { ok: true, body: { url } };
  } catch (error) {
    const message = error instanceof BillingError ? error.message : "Checkout couldn't be opened. Please try again.";
    if (!(error instanceof BillingError)) console.error("checkout failed", error);
    return { ok: false, code: "unavailable", message };
  }
}

/** Keeps who started a checkout, and tells the owner (once a day per install and plan). Never throws. */
async function noteBuyer(userId: string, plan: "pro" | "proplus", email: string, deps: Dependencies) {
  const now = deps.now?.() ?? new Date();
  const name = plan === "proplus" ? "Pro+" : "Pro";
  try {
    await deps.store.putRecord(`lead_${userId}`, { email, plan, device: deps.device ?? null, startedAt: now.toISOString() }, days(400, now));
  } catch (error) {
    console.warn("couldn't save the buyer", error instanceof Error ? error.message : error);
  }
  await alertOnce(deps.store, `lead_${userId}_${plan}_${dayKey(now)}`, `Notchman: ${email} opened checkout for ${name}`,
    `${email} opened the checkout for Notchman ${name} in the desktop app (${now.toISOString().slice(0, 16).replace("T", " ")} UTC).\n\n` +
    "You get a separate email when they finish paying. If they don't, you can write to them and ask what stopped them.\n\n" +
    `Install ID: ${userId.replace(/^install:/, "")}`,
    days(2, now), deps.notify);
}

function usage(entitlement: Entitlement, used: number) {
  const limit = PLANS[entitlement.plan].monthlyTLDRs;
  return { plan: entitlement.plan, used, limit, remaining: Math.max(0, limit - used) };
}

const TOO_LONG_FOR_FREE = "That's over 8,000 characters, the free plan's limit. "
  + "Notchman Pro makes TL;DRs of long texts too, like reports and research papers.";

/** The `tldr` endpoint. `userId` is the caller's install, from the request header. */
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
  // Voice is made only through /speak, where it's counted. (Older apps that
  // asked for audio here read the summary with the device voice instead.)
  const wantsVoice = false;
  const now = deps.now?.() ?? new Date();

  const rate = await deps.store.consume(`rate_${userId}_${minuteKey(now)}`, deps.perMinuteLimit ?? 6, days(1, now));
  if (!rate.allowed) return { ok: false, code: "resource-exhausted", message: "Slow down a little and try again.", details: { reason: "rate" } };

  const entitlement = await entitlementFor(userId, input, deps);
  if (entitlement.plan === "free" && text.length > FREE_MAX_CHARACTERS) {
    // Doesn't use up a free TL;DR. The apps offer Upgrade with this reason.
    return { ok: false, code: "invalid-argument", message: TOO_LONG_FOR_FREE,
             details: { reason: "too_long", limit: FREE_MAX_CHARACTERS } };
  }
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

  if (beta && deps.clientIp && deps.ipDailyTLDRs) {
    const network = await deps.store.consume(`iptldr_${networkKey(deps.clientIp)}_${dayKey(now)}`, deps.ipDailyTLDRs, days(2, now));
    if (!network.allowed) {
      await deps.store.refund(monthly);
      return { ok: false, code: "resource-exhausted", message: "Today's free TL;DRs on this network are used up. They reset tomorrow, or upgrade to Pro.",
               details: { reason: "monthly_limit", ...allowance, remaining: 0 } };
    }
  }

  if (deps.globalDailyTLDRs) {
    const global = await deps.store.consume(`global_tldr_${dayKey(now)}`, deps.globalDailyTLDRs, days(2, now));
    if (!global.allowed) {
      await deps.store.refund(monthly);
      return { ok: false, code: "unavailable", message: "Notchman is very busy today. Please try again later." };
    }
  }

  let summary: string;
  let highlights: string[] = [];
  try {
    if (deps.summarize) {
      summary = await deps.summarize(text, length);
    } else {
      ({ summary, highlights } = await summarizeTLDR(text, length));
    }
  } catch (error) {
    // Never charge a user for our failure.
    await deps.store.refund(monthly);
    console.error("summary failed", error instanceof UpstreamError ? error.message : error);
    const busy = error instanceof UpstreamError && error.rateLimited;
    const tooLong = error instanceof UpstreamError && error.tooLong;
    return { ok: false, code: "unavailable",
             message: busy ? "Notchman is very busy right now. Please try again in a minute."
               : tooLong ? "This text is too long for a TL;DR right now. Try a shorter part of it."
               : "The summary couldn't be created. Please try again." };
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
      // The key points, short, for the apps to show next to the player.
      highlights,
      summaryVersion: SUMMARY_VERSION,
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
  const entitlement = await entitlementFor(userId, input, deps);
  const now = deps.now?.() ?? new Date();
  // The Notchman voice allowance, for the desktop dashboard.
  const paidVoice = PLANS[entitlement.plan].monthlyVoiceCharacters > 0;
  const trialVoice = !paidVoice && (deps.freeTrialVoiceCharacters ?? 0) > 0;
  const voice = {
    voiceUsed: await deps.store.count(paidVoice ? `voicem_${entitlement.accountKey}_${monthKey(now)}`
      : trialVoice ? `voicetrial_${entitlement.accountKey}` : `voice_${entitlement.accountKey}_${dayKey(now)}`),
    voiceLimit: paidVoice ? PLANS[entitlement.plan].monthlyVoiceCharacters
      : trialVoice ? deps.freeTrialVoiceCharacters! : deps.betaDailyVoiceCharacters ?? 0,
    voicePeriod: paidVoice ? "month" : trialVoice ? "trial" : "day",
    // Where the desktop app's Upgrade buttons go (set in template.yaml).
    upgradeLinks: { pro: process.env.PRO_UPGRADE_LINK || null, proplus: process.env.PROPLUS_UPGRADE_LINK || null },
  };
  const betaLimit = deps.betaDailyTLDRs ?? 0;
  if (PLANS[entitlement.plan].monthlyTLDRs === 0 && betaLimit > 0) {
    const used = await deps.store.count(`beta_${entitlement.accountKey}_${dayKey(now)}`);
    return { ok: true, body: { plan: entitlement.plan, used, limit: betaLimit, remaining: Math.max(0, betaLimit - used), period: "day", ...voice } };
  }
  const used = await deps.store.count(`usage_${entitlement.accountKey}_${monthKey(now)}`);
  return { ok: true, body: { ...usage(entitlement, used), period: "month", ...voice } };
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
  if (input.voiceId !== undefined && (typeof input.voiceId !== "string" || !VOICE_ID.test(input.voiceId))) {
    // Never fall back to another voice silently: the app shows the error.
    return { ok: false, code: "invalid-argument", message: "That voice isn't available." };
  }
  const context: SpeechContext = {
    previousText: typeof input.previousText === "string" ? input.previousText : undefined,
    nextText: typeof input.nextText === "string" ? input.nextText : undefined,
    voiceId: typeof input.voiceId === "string" ? input.voiceId : undefined,
  };
  const now = deps.now?.() ?? new Date();

  // A long Read arrives as many pieces, so allow more requests per minute.
  const rate = await deps.store.consume(`speakrate_${userId}_${minuteKey(now)}`, 40, days(1, now));
  if (!rate.allowed) return { ok: false, code: "resource-exhausted", message: "Slow down a little and try again.", details: { reason: "rate" } };

  const entitlement = await entitlementFor(userId, input, deps);
  const premium = await premiumSpeak(text, context, entitlement, now, deps);
  if (premium.ok) return premium;
  // No Notchman (ElevenLabs) voice for this piece: use the standard natural
  // voice (Azure) instead of the device's robotic one, when it's set up.
  if (premium.code !== "invalid-argument") {
    const standard = await standardSpeak(text, context, entitlement, now, deps);
    if (standard) return standard;
  }
  return premium;
}

/** The Notchman voice (ElevenLabs), within the plan's allowance. */
async function premiumSpeak(text: string, context: SpeechContext, entitlement: Entitlement, now: Date,
                            deps: Dependencies): Promise<Result> {
  // Paid plans: a monthly allowance they pay for. Free: a small daily one,
  // inside a shared daily spending cap.
  const paid = PLANS[entitlement.plan].monthlyVoiceCharacters > 0;
  const trial = !paid && (deps.freeTrialVoiceCharacters ?? 0) > 0;
  const limit = paid ? PLANS[entitlement.plan].monthlyVoiceCharacters
    : trial ? deps.freeTrialVoiceCharacters! : deps.betaDailyVoiceCharacters ?? 0;
  if (limit <= 0) {
    return { ok: false, code: "resource-exhausted", message: "The Notchman voice needs Pro or Pro+.", details: { reason: "voice_limit" } };
  }

  // Never spend the last ElevenLabs credits: keep a reserve for subscribers.
  const reserve = deps.voiceReserveCredits ?? 0;
  if (reserve > 0) {
    const remaining = await (deps.voiceBalance ?? elevenLabsRemaining)();
    if (remaining !== undefined && remaining < (paid ? reserve / 5 : reserve)) {
      return { ok: false, code: "unavailable", message: "The Notchman voice is resting. Your device's voice reads this instead.",
               details: { reason: "voice_reserve" } };
    }
  }

  const key = paid ? `voicem_${entitlement.accountKey}_${monthKey(now)}`
    : trial ? `voicetrial_${entitlement.accountKey}` : `voice_${entitlement.accountKey}_${dayKey(now)}`;
  const reserved = await deps.store.consume(key, limit, paid ? days(40, now) : trial ? days(400, now) : days(2, now), text.length);
  if (!reserved.allowed) {
    return { ok: false, code: "resource-exhausted",
             message: paid ? "This month's Notchman voice is used up. It renews next month."
               : trial ? "Your free Notchman voice preview is used up. Upgrade to Pro to keep it." : "Today's free Notchman voice is used up. It resets tomorrow.",
             details: { reason: "voice_limit", used: reserved.count, limit } };
  }

  const networkVoiceKey = !paid && deps.clientIp && deps.ipDailyVoiceCharacters
    ? `ipvoice_${networkKey(deps.clientIp)}_${dayKey(now)}` : undefined;
  if (networkVoiceKey) {
    const network = await deps.store.consume(networkVoiceKey, deps.ipDailyVoiceCharacters!, days(2, now), text.length);
    if (!network.allowed) {
      await deps.store.refund(key, text.length);
      return { ok: false, code: "resource-exhausted", message: "Today's free Notchman voice on this network is used up. Upgrade to Pro to keep it.",
               details: { reason: "voice_limit", used: reserved.count, limit } };
    }
  }

  const globalKey = `global_voice_${dayKey(now)}`;
  const capped = !paid && Boolean(deps.globalDailyVoiceCharacters);
  if (capped && deps.globalDailyVoiceCharacters) {
    const global = await deps.store.consume(globalKey, deps.globalDailyVoiceCharacters, days(2, now), text.length);
    if (!global.allowed) {
      await deps.store.refund(key, text.length);
      if (networkVoiceKey) await deps.store.refund(networkVoiceKey, text.length);
      await alertOnce(deps.store, `freecap_${dayKey(now)}`, "Notchman: free users reached today's ElevenLabs cap",
        `Free users used all ${deps.globalDailyVoiceCharacters.toLocaleString("en-US")} free Notchman-voice characters for today (UTC). ` +
        "Until midnight UTC they hear the free voice instead; paying users aren't affected.\n\n" +
        "If free use keeps reaching the cap, it's a good moment to add ElevenLabs credits (https://elevenlabs.io/app/subscription) " +
        "and raise GlobalDailyVoiceCharacters in server/template.yaml.",
        days(2, now), deps.notify);
      return { ok: false, code: "unavailable", message: "Notchman's voice is very busy today. Please try again later." };
    }
  }

  const freeMonthKey = `global_freevoice_${monthKey(now)}`;
  const monthCapped = !paid && Boolean(deps.freeMonthlyVoiceCharacters);
  if (monthCapped) {
    const month = await deps.store.consume(freeMonthKey, deps.freeMonthlyVoiceCharacters!, days(40, now), text.length);
    if (!month.allowed) {
      await deps.store.refund(key, text.length);
      if (networkVoiceKey) await deps.store.refund(networkVoiceKey, text.length);
      if (capped) await deps.store.refund(globalKey, text.length);
      await alertOnce(deps.store, `freemonth_${monthKey(now)}`, "Notchman: free users reached this month's Notchman-voice share",
        `Free users used their ${deps.freeMonthlyVoiceCharacters!.toLocaleString("en-US")}-character share of the Notchman voice ` +
        "(ElevenLabs) for this month. Until next month they hear the free voice; paying users keep theirs.",
        days(40, now), deps.notify);
      return { ok: false, code: "unavailable", message: "Notchman's voice is resting. Your free voice reads this instead.",
               details: { reason: "free_month" } };
    }
  }

  try {
    const audio = deps.synthesize ? await deps.synthesize(text, context) : await synthesize(text, fetch, context);
    spendBalance(text.length);
    await countVoice(deps.store, text.length, paid, now).catch(() => undefined);
    return { ok: true, body: { audio: audio.audioBase64, audioFormat: audio.format, voiceId: audio.voiceId,
                               charactersUsed: reserved.count, characterLimit: limit } };
  } catch (error) {
    await deps.store.refund(key, text.length);
    if (networkVoiceKey) await deps.store.refund(networkVoiceKey, text.length);
    if (capped) await deps.store.refund(globalKey, text.length);
    if (monthCapped) await deps.store.refund(freeMonthKey, text.length);
    console.error("voice failed", error instanceof UpstreamError ? error.message : error);
    return { ok: false, code: "unavailable", message: "The voice couldn't be made. Please try again." };
  }
}

/**
 * The standard voice (Azure neural): natural and much cheaper. Free users
 * hear it after their Notchman-voice preview, and anyone whose allowance is
 * used up. Kept inside Azure's free tier by a monthly cap across everyone.
 * Returns null when it isn't set up or the caps are reached.
 */
async function standardSpeak(text: string, context: SpeechContext, entitlement: Entitlement, now: Date,
                             deps: Dependencies): Promise<Result | null> {
  const speak = deps.synthesizeStandard ?? (process.env.AZURE_SPEECH_KEY ? synthesizeAzure : undefined);
  if (!speak) return null;
  const daily = deps.standardDailyCharacters ?? 20_000;
  const key = `std_${entitlement.accountKey}_${dayKey(now)}`;
  const mine = await deps.store.consume(key, daily, days(2, now), text.length);
  if (!mine.allowed) return null;
  const globalKey = `global_std_${monthKey(now)}`;
  const monthly = deps.standardMonthlyCharacters ?? 0;
  if (monthly > 0) {
    const global = await deps.store.consume(globalKey, monthly, days(40, now), text.length);
    if (!global.allowed) {
      await deps.store.refund(key, text.length);
      return null;
    }
  }
  try {
    const audio = await speak(text, context);
    return { ok: true, body: { audio: audio.audioBase64, audioFormat: audio.format, voiceId: audio.voiceId,
                               voiceTier: "standard", charactersUsed: mine.count, characterLimit: daily } };
  } catch (error) {
    await deps.store.refund(key, text.length);
    if (monthly > 0) await deps.store.refund(globalKey, text.length);
    console.error("standard voice failed", error instanceof UpstreamError ? error.message : error);
    return null;
  }
}

/**
 * The iPhone account (Sign in with Apple, see accounts.ts).
 *   { action: "signin", identityToken, name?, transactions? }   after Sign in with Apple
 *   { action: "refresh", transactions? }                        after a purchase, or on launch
 *   { action: "delete" }                                        Delete Account
 */
export async function handleAccount(userId: string, data: unknown, deps: Dependencies): Promise<Result> {
  const input = (data ?? {}) as Record<string, unknown>;
  const now = deps.now?.() ?? new Date();
  if (input.action === "delete") {
    const deleted = await deleteAccount(deps.store, userId, now);
    return { ok: true, body: { deleted } };
  }
  const entitlement = await entitlementFor(userId, input, deps);
  const plan: AccountPlan = {
    plan: entitlement.plan,
    ...(entitlement.accountKey.startsWith("sub:") ? { subscription: entitlement.accountKey.slice(4) } : {}),
  };
  const planName = (id: string) => (id === "proplus" ? "Pro+" : id === "pro" ? "Pro" : "Free");
  if (input.action === "signin") {
    if (typeof input.identityToken !== "string" || input.identityToken.length > 10_000) {
      return { ok: false, code: "invalid-argument", message: "Sign in with Apple didn't send a token." };
    }
    let identity: AppleIdentity;
    try {
      identity = await (deps.verifyIdentity ?? ((token) => verifyIdentityToken(token, process.env.APPLE_BUNDLE_ID ?? "app.notchman")))(input.identityToken);
    } catch (error) {
      if (error instanceof IdentityError) {
        console.warn("sign in failed", error.message);
        return { ok: false, code: "invalid-argument", message: "Couldn't confirm your Apple sign-in. Try again." };
      }
      throw error;
    }
    const saved = await signIn(deps.store, userId, identity, { name: input.name, ...plan }, now);
    if (saved.new) {
      await alertOnce(deps.store, `account_${identity.appleUserId}`, `Notchman: new iPhone account (${planName(plan.plan)})`,
        `${identity.email ?? "Someone (no email shared)"}${saved.record.name ? ` (${saved.record.name})` : ""} signed in on the iPhone app.\n` +
        `Plan: ${planName(plan.plan)}${plan.subscription ? ` (App Store subscription ${plan.subscription})` : ""}\n` +
        `Apple account ID: ${identity.appleUserId}\nInstall ID: ${userId}`,
        days(KEEP_ALERT_DAYS, now), deps.notify);
    }
    return { ok: true, body: { signedIn: true, plan: plan.plan } };
  }
  if (input.action === "refresh") {
    const refreshed = await refreshAccount(deps.store, userId, plan, now);
    if (refreshed?.upgraded && plan.subscription) {
      await alertOnce(deps.store, `accountplan_${plan.subscription}`, `Notchman: ${String(refreshed.record.email ?? "an iPhone user")} bought ${planName(plan.plan)}`,
        `${String(refreshed.record.email ?? "Someone (no email shared)")} bought Notchman ${planName(plan.plan)} on the iPhone.\n` +
        `Apple account ID: ${String(refreshed.record.appleUserId)}\nApp Store subscription: ${plan.subscription}\nInstall ID: ${userId}`,
        days(KEEP_ALERT_DAYS, now), deps.notify);
    }
    return { ok: true, body: { signedIn: Boolean(refreshed), plan: plan.plan } };
  }
  return { ok: false, code: "invalid-argument", message: "Unknown account action." };
}

const KEEP_ALERT_DAYS = 400;
