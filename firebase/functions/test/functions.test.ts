import { describe, expect, it } from "vitest";
import { claimedEnvironment, resolveEntitlement } from "../src/entitlements.js";
import { handleTLDR, handleUsage } from "../src/handlers.js";
import { targetWords } from "../src/plans.js";
import { MemoryQuotaStore } from "../src/quota.js";
import { summarize } from "../src/summarize.js";

const UID = "firebase-user-1";
const TEXT = "This is a long message that needs a TL;DR. ".repeat(10);
const NOW = new Date(Date.UTC(2026, 8, 27, 10, 0));

function deps(overrides: Record<string, unknown> = {}) {
  let minute = 0;
  return {
    store: new MemoryQuotaStore(),
    entitlement: async () => ({ plan: "free" as const, accountKey: `user:${UID}` }),
    summarize: async () => "Okay, here's the important part.",
    perMinuteLimit: 1_000,
    // Spread calls over time so the per-minute limit doesn't interfere unless tested.
    now: () => new Date(NOW.getTime() + 60_000 * minute++),
    ...overrides,
  };
}

describe("tldr", () => {
  it("summarizes and reports the allowance", async () => {
    const result = await handleTLDR(UID, { text: TEXT }, deps());
    expect(result).toEqual({ ok: true, body: { summary: "Okay, here's the important part.", plan: "free", used: 1, limit: 10, remaining: 9 } });
  });

  it("stops Free at 10 a month", async () => {
    const d = deps();
    for (let i = 0; i < 10; i++) expect((await handleTLDR(UID, { text: TEXT }, d)).ok).toBe(true);
    const blocked = await handleTLDR(UID, { text: TEXT }, d);
    expect(blocked).toMatchObject({ ok: false, code: "resource-exhausted", details: { reason: "monthly_limit", limit: 10, remaining: 0 } });
  });

  it("gives Pro 100 and Pro+ 250", async () => {
    const pro = await handleTLDR(UID, { text: TEXT }, deps({ entitlement: async () => ({ plan: "pro", accountKey: "sub:1" }) }));
    const plus = await handleTLDR(UID, { text: TEXT }, deps({ entitlement: async () => ({ plan: "proplus", accountKey: "sub:2" }) }));
    expect(pro).toMatchObject({ ok: true, body: { limit: 100 } });
    expect(plus).toMatchObject({ ok: true, body: { limit: 250 } });
  });

  it("rate-limits bursts from one user", async () => {
    const d = deps({ perMinuteLimit: 2, now: () => NOW });
    expect((await handleTLDR(UID, { text: TEXT }, d)).ok).toBe(true);
    expect((await handleTLDR(UID, { text: TEXT }, d)).ok).toBe(true);
    expect(await handleTLDR(UID, { text: TEXT }, d)).toMatchObject({ ok: false, details: { reason: "rate" } });
  });

  it("refunds when the summary fails", async () => {
    const d = deps({ summarize: async () => { throw new Error("boom"); } });
    expect(await handleTLDR(UID, { text: TEXT }, d)).toMatchObject({ ok: false, code: "internal" });
    expect(await handleUsage(UID, {}, { ...d, now: () => NOW })).toMatchObject({ ok: true, body: { used: 0 } });
  });

  it("caps total free usage per day", async () => {
    let n = 0;
    const d = deps({ freeDailyCap: 2, entitlement: async () => ({ plan: "free", accountKey: `user:${n++}` }) });
    expect((await handleTLDR(UID, { text: TEXT }, d)).ok).toBe(true);
    expect((await handleTLDR(UID, { text: TEXT }, d)).ok).toBe(true);
    expect(await handleTLDR(UID, { text: TEXT }, d)).toMatchObject({ ok: false, code: "unavailable" });
  });

  it("rejects bad input", async () => {
    expect(await handleTLDR(UID, { text: "short" }, deps())).toMatchObject({ ok: false, code: "invalid-argument" });
    expect(await handleTLDR(UID, { text: "x".repeat(200_000) }, deps())).toMatchObject({ ok: false, code: "invalid-argument" });
  });
});

describe("entitlements", () => {
  it("treats missing or forged receipts as Free", async () => {
    const forged = ["h." + Buffer.from(JSON.stringify({ environment: "Sandbox" })).toString("base64url") + ".sig"];
    process.env.APPLE_ROOT_CERTS_BASE64 = Buffer.from("not a cert").toString("base64");
    expect(await resolveEntitlement(UID)).toEqual({ plan: "free", accountKey: `user:${UID}` });
    expect((await resolveEntitlement(UID, forged)).plan).toBe("free");
  });

  it("reads the claimed environment", () => {
    expect(claimedEnvironment("h." + Buffer.from(JSON.stringify({ environment: "Production" })).toString("base64url") + ".s")).toBe("Production");
    expect(claimedEnvironment("garbage")).toBeUndefined();
  });
});

describe("summarize", () => {
  it("uses the server-side key and the audio-first prompt", async () => {
    process.env.OPENAI_API_KEY = "sk-test";
    let sent: RequestInit | undefined;
    const fakeFetch = (async (_url: string, init: RequestInit) => {
      sent = init;
      return new Response(JSON.stringify({ choices: [{ message: { content: " Okay, the gist. " } }] }));
    }) as unknown as typeof fetch;
    expect(await summarize(TEXT, "thirtySeconds", fakeFetch)).toBe("Okay, the gist.");
    expect((sent?.headers as Record<string, string>).Authorization).toBe("Bearer sk-test");
    expect(String(sent?.body)).toContain("about 75 words");
  });

  it("scales detailed summaries", () => {
    expect(targetWords("detailed", 100)).toBe(300);
    expect(targetWords("detailed", 10_000)).toBe(900);
  });
});
