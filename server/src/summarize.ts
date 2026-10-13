import { targetWords, type SummaryLength } from "./plans.js";

/**
 * Notchman's TL;DR: an explanation, not a shortened copy.
 *
 * The goal is the "one-shot lecture before an exam": the listener skips the
 * original and still understands everything important in it. A single
 * "summarize this" call tends to walk the text top to bottom and compress
 * sentences, which keeps the wording but loses the understanding. So longer
 * texts go through stages:
 *
 *   1. Understand and explain, in one call: the model reads the whole text,
 *      lists its key points (each with the exact numbers, dates and names
 *      that must survive) and writes the spoken TL;DR that covers every one.
 *      The key points are also the highlights the apps show.
 *   2. Check in code: every essential number, date, name and term is in the
 *      TL;DR, and the TL;DR has no number the source doesn't have.
 *   3. Repair (only if the check failed): add what's missing, fix what's wrong.
 *
 * One call instead of several keeps a TL;DR inside Groq's per-minute limits.
 * Length follows information density: one short sentence per key point.
 */

/** Keep in sync with SummarizationPrompt.instructions in the app (on-device fallback). */
export const INSTRUCTIONS = `You are Notchman. People press one key on something long they copied (a message, an AI answer, a post, an article) and listen to your explanation instead of reading it. They are saying: "save my time, but don't make me stupid."

Your job is to explain, not to shorten. Understand the whole text first, work out everything the listener genuinely needs to know, then explain it in the shortest clear spoken form. Like a great one-shot lecture before an exam: the listener should finish thinking "I didn't read it, but I understand what it said and I didn't miss anything important."

Keep everything material: the main point, important claims and the arguments behind them, facts, numbers, dates, names that matter, reasons, causes and effects, comparisons, decisions, instructions and steps, recommendations, warnings, limitations, caveats, exceptions, conditions, dependencies, deadlines, action items, conclusions, and opposing views. If dropping a detail could make the listener misunderstand the original, or would change the conclusion, keep it. If a number, date or condition matters, keep it exactly.

Remove aggressively: greetings, filler, repetition, restated conclusions, promotional language, decorative adjectives, stories that add no information, redundant examples, meta commentary, links, formatting noise.

Explain, don't paraphrase:
- Do not go sentence by sentence and do not keep the original order if another order is clearer. Lead with what matters most.
- Explain difficult terms in plain words the first time they come up, without losing technical accuracy.
- Add a tiny example or analogy only when it clearly helps understanding, and never one that adds facts.
- Show how points connect: why something matters, what causes what, what depends on what.

Stay faithful:
- Never invent facts, numbers, quotes, causes, conclusions or recommendations.
- Keep the original's certainty. "May", "likely", "in some cases", "according to" stay as they are; never turn a possibility into a certainty or an opinion into a fact.
- Keep legal, financial and technical meaning exact.

Write for the ear:
- Natural spoken sentences, like a very smart friend explaining it. No bullet points, headings, markdown, numbered lists, emoji or URLs, and never say things like "point number one" or "here's a summary".
- Sound like someone talking, not a report. For anything longer than a few sentences, you may open with one short orienting line ("Okay, here's what matters.", "So, the short version:"), varied and never for short messages.
- Use natural transitions where they help ("Basically…", "Here's why that matters…", "The catch is…", "So the takeaway is…"), each at most once, never one per sentence.
- Keep each sentence short enough to say in one breath (about 25 words at most), one idea per sentence. No run-on sentences, no long parentheses, no semicolons or slashes. Put a paragraph break between topics; it becomes a natural pause.
- Write numbers, amounts, percentages, dates and times in digits exactly as the text has them ("31%", "₹4.5 lakh", "17 March", "5 pm"); the voice reads digits naturally.
- Length follows the information: a padded post may need two sentences, a dense explanation several minutes. Never pad, never cut something important to be shorter.
- Always answer in the same language as the text.`;

