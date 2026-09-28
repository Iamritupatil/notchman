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
}

export const PLANS: Record<PlanID, Plan> = {
  free: { id: "free", name: "Free", monthlyTLDRs: 0 },
  pro: { id: "pro", name: "Pro", monthlyTLDRs: 40 },
  proplus: { id: "proplus", name: "Pro+", monthlyTLDRs: 100 },
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
  // A TL;DR is never more than about a third of the message.
  const short = Math.max(30, Math.floor(sourceWords * 0.3));
  switch (length) {
    case "thirtySeconds": return Math.min(75, short);
    case "oneMinute": return Math.min(150, short);
    case "twoMinutes": return Math.min(300, short);
    case "detailed": return Math.min(900, Math.max(300, Math.round(sourceWords * 0.35)));
  }
}
