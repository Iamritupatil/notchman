import { describe, expect, it } from "vitest";
import { claimedEnvironment, resolveEntitlement } from "../lib/entitlements.js";
import { handleTLDR, handleUsage } from "../lib/handlers.js";
import { targetWords } from "../lib/plans.js";
import { MemoryUsageStore, reserve } from "../lib/usage.js";

const ID = "3f2c9a4e-1b7d-4c8e-9a2f-5d6e7f8a9b0c";
const TEXT = "This is a long message that needs a TL;DR. ".repeat(10);

function deps(overrides = {}) {
  return {
    store: new MemoryUsageStore(),
    entitlement: async () => ({ plan: "free" as const, accountKey: `install:${ID}` }),
    summarize: async () => "Okay, here's the important part.",
    ...overrides,
  };
}

describe("POST /api/tldr", () => {
  it("summarizes and reports remaining allowance", async () => {
    const result = await handleTLDR({ installId: ID, text: TEXT }, deps());
    expect(result.status).toBe(200);
    expect(result.body).toMatchObject({ summary: "Okay, here's the important part.", plan: "free", used: 1, limit: 10, remaining: 9 });
  });

  it("stops at the monthly limit with 402", async () => {
    const d = deps();
    for (let i = 0; i < 10; i++) expect((await handleTLDR({ installId: ID, text: TEXT }, d)).status).toBe(200);
    const blocked = await handleTLDR({ installId: ID, text: TEXT }, d);
    expect(blocked.status).toBe(402);
    expect(blocked.body).toMatchObject({ error: "quota_exceeded", remaining: 0, limit: 10 });
  });

  it("gives Pro+ 250", async () => {
    const d = deps({ entitlement: async () => ({ plan: "proplus" as const, accountKey: "sub:1" }) });
    const result = await handleTLDR({ installId: ID, text: TEXT }, d);
    expect(result.body).toMatchObject({ plan: "proplus", limit: 250, remaining: 249 });
  });

  it("refunds the TL;DR when the summary fails", async () => {
    const d = deps({ summarize: async () => { throw new Error("boom"); } });
    expect((await handleTLDR({ installId: ID, text: TEXT }, d)).status).toBe(502);
    const usage = await handleUsage({ installId: ID }, d);
    expect(usage.body).toMatchObject({ used: 0, remaining: 10 });
  });

  it("rejects bad input", async () => {
    expect((await handleTLDR({ installId: "nope", text: TEXT }, deps())).status).toBe(400);
    expect((await handleTLDR({ installId: ID, text: "short" }, deps())).status).toBe(400);
  });

  it("caps total free usage per day", async () => {
    const d = { ...deps(), freeDailyCap: 2 };
    const other = (n: number) => ({ plan: "free" as const, accountKey: `install:${n}` });
    let n = 0;
    const d2 = { ...d, entitlement: async () => other(n++) };
    expect((await handleTLDR({ installId: ID, text: TEXT }, d2)).status).toBe(200);
    expect((await handleTLDR({ installId: ID, text: TEXT }, d2)).status).toBe(200);
    expect((await handleTLDR({ installId: ID, text: TEXT }, d2)).status).toBe(503);
  });
});

describe("quota", () => {
  it("resets each month", async () => {
    const store = new MemoryUsageStore();
    const jan = new Date(Date.UTC(2026, 0, 31));
    const feb = new Date(Date.UTC(2026, 1, 1));
    expect((await reserve(store, "a", 1, { isFree: false, now: jan })).allowed).toBe(true);
    expect((await reserve(store, "a", 1, { isFree: false, now: jan })).allowed).toBe(false);
    expect((await reserve(store, "a", 1, { isFree: false, now: feb })).allowed).toBe(true);
  });
});

describe("entitlements", () => {
  it("treats missing or forged receipts as Free", async () => {
    const forged = ["eyJhbGciOiJFUzI1NiJ9." + Buffer.from(JSON.stringify({ environment: "Sandbox" })).toString("base64url") + ".sig"];
    process.env.APPLE_ROOT_CERTS_BASE64 = Buffer.from("not a cert").toString("base64");
    expect(await resolveEntitlement(ID)).toEqual({ plan: "free", accountKey: `install:${ID}` });
    expect((await resolveEntitlement(ID, forged)).plan).toBe("free");
  });

  it("reads the claimed environment", () => {
    const jws = "h." + Buffer.from(JSON.stringify({ environment: "Production" })).toString("base64url") + ".s";
    expect(claimedEnvironment(jws)).toBe("Production");
    expect(claimedEnvironment("garbage")).toBeUndefined();
  });
});

describe("plans", () => {
  it("scales detailed summaries with the source", () => {
    expect(targetWords("oneMinute", 5000)).toBe(150);
    expect(targetWords("detailed", 100)).toBe(300);
    expect(targetWords("detailed", 10_000)).toBe(900);
  });
});

describe("summarize (OpenAI call)", async () => {
  const { summarize } = await import("../lib/summarize.js");

  it("sends our server key and the audio-first prompt", async () => {
    process.env.OPENAI_API_KEY = "sk-test";
    let sent: { url: string; init: RequestInit } | undefined;
    const fakeFetch = (async (url: string, init: RequestInit) => {
      sent = { url, init };
      return new Response(JSON.stringify({ choices: [{ message: { content: " Okay, here's the gist. " } }] }), { status: 200 });
    }) as unknown as typeof fetch;
    expect(await summarize(TEXT, "thirtySeconds", fakeFetch)).toBe("Okay, here's the gist.");
    expect(sent?.url).toBe("https://api.openai.com/v1/chat/completions");
    expect((sent?.init.headers as Record<string, string>).Authorization).toBe("Bearer sk-test");
    expect(String(sent?.init.body)).toContain("about 75 words");
  });

  it("surfaces OpenAI errors", async () => {
    process.env.OPENAI_API_KEY = "sk-test";
    const fakeFetch = (async () => new Response(JSON.stringify({ error: { message: "bad key" } }), { status: 401 })) as unknown as typeof fetch;
    await expect(summarize(TEXT, "oneMinute", fakeFetch)).rejects.toThrow("bad key");
  });
});
