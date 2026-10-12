import { describe, expect, it } from "vitest";
import { inventedNumbers, missingEssentials, parseTLDR, summarize, summarizeTLDR, tidy, tldrTargetWords, type Notes } from "../src/summarize.js";

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

const ANSWER = {
  contentType: "news",
  mainPoint: "A cheaper, faster model launched for developers.",
  keyPoints: [
    { text: "About 40% cheaper than the previous model", mustKeep: ["40%"], importance: 3 },
    { text: "logit_bias and best_of are no longer supported", mustKeep: ["logit_bias", "best_of"], importance: 3 },
    { text: "Old model shuts down March 14, 2027", mustKeep: ["March 14, 2027"], importance: 3 },
    { text: "Launch was streamed", mustKeep: ["livestream"], importance: 1 },
  ],
};
const answer = (narration: string) => JSON.stringify({ ...ANSWER, narration });

const NEWS = `Nimbus Labs launched a new model for developers today. It is about 40% cheaper than the previous model, with similar quality on the company's own tests. ` +
  `Two older parameters, logit_bias and best_of, are no longer supported, so some apps will need changes before they switch. ` +
  `The old model keeps working until March 14, 2027, after which requests to it will fail. The launch event was streamed online, and the company ` +
  `recommends testing on a staging environment first because response formats can differ, especially for JSON.`;

describe("TL;DR pipeline", () => {
  process.env.GROQ_API_KEY = "gsk-test";

  it("reads everything, lists the key points and explains them, in one call", async () => {
    const complete = "Basically, the new model is about 40% cheaper with similar quality. The catch: logit_bias and best_of are gone, and the old model shuts down on March 14, 2027.";
    const { calls, fetchImpl } = fakeGroq([answer(complete)]);
    const result = await summarizeTLDR(NEWS, "detailed", fetchImpl);
    expect(result.summary).toBe(complete);
    expect(calls).toHaveLength(1);
    expect(calls[0].response_format).toEqual({ type: "json_object" });
    const request = calls[0].messages[1].content;
    expect(request).toContain("Read the ENTIRE text below");
    expect(request).toContain("Cover EVERY importance-3 point");
    expect(request).toMatch(/about \d+ words and never more than \d+/);
    expect(request).toContain("TEXT:\n" + NEWS.slice(0, 40));
    // The highlights are the important key points, in the text's order.
    expect(result.highlights).toEqual([
      "About 40% cheaper than the previous model",
      "logit_bias and best_of are no longer supported",
      "Old model shuts down March 14, 2027",
    ]);
  });

  it("adds back essentials the TL;DR dropped, and only those", async () => {
    const dropped = "The new model is cheaper and faster. Older parameters are gone.";
    const fixed = "The new model is about 40% cheaper. logit_bias and best_of are gone, and the old one shuts down on March 14, 2027.";
    const { calls, fetchImpl } = fakeGroq([answer(dropped), fixed]);
    expect(await summarize(NEWS, "detailed", fetchImpl)).toBe(fixed);
    expect(calls).toHaveLength(2);
    const repair = calls[1].messages[1].content;
    expect(repair).toContain("must include: 40%");
    expect(repair).toContain("logit_bias, best_of");
    expect(repair).toContain("March 14, 2027");
    expect(repair).not.toContain("livestream");
  });

  it("corrects numbers that aren't in the source", async () => {
    const wrong = "It's about 45% cheaper. logit_bias and best_of are gone, and the old model shuts down on March 14, 2027.";
    const { calls, fetchImpl } = fakeGroq([answer(wrong), "Fixed."]);
    await summarize(NEWS, "detailed", fetchImpl);
    expect(calls[1].messages[1].content).toContain("numbers that are not in the source: 45");
  });

  it("falls back to one careful call if the answer can't be read", async () => {
    const { calls, fetchImpl } = fakeGroq(["not json", "A direct explanation."]);
    expect(await summarize(LONG, "detailed", fetchImpl)).toBe("A direct explanation.");
    expect(calls).toHaveLength(2);
    expect(calls[1].messages[1].content).toContain("Keep every important point");
  });

  it("keeps very short messages to a single plain call", async () => {
    const { calls, fetchImpl } = fakeGroq(["Meeting moved to 6."]);
    await summarize("Hey! The meeting moved to 6 because the client is late. Bring the contract please.", "detailed", fetchImpl);
    expect(calls).toHaveLength(1);
    expect(calls[0].response_format).toBeUndefined();
  });

  it("waits and retries once when Groq asks to slow down", async () => {
    let n = 0;
    const fetchImpl = (async () => {
      n++;
      if (n === 1) return new Response(JSON.stringify({ error: { message: "Rate limit reached. Please try again in 0.01s." } }), { status: 429 });
      return new Response(JSON.stringify({ choices: [{ message: { content: "Meeting moved to 6." } }] }));
    }) as unknown as typeof fetch;
    expect(await summarize("Hey! The meeting moved to 6 because the client is late. Bring the contract please.", "detailed", fetchImpl)).toBe("Meeting moved to 6.");
    const busy = (async () => new Response(JSON.stringify({ error: { message: "Please try again in 40s." } }), { status: 429 })) as unknown as typeof fetch;
    await expect(summarize(LONG, "detailed", busy)).rejects.toMatchObject({ rateLimited: true });
  });
});

