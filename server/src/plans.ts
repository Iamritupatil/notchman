/**
 * Subscription plans and their monthly cloud TL;DR allowances (Groq summary +
 * ElevenLabs voice, about $0.046 each). Free is 0 here: free TL;DRs are made on
 * the iPhone and never reach the server, so free users cost nothing.
 */
export type PlanID = "free" | "pro" | "proplus";

export interface Plan {
  id: PlanID;
  name: string;
  monthlyTLDRs: number;
  /**
   * ElevenLabs characters a month (what ElevenLabs bills). A capped TL;DR is
   * at most ~800 characters, so this covers every TL;DR plus some reading;
   * past it, the apps use their free voices.
   */
  monthlyVoiceCharacters: number;
}

export const PLANS: Record<PlanID, Plan> = {
  free: { id: "free", name: "Free", monthlyTLDRs: 0, monthlyVoiceCharacters: 0 },
  pro: { id: "pro", name: "Pro", monthlyTLDRs: 40, monthlyVoiceCharacters: 40_000 },
  proplus: { id: "proplus", name: "Pro+", monthlyTLDRs: 100, monthlyVoiceCharacters: 100_000 },
};

/** App Store product IDs → plan. Keep in sync with PremiumStore.swift and App Store Connect. */
export const PRODUCT_PLANS: Record<string, PlanID> = {
  "com.notchman.pro.monthly": "pro",
  "com.notchman.pro.yearly": "pro",
  "com.notchman.proplus.monthly": "proplus",
  "com.notchman.proplus.yearly": "proplus",
};

export type SummaryLength = "thirtySeconds" | "oneMinute" | "twoMinutes" | "detailed";

/** Spoken-word budget for a summary; mirrors QuickListenDuration in the app. */
export function targetWords(length: SummaryLength, sourceWords: number): number {
  // Never longer than the message itself would take; "complete" scales with
  // the message so every key point fits.
  const cap = (words: number) => Math.max(30, Math.min(words, Math.round(sourceWords * 0.6)));
  switch (length) {
    case "thirtySeconds": return cap(75);
    case "oneMinute": return cap(150);
    case "twoMinutes": return cap(300);
    case "detailed": return Math.max(60, Math.min(900, Math.round(sourceWords * 0.45)));
  }
}
