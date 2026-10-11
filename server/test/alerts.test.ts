import { describe, expect, it } from "vitest";
import { alertOnce, countVoice, usageCheck, usageReport } from "../src/alerts.js";
import { handleSpeak } from "../src/handlers.js";
import { MemoryQuotaStore } from "../src/quota.js";

const NOW = new Date(Date.UTC(2026, 9, 9, 10, 0));

function inbox() {
  const mails: { subject: string; message: string }[] = [];
  return { mails, notify: async (subject: string, message: string) => { mails.push({ subject, message }); } };
}

describe("owner alerts", () => {
  it("sends each alert once", async () => {
    const store = new MemoryQuotaStore();
    const { mails, notify } = inbox();
    expect(await alertOnce(store, "x", "Hi", "Body", NOW, notify)).toBe(true);
    expect(await alertOnce(store, "x", "Hi", "Body", NOW, notify)).toBe(false);
    expect(mails).toHaveLength(1);
  });

  it("emails at 50%, 80% and 95% of the month's ElevenLabs budget, once each, with the details", async () => {
    const store = new MemoryQuotaStore();
    const { mails, notify } = inbox();
    const options = { budget: 1000, notify, balance: async () => 26_000, subscribers: async () => ({ pro: 3, proplus: 1 }) };
    await countVoice(store, 300, false, NOW);
    expect((await usageCheck(store, NOW, options)).sent).toEqual([]);
    await countVoice(store, 250, true, NOW);
    expect((await usageCheck(store, NOW, options)).sent).toEqual(["budget 50%"]);
    expect((await usageCheck(store, NOW, options)).sent).toEqual([]);
    await countVoice(store, 420, false, NOW); // jumps past 80% and 95%: one email
    expect((await usageCheck(store, NOW, options)).sent).toEqual(["budget 95%"]);
    expect(mails.map((m) => m.subject)).toEqual([
      "Notchman: ElevenLabs voice at 55% of this month's budget",
      "Notchman: ElevenLabs voice at 97% of this month's budget",
    ]);
    expect(mails[1].message).toContain("Free users: 720 characters");
    expect(mails[1].message).toContain("Paying users: 250 characters");
    expect(mails[1].message).toContain("ElevenLabs credits left: 26,000");
    expect(mails[1].message).toContain("3 Pro ($14.97/mo) and 1 Pro+ ($9.99/mo)");
  });

  it("warns when ElevenLabs credits run low, and explains when the balance can't be read", async () => {
    const store = new MemoryQuotaStore();
    const { mails, notify } = inbox();
    expect((await usageCheck(store, NOW, { budget: 27_000, notify, balance: async () => 2_000 })).sent).toEqual(["low balance"]);
    expect(mails[0].subject).toBe("Notchman: only 2,000 ElevenLabs credits left");
    const report = await usageReport(store, NOW, { budget: 27_000, balance: async () => undefined });
    expect(report.text).toContain('"User: Read" permission');
  });

  it("counts every Notchman-voice character, and tells the owner once when free users hit the daily cap", async () => {
    const store = new MemoryQuotaStore();
    const { mails, notify } = inbox();
    const synthesize = async () => ({ audioBase64: "QUJD", format: "mp3" as const, characters: 3, voiceId: "EXAVITQu4vr4xnSDxMaL" });
    const free = async () => ({ plan: "free" as const, accountKey: `user:${Math.random()}` });
    const deps = { store, synthesize, entitlement: free, freeTrialVoiceCharacters: 5000, globalDailyVoiceCharacters: 60, notify, now: () => NOW };
    const text = "Your interview moved to Friday at eleven.";
    expect((await handleSpeak("a", { text }, deps)).ok).toBe(true);
    expect((await handleSpeak("b", { text }, deps)).ok).toBe(false);
    expect((await handleSpeak("c", { text }, deps)).ok).toBe(false);
    expect(await store.count("elmonth_free_2026-10")).toBe(text.length);
    expect(mails.map((m) => m.subject)).toEqual(["Notchman: free users reached today's ElevenLabs cap"]);
  });

  it("keeps free users inside their monthly share, so paying users always have the Notchman voice", async () => {
    const store = new MemoryQuotaStore();
    const { mails, notify } = inbox();
    const synthesize = async () => ({ audioBase64: "QUJD", format: "mp3" as const, characters: 3, voiceId: "EXAVITQu4vr4xnSDxMaL" });
    const text = "Your interview moved to Friday at eleven.";
    const base = { store, synthesize, freeTrialVoiceCharacters: 5000, freeMonthlyVoiceCharacters: text.length, notify, now: () => NOW };
    const free = { ...base, entitlement: async () => ({ plan: "free" as const, accountKey: `user:${Math.random()}` }) };
    const paid = { ...base, entitlement: async () => ({ plan: "pro" as const, accountKey: "sub:1" }) };
    expect((await handleSpeak("a", { text }, free)).ok).toBe(true);
    const second = await handleSpeak("b", { text }, free);
    expect(second.ok).toBe(false);
    expect(second.ok ? undefined : second.details?.reason).toBe("free_month");
    expect((await handleSpeak("c", { text }, paid)).ok).toBe(true);
    expect(mails.map((m) => m.subject)).toEqual(["Notchman: free users reached this month's Notchman-voice share"]);
  });
});