describe("plain output", () => {
  it("turns thin spaces and non-breaking hyphens into plain characters", () => {
    expect(tidy("It's 40\u202F% cheaper, a 30\u2011day window, on 20\u00A0October.")).toBe("It's 40% cheaper, a 30-day window, on 20 October.");
  });
  it("aims for about 40% of a short text, and keeps growing more slowly for long ones", () => {
    expect(tldrTargetWords(60)).toBe(45);
    expect(tldrTargetWords(300)).toBe(120);
    expect(tldrTargetWords(875)).toBe(350);
    // A 10-page paper gets a few minutes, not the same as a long email.
    expect(tldrTargetWords(2400)).toBe(533);
    expect(tldrTargetWords(5000)).toBe(845);
    expect(tldrTargetWords(20000)).toBe(900);
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

  it("finds numbers the source doesn't have", () => {
    expect(inventedNumbers("It costs $1,200 and 40% less, from 11:00, two weeks.", "costs 1200 dollars, 40 percent less, at 11:00")).toEqual([]);
    expect(inventedNumbers("It's 45% cheaper.", "It's 40% cheaper.")).toEqual(["45"]);
  });

  it("parses the answer even with text around the JSON, and rejects empty ones", () => {
    expect(parseTLDR(`Here you go:\n${answer("Okay.")}\nDone`)?.points).toHaveLength(4);
    expect(parseTLDR(JSON.stringify({ keyPoints: [], narration: "x" }))).toBeNull();
    expect(parseTLDR(JSON.stringify({ ...ANSWER, narration: "" }))).toBeNull();
    expect(parseTLDR(JSON.stringify({ ...ANSWER, contentType: "weird", narration: "x" }))?.contentType).toBe("other");
  });
});

describe("empty model replies", () => {
  process.env.GROQ_API_KEY = "gsk-test";

  it("asks again with less thinking when the model says nothing", async () => {
    const { calls, fetchImpl } = fakeGroq(["", "Short and clear."]);
    expect(await summarize("Lunch moved to Friday at one, bring the slides.", "detailed", fetchImpl)).toBe("Short and clear.");
    expect(calls.map((c) => c.reasoning_effort)).toEqual(["medium", "low"]);
  });

  it("falls back to a direct explanation when the TL;DR comes back empty", async () => {
    const { calls, fetchImpl } = fakeGroq(["", "", "Direct explanation."]);
    expect(await summarize(LONG, "detailed", fetchImpl)).toBe("Direct explanation.");
    expect(calls).toHaveLength(3);
  });
});