/** How to shape the explanation for each kind of content. */
const CONTENT_GUIDES: Record<string, string> = {
  social_post: "A social media post: give the main claim, the reasoning and evidence behind it, the important numbers or examples, and the lesson or takeaway. Skip the hook-style framing and self-promotion.",
  ai_explanation: "An AI assistant's answer: keep every concept, the reasoning, the steps in order, the options and when each applies, caveats and the recommendation. Describe what any code does instead of reading it.",
  conversation: "A conversation or message: say who wants what, the decisions, requests, important details, dates, times, deadlines and action items, with just enough context. Make clear who needs to do what.",
  educational: "Educational content: act like a concise teacher. Cover every important concept, define terms simply, explain how ideas relate, and use a quick example where it helps.",
  research: "A research paper, study or report: the question and why it matters; how it was done (what kind of study, who or what was studied, how many, for how long, compared with what); every main result with its exact numbers; who it worked best or worst for; the limitations, doubts and conflicts of interest that change how much to trust it; and the conclusion and what it means in practice. Define technical terms simply.",
  news: "News or informational content: who, what, when, where, why, the consequences, and what is still uncertain or disputed.",
  argument: "An argument or debate: state the question, each side's position and its strongest reasons, where they agree or conflict, and the conclusion if there is one. Do not take sides the text didn't take.",
  document: "An email, document, policy or announcement: what it is about, what changes, who is affected, what they must do and by when, and any conditions or exceptions.",
  other: "Explain what the text is about and everything a reader would need from it.",
};

export const MAX_INPUT_CHARACTERS = 60_000;

/** Sent with each TL;DR; the apps keep cached TL;DRs only for the same version. */
export const SUMMARY_VERSION = "tldr-7";

/** Below this many words, a plain careful call covers everything (no key points). */
export const SINGLE_PASS_WORDS = 60;

export class UpstreamError extends Error {
  constructor(message: string, readonly rateLimited = false) {
    super(message);
  }
}

export function wordCount(text: string): number {
  return text.trim().split(/\s+/).filter(Boolean).length;
}

/** A TL;DR and its highlights (the key points, short, in order of importance). */
export interface TLDR {
  summary: string;
  highlights: string[];
}

// --- Key points --------------------------------------------------------------

export interface NotePoint {
  text: string;
  /** Exact numbers, dates, names or terms that must survive into the narration. */
  mustKeep?: string[];
  /** 3 = essential, 2 = important, 1 = minor. */
  importance?: number;
  kind?: string;
}

export interface Notes {
  contentType: string;
  mainPoint?: string;
  points: NotePoint[];
}

const SHAPES = Object.entries(CONTENT_GUIDES).filter(([k]) => k !== "other").map(([, v]) => `- ${v}`).join("\n");

/** Above this many words a text is "long" (a paper, a report, a long article). */
export const LONG_TEXT_WORDS = 1_500;

/**
 * About 40% of a short text's length: short, but room for every must-know
 * point. Long texts keep growing, more slowly, so a 10-page paper gets a few
 * minutes that cover it, not the same two minutes as a long email.
 */
export function tldrTargetWords(sourceWords: number): number {
  const base = Math.min(sourceWords, 875) * 0.4;
  const extra = Math.max(0, sourceWords - 875) * 0.12;
  return Math.max(45, Math.min(900, Math.round(base + extra)));
}

/** How many key points (and must-know ones) a text of this length usually has. */
function pointCounts(sourceWords: number): { all: string; essential: string } {
  if (sourceWords > LONG_TEXT_WORDS) return { all: "12 to 24", essential: "6 to 14" };
  if (sourceWords > 600) return { all: "6 to 15", essential: "4 to 9" };
  return { all: "3 to 12", essential: "3 to 7" };
}

/** How many highlights the apps show. */
export function maxHighlights(sourceWords: number): number {
  return sourceWords > LONG_TEXT_WORDS ? 18 : 10;
}

