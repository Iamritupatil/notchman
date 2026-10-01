import { describe, expect, it } from "vitest";
import { missingEssentials, parseNotes, summarize, SINGLE_PASS_WORDS, type Notes } from "../src/summarize.js";

const LONG = Array.from({ length: 40 }, (_, i) =>
  `Sentence ${i + 1} explains a detail of the new model launch, its pricing, latency and migration plan for developers.`).join(" ");

const NOTES: Notes = {
  contentType: "news",
  mainPoint: "A cheaper, faster model launched for developers.",
  points: [
    { kind: "number", text: "About 40% cheaper than the previous model with similar quality.", mustKeep: ["40%"], importance: 3 },
    { kind: "caveat", text: "Two older parameters, logit_bias and best_of, are no longer supported.", mustKeep: ["logit_bias", "best_of"], importance: 3 },
    { kind: "deadline", text: "The old model shuts down on March 14, 2027.", mustKeep: ["March 14, 2027"], importance: 3 },
    { kind: "context", text: "The launch event was streamed.", mustKeep: ["livestream"], importance: 1 },
  ],
};

/** A fake Groq that answers each stage in turn and records what it was asked. */
function fakeGroq(replies: string[]) {
  const calls: { messages: { role: string; content: string }[]; response_format?: unknown; reasoning_effort?: string }[] = [];
  const fetchImpl = (async (_url: string, init: RequestInit) => {
    calls.push(JSON.parse(String(init.body)));
    const content = replies[Math.min(calls.length - 1, replies.length - 1)];
    return new Response(JSON.stringify({ choices: [{ message: { content } }] }));
  }) as unknown as typeof fetch;
  return { calls, fetchImpl };
}

describe("TL;DR pipeline", () => {
  process.env.GROQ_API_KEY = "gsk-test";

  it("understands first (structured notes), then explains from them", async () => {
    const complete = "Basically, the new model is about 40 percent cheaper with similar quality. The catch: logit_bias and best_of are gone, and the old model shuts down on March 14, 2027.";
    const { calls, fetchImpl } = fakeGroq([JSON.stringify(NOTES), complete]);
    expect(await summarize(LONG, "detailed", fetchImpl)).toBe(complete);
    expect(calls).toHaveLength(2);
    // Stage 1 asks for JSON notes covering everything material.
    expect(calls[0].response_format).toEqual({ type: "json_object" });
    expect(calls[0].messages[1].content).toContain("Read the ENTIRE text below carefully");
    // Stage 2 gets the notes, the source and the guide for this content type.
    const request = calls[1].messages[1].content;
    expect(request).toContain('"mustKeep":["40%"]');
    expect(request).toContain("SOURCE:\n" + LONG.slice(0, 40));
    expect(request).toContain("News or informational content");
    expect(request).toContain("Organise it for understanding, not in the source's order");
    expect(request).toContain("what important information would the listener still not know");
  });

  it("adds back essentials the explanation dropped (coverage check)", async () => {
    const dropped = "The new model is cheaper and faster. Older parameters are gone.";
    const fixed = "The new model is about 40% cheaper. logit_bias and best_of are gone, and the old one shuts down on March 14, 2027.";
    const { calls, fetchImpl } = fakeGroq([JSON.stringify(NOTES), dropped, fixed]);
    expect(await summarize(LONG, "detailed", fetchImpl)).toBe(fixed);
    expect(calls).toHaveLength(3);
    const repair = calls[2].messages[1].content;
    expect(repair).toContain("must include: 40%");
    expect(repair).toContain("logit_bias, best_of");
    expect(repair).toContain("March 14, 2027");
    // Minor points aren't forced back in.
    expect(repair).not.toContain("livestream");
  });

  it("falls back to one careful call if the notes can't be read", async () => {
    const { calls, fetchImpl } = fakeGroq(["not json", "A direct explanation."]);
    expect(await summarize(LONG, "detailed", fetchImpl)).toBe("A direct explanation.");
    expect(calls).toHaveLength(2);
    expect(calls[1].messages[1].content).toContain("not sentence by sentence");
  });

  it("keeps short messages to a single call", async () => {
    const { calls, fetchImpl } = fakeGroq(["Meeting moved to 6."]);
    await summarize("Hey! The meeting moved to 6 because the client is late. Bring the contract please.", "detailed", fetchImpl);
    expect(calls).toHaveLength(1);
    expect(SINGLE_PASS_WORDS).toBeGreaterThan(50);
  });
});

describe("coverage check", () => {
  it("accepts numbers said differently", () => {
    const notes: Notes = { contentType: "other", points: [
      { kind: "number", text: "x", mustKeep: ["40%", "$1,200", "11:00", "2,500 users"], importance: 3 },
    ] };
    expect(missingEssentials(notes, "It's 40 percent cheaper, costs 1200 dollars, starts at 11 00, and 2500 users joined.")).toEqual([]);
    expect(missingEssentials(notes, "It's much cheaper and starts at eleven.")[0].missing).toEqual(["40%", "$1,200", "11:00", "2,500 users"]);
  });

  it("checks names and terms loosely but catches omissions", () => {
    const notes: Notes = { contentType: "other", points: [
      { kind: "fact", text: "x", mustKeep: ["Retrieval-Augmented Generation", "Priya Sharma"], importance: 2 },
    ] };
    expect(missingEssentials(notes, "Retrieval augmented generation, as Priya Sharma explained, lets the AI look things up.")).toEqual([]);
    expect(missingEssentials(notes, "It lets the AI look things up.")[0].missing).toEqual(["Retrieval-Augmented Generation", "Priya Sharma"]);
  });

  it("parses notes even with text around the JSON, and rejects empty notes", () => {
    expect(parseNotes(`Here you go:\n${JSON.stringify(NOTES)}\nDone`)?.points).toHaveLength(4);
    expect(parseNotes('{"points": []}')).toBeNull();
    expect(parseNotes(JSON.stringify({ ...NOTES, contentType: "weird" }))?.contentType).toBe("other");
  });
});
