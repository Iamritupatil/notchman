/** Subscription plans and their monthly TL;DR allowances. */
export type PlanID = "free" | "pro" | "proplus";

export interface Plan {
  id: PlanID;
  name: string;
  monthlyTLDRs: number;
}

export const PLANS: Record<PlanID, Plan> = {
  free: { id: "free", name: "Free", monthlyTLDRs: 10 },
  pro: { id: "pro", name: "Pro", monthlyTLDRs: 100 },
  proplus: { id: "proplus", name: "Pro+", monthlyTLDRs: 250 },
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
  switch (length) {
    case "thirtySeconds": return 75;
    case "oneMinute": return 150;
    case "twoMinutes": return 300;
    case "detailed": return Math.min(900, Math.max(300, Math.round(sourceWords * 0.35)));
  }
}