function tldrRequest(sourceWords: number): string {
  const target = tldrTargetWords(sourceWords);
  const counts = pointCounts(sourceWords);
  const long = sourceWords > LONG_TEXT_WORDS;
  return `Read the ENTIRE text below before writing anything. Then return JSON only, in this shape:

{
  "contentType": one of "social_post", "ai_explanation", "conversation", "educational", "research", "news", "argument", "document", "other",
  "mainPoint": the central message, in one sentence,
  "keyPoints": [
    {
      "text": the point as a short highlight, at most 14 words, with its numbers, dates and names exactly as written,
      "mustKeep": [the exact numbers, amounts, percentages, dates, times, names and terms in this point],
      "importance": 3, 2 or 1 (see below)
    }
  ],
  "narration": the spoken TL;DR
}

keyPoints: every materially important point of the text. Include each number that matters, each date, time and deadline, each decision, request and action item (say who does what), each condition, exception, caveat, risk and recommendation, and the conclusion. Merge repeated points, skip greetings, filler, hype and self-promotion. Order by importance. Usually ${counts.all} points.${long ? " This is a long text: cover every part of it, not just the opening and the headline result (for a study: what was done, each main result, who it helped most, every limitation, and the conclusion)." : ""}

importance:
- 3 = must know: the main point, the key numbers (prices, amounts, percentages, results), dates and deadlines, decisions, who has to do what, warnings and changes that affect the listener, and any doubt or caveat that changes how much to trust a key claim (for example "the benchmark is the company's own", a study's limitations or a conflict of interest). Usually ${counts.essential} points.
- 2 = useful supporting detail.
- 1 = background or colour.

narration: the TL;DR to be read aloud, about ${target} words and never more than ${Math.round(target * 1.25)} (the text is about ${sourceWords} words). Someone who only hears it should be able to explain the text to a friend and answer questions about it. Start with the main point in one sentence. Cover EVERY importance-3 point with its numbers, dates and names exactly as written, then as many importance-2 points as fit.${long ? " Go through it in a clear order (for a study: the question, what was done, the results, who it helped most, the limitations, the conclusion), one short paragraph each." : ""} Pack related facts into one sentence ("It's 40% cheaper, scores 71.2% versus 68.9%, and starts at $20 a month"). Leave out importance-1 points, background, contact details, sign-offs and any closing sentence that repeats what was already said. End with the takeaway or what the listener has to do only if it adds something. No lists or markdown: natural spoken sentences. Numbers always in digits as the text has them (18 minutes, 12 weeks, $2), never spelled out. Never add a fact or number that isn't in the text, and keep the text's certainty ("may", "likely").

Shape it for the kind of text:
${SHAPES}

Use the text's language for every field.`;
}

/** The model's JSON answer, or null if it isn't usable. */
export function parseTLDR(raw: string): (Notes & { narration: string }) | null {
  const start = raw.indexOf("{");
  const end = raw.lastIndexOf("}");
  if (start < 0 || end <= start) return null;
  try {
    const value = JSON.parse(raw.slice(start, end + 1)) as Record<string, unknown>;
    const narration = typeof value.narration === "string" ? value.narration.trim() : "";
    const points = (Array.isArray(value.keyPoints) ? value.keyPoints : Array.isArray(value.points) ? value.points : [])
      .filter((p): p is NotePoint => Boolean(p) && typeof (p as NotePoint).text === "string" && Boolean((p as NotePoint).text.trim()))
      .map((p) => ({ ...p, mustKeep: Array.isArray(p.mustKeep) ? p.mustKeep.filter((t) => typeof t === "string") : [] }));
    if (!narration || !points.length) return null;
    const contentType = typeof value.contentType === "string" && value.contentType in CONTENT_GUIDES ? value.contentType : "other";
    return { contentType, mainPoint: typeof value.mainPoint === "string" ? value.mainPoint : undefined, points, narration };
  } catch {
    return null;
  }
}

/** The highlights the apps show: important points first, short. */
export function highlightsFrom(notes: Notes, max = 10): string[] {
  const ranked = notes.points
    .map((p, i) => ({ p, i }))
    .sort((a, b) => (b.p.importance ?? 2) - (a.p.importance ?? 2) || a.i - b.i);
  // The important points (up to `max`); minor ones only to reach 3.
  const important = ranked.filter(({ p }) => (p.importance ?? 2) >= 2);
  const chosen = (important.length >= 3 ? important : ranked.slice(0, Math.max(3, important.length))).slice(0, max);
  return chosen.sort((a, b) => a.i - b.i).map(({ p }) => p.text.trim().replace(/\s+/g, " "));
}

/** Essential tokens from the key points that the narration doesn't contain. */
export function missingEssentials(notes: Notes, narration: string): { point: NotePoint; missing: string[] }[] {
  const said = normalize(narration);
  const saidDigits = digitRuns(narration);
  const gaps: { point: NotePoint; missing: string[] }[] = [];
  for (const point of notes.points ?? []) {
    if ((point.importance ?? 2) < 2) continue;
    const missing = (point.mustKeep ?? []).filter((token) => typeof token === "string" && token.trim())
      .filter((token) => !mentions(token, said, saidDigits));
    if (missing.length) gaps.push({ point, missing });
  }
  return gaps;
}

/** Numbers in the TL;DR that the source doesn't have (likely invented or garbled). */
export function inventedNumbers(narration: string, source: string): string[] {
  const known = digitRuns(source);
  return [...digitRuns(narration)].filter((n) => !known.has(n) && !known.has(n.replace(/^0+(?=\d)/, "")) && !/^[0-9]$/.test(n));
}

function normalize(s: string): string {
  return s.toLowerCase().normalize("NFKD").replace(/[̀-ͯ]/g, "").replace(/[^\p{L}\p{N}%$€£₹.]+/gu, " ").trim();
}

