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
    entitlement: async () => ({ plan: "pro" as const, accountKey: "sub:1" }),
    summarize: async () => "Okay, here's the important part.",
    synthesize: async () => ({ audioBase64: "QUJD", format: "mp3" as const, characters: 31 }),
    perMinuteLimit: 1_000,
    // Spread calls over time so the per-minute limit doesn't interfere unless tested.
    now: () => new Date(NOW.getTime() + 60_000 * minute++),
    ...overrides,
  };
}

describe("tldr", () => {
  it("summarizes and reports the allowance", async () => {
    const result = await handleTLDR(UID, { text: TEXT }, deps());
    expect(result).toEqual({ ok: true, body: { summary: "Okay, here's the important part.", audio: "QUJD", audioFormat: "mp3", plan: "pro", used: 1, limit: 40, remaining: 39 } });
  });

  it("never spends money on Free (those TL;DRs are made on device)", async () => {
    let calls = 0;
    const d = deps({
      entitlement: async () => ({ plan: "free", accountKey: `user:${UID}` }),
      summarize: async () => { calls++; return "x"; },
      synthesize: async () => { calls++; return { audioBase64: "", format: "mp3", characters: 0 }; },
    });
    const blocked = await handleTLDR(UID, { text: TEXT }, d);
    expect(blocked).toMatchObject({ ok: false, code: "resource-exhausted", details: { reason: "monthly_limit", plan: "free", limit: 0 } });
    expect(calls).toBe(0);
  });

  it("stops Pro at 40 a month", async () => {
    const d = deps();
    for (let i = 0; i < 40; i++) expect((await handleTLDR(UID, { text: TEXT }, d)).ok).toBe(true);
    const blocked = await handleTLDR(UID, { text: TEXT }, d);
    expect(blocked).toMatchObject({ ok: false, code: "resource-exhausted", details: { reason: "monthly_limit", limit: 40, remaining: 0 } });
  });

  it("gives Pro 40 and Pro+ 100", async () => {
    const pro = await handleTLDR(UID, { text: TEXT }, deps());
    const plus = await handleTLDR(UID, { text: TEXT }, deps({ entitlement: async () => ({ plan: "proplus", accountKey: "sub:2" }) }));
    expect(pro).toMatchObject({ ok: true, body: { limit: 40 } });
    expect(plus).toMatchObject({ ok: true, body: { limit: 100 } });
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

  it("still returns the summary when the voice fails", async () => {
    const d = deps({ synthesize: async () => { throw new Error("voice down"); } });
    const result = await handleTLDR(UID, { text: TEXT }, d);
    expect(result).toMatchObject({ ok: true, body: { summary: "Okay, here's the important part.", used: 1 } });
    expect((result as { body: Record<string, unknown> }).body.audio).toBeUndefined();
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
  it("calls Groq gpt-oss with the server-side key and the audio-first prompt", async () => {
    process.env.GROQ_API_KEY = "gsk-test";
    let sent: RequestInit | undefined;
    let sentURL = "";
    const fakeFetch = (async (url: string, init: RequestInit) => {
      sent = init;
      sentURL = url;
      return new Response(JSON.stringify({ choices: [{ message: { content: " Okay, the gist. " } }] }));
    }) as unknown as typeof fetch;
    expect(await summarize(TEXT, "thirtySeconds", fakeFetch)).toBe("Okay, the gist.");
    expect(sentURL).toBe("https://api.groq.com/openai/v1/chat/completions");
    expect((sent?.headers as Record<string, string>).Authorization).toBe("Bearer gsk-test");
    const body = JSON.parse(String(sent?.body));
    expect(body.model).toBe("openai/gpt-oss-120b");
    expect(body.messages[1].content).toContain("about 54 words, in the same language as the message");
  });

  it("scales complete summaries with the message", () => {
    expect(targetWords("detailed", 100)).toBe(60);
    expect(targetWords("detailed", 1_000)).toBe(450);
    expect(targetWords("detailed", 10_000)).toBe(900);
  });

  it("never makes a timed TL;DR longer than the message needs", () => {
    expect(targetWords("oneMinute", 200)).toBe(120);
    expect(targetWords("oneMinute", 50)).toBe(30);
    expect(targetWords("oneMinute", 2_000)).toBe(150);
  });
});

describe("synthesize (ElevenLabs)", async () => {
  const { synthesize } = await import("../src/speech.js");

  it("requests Multilingual v2 MP3 with the server-side key", async () => {
    process.env.ELEVENLABS_API_KEY = "el-test";
    let url = "";
    let init: RequestInit | undefined;
    const fakeFetch = (async (u: string, i: RequestInit) => {
      url = u; init = i;
      return new Response(new Uint8Array([1, 2, 3]), { status: 200 });
    }) as unknown as typeof fetch;
    const speech = await synthesize("Hola, aquí está lo importante.", fakeFetch);
    expect(url).toContain("https://api.elevenlabs.io/v1/text-to-speech/");
    expect(url).toContain("output_format=mp3_44100_128");
    expect((init?.headers as Record<string, string>)["xi-api-key"]).toBe("el-test");
    expect(JSON.parse(String(init?.body)).model_id).toBe("eleven_multilingual_v2");
    expect(speech.audioBase64).toBe(Buffer.from([1, 2, 3]).toString("base64"));
  });

  it("surfaces ElevenLabs errors", async () => {
    process.env.ELEVENLABS_API_KEY = "el-test";
    const fakeFetch = (async () => new Response("quota", { status: 429 })) as unknown as typeof fetch;
    await expect(synthesize("Hello there.", fakeFetch)).rejects.toThrow("ElevenLabs returned 429");
  });
});
