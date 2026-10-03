import { describe, expect, it } from "vitest";
import { claimedEnvironment, resolveEntitlement } from "../src/entitlements.js";
import { handleSpeak, handleTLDR, handleUsage } from "../src/handlers.js";
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
    synthesize: async () => ({ audioBase64: "QUJD", format: "mp3" as const, characters: 31, voiceId: "EXAVITQu4vr4xnSDxMaL" }),
    perMinuteLimit: 1_000,
    // Spread calls over time so the per-minute limit doesn't interfere unless tested.
    now: () => new Date(NOW.getTime() + 60_000 * minute++),
    ...overrides,
  };
}

describe("speak", () => {
  const free = { entitlement: async () => ({ plan: "free" as const, accountKey: "anon:1" }) };

  it("voices a piece of text and counts its characters", async () => {
    const result = await handleSpeak(UID, { text: "Hello there, this is Notchman." }, deps({ ...free, betaDailyVoiceCharacters: 100 }));
    expect(result).toMatchObject({ ok: true, body: { audio: "QUJD", audioFormat: "mp3", charactersUsed: 30, characterLimit: 100 } });
  });

  it("stops at the daily character allowance", async () => {
    const d = deps({ ...free, betaDailyVoiceCharacters: 50 });
    expect((await handleSpeak(UID, { text: "x".repeat(40) }, d)).ok).toBe(true);
    expect(await handleSpeak(UID, { text: "x".repeat(20) }, d)).toMatchObject({ ok: false, details: { reason: "voice_limit" } });
    expect((await handleSpeak(UID, { text: "x".repeat(10) }, d)).ok).toBe(true);
  });

  it("refuses free users when the beta voice is off", async () => {
    expect(await handleSpeak(UID, { text: "Hello" }, deps(free))).toMatchObject({ ok: false, details: { reason: "voice_limit" } });
  });

  it("passes neighbouring text for natural flow and refunds failures", async () => {
    let seen: unknown;
    const d = deps({ ...free, betaDailyVoiceCharacters: 100,
                     synthesize: async (_t: string, c: unknown) => { seen = c; throw new Error("down"); } });
    expect(await handleSpeak(UID, { text: "Middle.", previousText: "Before.", nextText: "After.",
                                     voiceId: "JBFqnCBsd6RMkjVDRZzb" }, d))
      .toMatchObject({ ok: false, code: "unavailable" });
    expect(seen).toEqual({ previousText: "Before.", nextText: "After.", voiceId: "JBFqnCBsd6RMkjVDRZzb" });
    expect(await d.store.count(`voice_anon:1_${"2026-09-27"}`)).toBe(0);
  });

  it("stops at the total daily voice cap and refunds the user", async () => {
    const d = deps({ ...free, betaDailyVoiceCharacters: 1_000, globalDailyVoiceCharacters: 30 });
    expect((await handleSpeak(UID, { text: "x".repeat(25) }, d)).ok).toBe(true);
    expect(await handleSpeak(UID, { text: "x".repeat(10) }, d)).toMatchObject({ ok: false, code: "unavailable" });
    expect(await d.store.count("voice_anon:1_2026-09-27")).toBe(25);
  });

  it("rejects a malformed voice ID instead of using another voice", async () => {
    let called = false;
    const d = deps({ ...free, betaDailyVoiceCharacters: 100,
                     synthesize: async () => { called = true; return { audioBase64: "QQ==", format: "mp3" as const, characters: 1, voiceId: "x" }; } });
    expect(await handleSpeak(UID, { text: "Hello.", voiceId: "../../etc" }, d)).toMatchObject({ ok: false, code: "invalid-argument" });
    expect(called).toBe(false);
  });

  it("reports the voice that spoke, so the app can check it", async () => {
    const d = deps({ ...free, betaDailyVoiceCharacters: 100,
                     synthesize: async (_t: string, c: { voiceId?: string }) =>
                       ({ audioBase64: "QQ==", format: "mp3" as const, characters: 6, voiceId: c.voiceId ?? "default" }) });
    expect(await handleSpeak(UID, { text: "Hello.", voiceId: "JBFqnCBsd6RMkjVDRZzb" }, d))
      .toMatchObject({ ok: true, body: { voiceId: "JBFqnCBsd6RMkjVDRZzb" } });
  });

  it("rejects oversized pieces", async () => {
    expect(await handleSpeak(UID, { text: "x".repeat(3_000) }, deps())).toMatchObject({ ok: false, code: "invalid-argument" });
  });
});