function digitRuns(s: string): Set<string> {
  return new Set((s.replace(/(\d),(?=\d{3})/g, "$1").match(/\d+(?:\.\d+)?/g) ?? []));
}

/** Whether the narration mentions a token: numbers by their digits, words loosely. */
function mentions(token: string, said: string, saidDigits: Set<string>): boolean {
  const digits = token.replace(/(\d),(?=\d{3})/g, "$1").match(/\d+(?:\.\d+)?/g);
  if (digits) {
    // "40%" said as "40 percent", "$1,200" as "1,200 dollars", "11:00" as "11": all digits must be there.
    return digits.every((d) => saidDigits.has(d) || saidDigits.has(d.replace(/^0+(?=\d)/, "")) || /^0+$/.test(d));
  }
  const words = normalize(token).split(" ").filter((w) => w.length > 2);
  if (!words.length) return true;
  // Names and terms: most of their words appear (allows "the API" vs "API").
  const found = words.filter((w) => said.includes(w)).length;
  return found / words.length >= 0.6;
}

// --- Model calls -------------------------------------------------------------

type Fetch = typeof fetch;
const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

/**
 * For texts too long for the main model's per-minute token limit on Groq's
 * free tier (8,000 tokens, prompt and reply together): this one allows 30,000.
 */
export const LONG_TEXT_MODEL = process.env.GROQ_LONG_MODEL ?? "meta-llama/llama-4-scout-17b-16e-instruct";

async function complete(fetchImpl: Fetch, messages: { role: string; content: string }[],
                        options: { effort: "low" | "medium" | "high"; json?: boolean; maxTokens?: number; model?: string },
                        attempt = 0): Promise<string> {
  const apiKey = process.env.GROQ_API_KEY;
  if (!apiKey) throw new UpstreamError("GROQ_API_KEY is not configured on the server.");
  const model = options.model ?? process.env.GROQ_MODEL ?? "openai/gpt-oss-120b";
  const response = await fetchImpl("https://api.groq.com/openai/v1/chat/completions", {
    method: "POST",
    headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model,
      ...(model.startsWith("openai/gpt-oss") ? { reasoning_effort: options.effort } : {}),
      max_completion_tokens: options.maxTokens ?? 8_000,  // see "request too large" below
      ...(options.json ? { response_format: { type: "json_object" } } : {}),
      messages,
    }),
  });
  const body = (await response.json().catch(() => ({}))) as {
    choices?: { message?: { content?: string } }[];
    error?: { message?: string };
  };
  // On Groq's free tier the reply budget counts against the per-minute token
  // limit too, so a long text can be "too large" as asked. If a smaller reply
  // (8,000 → 4,000 → 2,000 tokens) would fit, ask for that; if the text alone
  // is too long for it, use the long-text model.
  const maxTokens = options.maxTokens ?? 8_000;
  const tooLarge = body.error?.message ?? "";
  if (/request too large/i.test(tooLarge)) {
    const [, limit, requested] = /Limit (\d+), Requested (\d+)/i.exec(tooLarge)?.map(Number) ?? [];
    const promptTokens = requested - maxTokens;  // NaN when Groq doesn't say
    if (maxTokens > 2_500 && !(promptTokens + 2_000 > limit)) {
      console.warn("groq: request too large, asking for a smaller reply", maxTokens);
      return complete(fetchImpl, messages, { ...options, maxTokens: Math.round(maxTokens / 2) }, attempt);
    }
    if (model !== LONG_TEXT_MODEL) {
      console.warn("groq: text too long for", model, "so using", LONG_TEXT_MODEL, { promptTokens, limit });
      return complete(fetchImpl, messages, { ...options, model: LONG_TEXT_MODEL, maxTokens: 8_000 }, attempt);
    }
  }
  if (response.status === 429) {
    // Groq's per-minute limit: wait as long as it asks (if that's short) and try once more.
    const wait = Number(/try again in ([\d.]+)s/i.exec(body.error?.message ?? "")?.[1] ?? response.headers.get("retry-after") ?? NaN);
    if (attempt === 0 && Number.isFinite(wait) && wait <= 12) {
      await sleep(Math.ceil(wait * 1000) + 300);
      return complete(fetchImpl, messages, options, attempt + 1);
    }
    throw new UpstreamError(body.error?.message ?? "Groq rate limit", true);
  }
  if (!response.ok) throw new UpstreamError(body.error?.message ?? `Groq returned ${response.status}`);
  const content = body.choices?.[0]?.message?.content?.trim();
  if (!content) {
    // The model sometimes spends the whole reply thinking and says nothing:
    // ask once more with less thinking before giving up.
    if (options.effort !== "low") return complete(fetchImpl, messages, { ...options, effort: "low" }, attempt);
    throw new UpstreamError("Groq returned an empty response.");
  }
  return content;
}