describe("tldr", () => {
  it("stops at the total daily TL;DR cap without charging the user", async () => {
    const d = deps({ globalDailyTLDRs: 1 });
    expect((await handleTLDR(UID, { text: TEXT }, d)).ok).toBe(true);
    expect(await handleTLDR(UID, { text: TEXT }, d)).toMatchObject({ ok: false, code: "unavailable" });
    expect(await d.store.count("usage_sub:1_2026-09")).toBe(1);
  });

  it("can return just the summary so the app voices it", async () => {
    let voiced = false;
    const result = await handleTLDR(UID, { text: TEXT, voice: false },
      deps({ synthesize: async () => { voiced = true; return { audioBase64: "QUJD", format: "mp3", characters: 3 }; } }));
    expect(result.ok && result.body.audio).toBeFalsy();
    expect(voiced).toBe(false);
  });

  it("summarizes and reports the allowance", async () => {
    const result = await handleTLDR(UID, { text: TEXT }, deps());
    expect(result).toEqual({ ok: true, body: { summary: "Okay, here's the important part.", audio: "QUJD", audioFormat: "mp3", summaryVersion: "tldr-5", plan: "pro", used: 1, limit: 40, remaining: 39 } });
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
  it("calls Groq gpt-oss with the server-side key (timed lengths, for older apps)", async () => {
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
    expect(body.messages[1].content).toContain("about 54 spoken words");
  });

  it("explains short messages in one call, with no duration target", async () => {
    process.env.GROQ_API_KEY = "gsk-test";
    const bodies: { messages: { content: string }[] }[] = [];
    const fakeFetch = (async (_url: string, init: RequestInit) => {
      bodies.push(JSON.parse(String(init.body)));
      return new Response(JSON.stringify({ choices: [{ message: { content: "Friday at 11, bring your portfolio." } }] }));
    }) as unknown as typeof fetch;
    await summarize("The interview moved to Friday at 11am. Please confirm tonight and bring your portfolio.", "detailed", fakeFetch);
    expect(bodies).toHaveLength(1);
    expect(bodies[0].messages[0].content).toContain("Your job is to explain, not to shorten");
    expect(bodies[0].messages[0].content).toContain("Keep the original's certainty");
    expect(bodies[0].messages[0].content).not.toMatch(/\d+ seconds|one minute/i);
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

  it("requests Flash v2.5 MP3 with the server-side key", async () => {
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
    expect(JSON.parse(String(init?.body)).model_id).toBe("eleven_flash_v2_5");
    expect(speech.audioBase64).toBe(Buffer.from([1, 2, 3]).toString("base64"));
  });

  it("uses the chosen voice, and only a well-formed one", async () => {
    process.env.ELEVENLABS_API_KEY = "el-test";
    let url = "";
    const fakeFetch = (async (u: string) => { url = u; return new Response(new Uint8Array([1]), { status: 200 }); }) as unknown as typeof fetch;
    const speech = await synthesize("Hi.", fakeFetch, { voiceId: "JBFqnCBsd6RMkjVDRZzb" });
    expect(url).toContain("/text-to-speech/JBFqnCBsd6RMkjVDRZzb?");
    expect(speech.voiceId).toBe("JBFqnCBsd6RMkjVDRZzb");
    await synthesize("Hi.", fakeFetch, { voiceId: "bad/id" });
    expect(url).not.toContain("bad");
  });

  it("surfaces ElevenLabs errors", async () => {
    process.env.ELEVENLABS_API_KEY = "el-test";
    const fakeFetch = (async () => new Response("quota", { status: 429 })) as unknown as typeof fetch;
    await expect(synthesize("Hello there.", fakeFetch)).rejects.toThrow("ElevenLabs returned 429");
  });
});

describe("RevenueCat (desktop purchases)", () => {
  it("maps an active entitlement to its plan and ignores expired ones", async () => {
    const { revenueCatPlan } = await import("../src/entitlements.js");
    process.env.REVENUECAT_SECRET_KEY = "sk_test";
    const now = Date.parse("2026-10-03T00:00:00Z");
    const reply = (entitlements: Record<string, unknown>) => (async () =>
      new Response(JSON.stringify({ subscriber: { entitlements } }), { status: 200 })) as unknown as typeof fetch;
    expect(await revenueCatPlan("u1", now, reply({ pro: { expires_date: "2026-11-01T00:00:00Z" } }))).toBe("pro");
    expect(await revenueCatPlan("u2", now, reply({ proplus: { expires_date: "2026-09-01T00:00:00Z" } }))).toBe("free");
    expect(await revenueCatPlan("u3", now, reply({ pro: { expires_date: null }, proplus: { expires_date: "2027-01-01T00:00:00Z" } }))).toBe("proplus");
    delete process.env.REVENUECAT_SECRET_KEY;
    expect(await revenueCatPlan("u4", now, reply({ pro: {} }))).toBe("free");
  });
});