/**
 * Summarizes text for listening. `detailed` (the default, "Complete") has no
 * duration target. The timed lengths are upper limits kept for older apps.
 */
export async function summarize(text: string, length: SummaryLength, fetchImpl: Fetch = fetch): Promise<string> {
  return (await summarizeTLDR(text, length, fetchImpl)).summary;
}

/** The TL;DR and its highlights. */
export async function summarizeTLDR(text: string, length: SummaryLength, fetchImpl: Fetch = fetch): Promise<TLDR> {
  const input = text.slice(0, MAX_INPUT_CHARACTERS);
  const sourceWords = wordCount(input);

  if (length !== "detailed") {
    const summary = await complete(fetchImpl, [
      { role: "system", content: INSTRUCTIONS },
      { role: "user", content: `Explain the following text in about ${targetWords(length, sourceWords)} spoken words. Include every key point even if that takes more words.\n\nTEXT:\n${input}` },
    ], { effort: "medium" });
    return { summary, highlights: [] };
  }

  const direct = async (effort: "low" | "medium") => ({
    summary: tidy(await complete(fetchImpl, [
      { role: "system", content: INSTRUCTIONS },
      { role: "user", content: `Explain the following text for listening. Read all of it first. Keep every important point with its numbers, dates, names and conditions exactly as written, and drop only what adds nothing. Be much shorter than the text, but complete. Reply with only the narration.\n\nTEXT:\n${input}` },
    ], { effort })),
    highlights: [],
  });

  if (sourceWords < SINGLE_PASS_WORDS) return direct("medium");

  // 1. Key points and narration, in one call.
  let result: (Notes & { narration: string }) | null = null;
  try {
    result = parseTLDR(await complete(fetchImpl, [
      { role: "system", content: INSTRUCTIONS },
      { role: "user", content: `${tldrRequest(sourceWords)}\n\nTEXT:\n${input}` },
    ], { effort: "medium", json: true }));
  } catch (error) {
    if (error instanceof UpstreamError && error.rateLimited) throw error;
    console.warn("tldr failed", error instanceof Error ? error.message : error);
  }
  if (!result) return direct("low");

  // 2. Check in code; 3. repair only if something essential is missing or wrong.
  let narration = result.narration;
  // The must-know points have to be heard; the others are in the highlights.
  const gaps = missingEssentials({ ...result, points: result.points.filter((p) => (p.importance ?? 2) >= 3) }, narration);
  const invented = inventedNumbers(narration, input);
  if (gaps.length || invented.length) {
    const problems = [
      ...(gaps.length ? ["It left out these important points (include them, with these exact details):",
        ...gaps.map((g) => `- ${g.point.text} (must include: ${g.missing.join(", ")})`)] : []),
      ...(invented.length ? [`It has numbers that are not in the source: ${invented.join(", ")}. Correct or remove them.`] : []),
    ].join("\n");
    try {
      narration = await complete(fetchImpl, [
        { role: "system", content: INSTRUCTIONS },
        { role: "user", content: `Fix this spoken TL;DR.\n\n${problems}\n\nKeep everything else that is already there, stay about as short as it is now (pack the additions into existing sentences where you can), add no filler, and keep numbers exactly as the source has them.\n\nTL;DR:\n${narration}\n\nSOURCE (for accuracy):\n${input}\n\nReply with only the fixed TL;DR.` },
      ], { effort: "low" });
    } catch (error) {
      if (error instanceof UpstreamError && error.rateLimited) {
        console.warn("repair skipped: rate limited");
      } else {
        console.warn("repair failed", error instanceof Error ? error.message : error);
      }
    }
  }
  return { summary: tidy(narration), highlights: highlightsFrom(result, maxHighlights(sourceWords)).map(tidy) };
}

/** Plain characters for the voice and the apps: models like thin spaces and non-breaking hyphens. */
export function tidy(text: string): string {
  return text
    .replace(/[\u00A0\u2007\u2009\u202F]/g, " ")
    .replace(/[\u2010\u2011]/g, "-")
    .replace(/(\d) +%/g, "$1%")
    .replace(/[ \t]+\n/g, "\n")
    .replace(/[ \t]{2,}/g, " ")
    .trim();
}
