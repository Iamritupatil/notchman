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

import { APIError } from "@anthropic-ai/sdk";
import { AnthropicBedrockMantle } from "@anthropic-ai/bedrock-sdk";
import { BedrockRuntimeClient, ConverseCommand } from "@aws-sdk/client-bedrock-runtime";

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

Sound like a person, not a report:
- Talk like a smart friend who just read it for the listener and is telling them over coffee: warm, relaxed, confident, plain words. Use contractions (it's, they're, you'll) and speak to the listener as "you" when it fits.
- Shape it like a great one-shot lecture: first the context and the bottom line in one or two sentences (what this is, who is telling the listener what, and what it comes down to), then the ideas in the order that makes them easiest to follow, each in plain words with why it matters.
- Lead the listener somewhere. Finish with where this leaves them: what they need to do or decide next, or the one thing to remember, in new words and never a repeat. Leave it out only for a plain story or news with nothing to act on. The listener should never end up wondering "so what do I do now?"
- Translate jargon, names of files, tools and commands into what they mean for the listener. Not "656 tests passed and Docker was skipped" but "everything that could be tested works".
- Vary the rhythm: mix short sentences with medium ones. One idea per sentence, about 20 words at most. No run-ons, no long parentheses, no semicolons or slashes. Put a paragraph break between topics; it becomes a natural pause.
- Never sound like a summary of a document. Don't say "the text", "the author", "the article", "the post", "this message", "it discusses", "it highlights", "it mentions", "it also notes", "the writer explains". Just say the thing itself: not "The author argues that remote work boosts output" but "Remote work actually boosts output."
- No stiff connectors: never "Additionally", "Furthermore", "Moreover", "In conclusion", "Overall", "In summary", "It is important to note". Use spoken ones instead, each at most once and only where they help: "So…", "Basically…", "Here's the thing…", "The catch is…", "That matters because…", "Bottom line:".
- Never speak as the writer. When the text is someone's own story or post, tell it about them: not "I quit my job" but "This founder quit their job" (use their name if the text gives it).
- Don't stack facts. At most two numbers in a sentence; spread the rest out and say what each one means ("that's about half"). Skip statistical notation (confidence intervals, p-values, effect sizes) unless the listener truly needs it: say "a clear, reliable difference" instead.
- No bullet points, headings, markdown, numbered lists, emoji or URLs, and never "point number one" or "here's a summary".
- Write numbers, amounts, percentages, dates and times in digits exactly as the text has them ("31%", "₹4.5 lakh", "17 March", "5 pm"); the voice reads digits naturally.
- Length follows the information: a padded post may need two sentences, a dense explanation several minutes. Never pad, never cut something important to be shorter.
- Always answer in the same language as the text.`;

/** How to shape the explanation for each kind of content. */
const CONTENT_GUIDES: Record<string, string> = {
  social_post: "A social media post: give the main claim, the reasoning and evidence behind it, the important numbers or examples, and the lesson or takeaway. Skip the hook-style framing and self-promotion.",
  ai_explanation: "An AI assistant's answer: keep every concept, the reasoning, the steps in order, the options and when each applies, caveats and the recommendation. Describe what any code does instead of reading it.",
  work_report: "A report on work that was done, from an AI agent (like Claude Code or Codex), a developer or a teammate: first the bottom line (is it done, did it work); then what changed, in plain words and why it matters to the listener; then what is still broken, slow, risky or unconfirmed; and last, each decision or question waiting for the listener, with the options and the recommendation, so they know exactly what to answer. Talk about whoever did the work by name (\"Claude couldn't check why\"), never as \"I\". Never read out test counts, library, file or tool names, paths or commands: say what they mean (\"the tests pass, apart from a few that couldn't run on this computer\").",
  conversation: "A conversation or message: say who wants what, the decisions, requests, important details, dates, times, deadlines and action items, with just enough context. Make clear who needs to do what.",
  educational: "Educational content: act like a concise teacher. Cover every important concept, define terms simply, explain how ideas relate, and use a quick example where it helps.",
  research: "A research paper, study or report, explained like a good teacher would: the question and why it matters; how it was done in plain words (what kind of study, who, how many, for how long, compared with what); the main results with their key numbers (not every statistic); who it worked best or worst for; the limitations, doubts and conflicts of interest that change how much to trust it; and what it means in practice. Define technical terms simply.",
  news: "News or informational content: who, what, when, where, why, the consequences, and what is still uncertain or disputed.",
  argument: "An argument or debate: state the question, each side's position and its strongest reasons, where they agree or conflict, and the conclusion if there is one. Do not take sides the text didn't take.",
  document: "An email, document, policy or announcement: what it is about, what changes, who is affected, what they must do and by when, and any conditions or exceptions.",
  other: "Explain what the text is about and everything a reader would need from it.",
};

export const MAX_INPUT_CHARACTERS = 60_000;

/** Sent with each TL;DR; the apps keep cached TL;DRs only for the same version. */
export const SUMMARY_VERSION = "tldr-9";

/** Below this many words, a plain careful call covers everything (no key points). */
export const SINGLE_PASS_WORDS = 60;

export class UpstreamError extends Error {
  /** `tooLong`: the text alone is over Groq's per-minute token limit (free tier), so trying again won't help. */
  constructor(message: string, readonly rateLimited = false, readonly tooLong = false) {
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
  "contentType": one of "social_post", "ai_explanation", "work_report", "conversation", "educational", "research", "news", "argument", "document", "other",
  "mainPoint": the central message, in one sentence,
  "keyPoints": [
    {
      "text": the point as a short highlight, at most 14 words, with its numbers, dates and names exactly as written,
      "mustKeep": [the exact numbers, amounts, percentages, dates, times, names and terms in this point],
      "importance": 3, 2 or 1 (see below)
    }
  ],
  "bottomLine": how the spoken TL;DR opens, in one or two plain sentences: what this is and what it comes down to (for example "Claude fixed your short reel scripts, but the long ones still need work." or "Your interview moved to Friday, and you need to confirm by tonight."). Say "you" only for what is addressed to the listener (their email, their chat with an AI). Someone's own post or story is about them: "This founder quit their job…", never "You quit…",
  "narration": the middle of the spoken TL;DR (see below), which comes right after bottomLine,
  "nextStep": how the spoken TL;DR ends, in one or two sentences: what the listener needs to do or decide next, with the recommendation when there is one, or the one thing to remember. "" for a plain story or news with nothing to act on
}

keyPoints: every materially important point of the text. Include each number that matters, each date, time and deadline, each decision, request and action item (say who does what), each condition, exception, caveat, risk and recommendation, and the conclusion. Merge repeated points, skip greetings, filler, hype and self-promotion. Order by importance. Usually ${counts.all} points.${long ? " This is a long text: cover every part of it, not just the opening and the headline result (for a study: what was done, each main result, who it helped most, every limitation, and the conclusion)." : ""}

importance:
- 3 = must know: the main point, the key numbers (prices, amounts, percentages, results), dates and deadlines, decisions, who has to do what, warnings and changes that affect the listener, and any doubt or caveat that changes how much to trust a key claim (for example "the benchmark is the company's own", a study's limitations or a conflict of interest). Usually ${counts.essential} points.
- 2 = useful supporting detail.
- 1 = background or colour.

The listener hears bottomLine, then narration, then nextStep, as one TL;DR of about ${target} words and never more than ${Math.round(target * 1.25)} (the text is about ${sourceWords} words). It should feel like a friend explaining it, not a list of facts: someone who only hears it should understand it well enough to explain it to someone else.

narration: the middle, about ${Math.max(25, target - 40)} words, without repeating bottomLine or nextStep. In it, explain every importance-3 point in words anyone gets, with its key numbers, dates and names exactly as written, and add importance-2 points only where they help the story.${long ? " Go through it in a clear order (for a study: the question, what was done, the results, who it helped most, the limitations, the conclusion), one short paragraph each." : ""} Connect the points: why it matters, what causes what. Say what a number means when that isn't obvious. Leave out importance-1 points, background, contact details, sign-offs and any closing sentence that repeats what was already said. Never read out test counts, file, library or tool names: say what they mean ("the tests pass"). Numbers in digits as the text has them (18 minutes, 12 weeks, $2). Never read out confidence intervals, p-values, effect sizes or sample-size calculations in the narration (they can stay in keyPoints): say "a clear difference" or "statistically solid" instead. Never add a fact or number that isn't in the text, and keep the text's certainty ("may", "likely").

Shape it for the kind of text:
${SHAPES}

Use the text's language for every field.`;
}

/** The model's JSON answer, or null if it isn't usable. */
/** bottomLine, the middle and nextStep as one spoken TL;DR, without saying the opening twice. */
export function assembleNarration(bottomLine: string, middle: string, nextStep: string): string {
  const words = (t: string) => new Set(t.toLowerCase().match(/[\p{L}\p{N}%$₹€£.]+/gu) ?? []);
  const similar = (a: string, b: string) => {
    const x = words(a), y = words(b);
    if (!x.size || !y.size) return false;
    let shared = 0;
    for (const w of x) if (y.has(w)) shared += 1;
    return shared / Math.min(x.size, y.size) >= 0.7;
  };
  const sentences = (t: string) => t.match(/[^.!?]+[.!?]+["')\]]*\s*|[^.!?]+$/g) ?? [t];
  let body = middle.trim();
  // The model sometimes opens the middle with the bottom line again, or ends it with the next step.
  const first = sentences(body)[0] ?? "";
  if (bottomLine && first && similar(first, bottomLine)) body = body.slice(first.length).trim();
  const last = sentences(body).at(-1) ?? "";
  if (nextStep && last && similar(last, nextStep)) body = body.slice(0, body.length - last.length).trim();
  return [bottomLine.trim(), body, nextStep.trim()].filter(Boolean).join("\n\n");
}

export function parseTLDR(raw: string): (Notes & { narration: string }) | null {
  const start = raw.indexOf("{");
  const end = raw.lastIndexOf("}");
  if (start < 0 || end <= start) return null;
  try {
    const value = JSON.parse(raw.slice(start, end + 1)) as Record<string, unknown>;
    const text = (key: string) => (typeof value[key] === "string" ? (value[key] as string).trim() : "");
    const narration = text("narration") ? assembleNarration(text("bottomLine"), text("narration"), text("nextStep")) : "";
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

/** Confidence intervals, p-values and effect sizes: never required in the narration. */
const STATISTIC = /\bCI\b|confidence interval|\bp\s*[<=>≤]|\bd\s*=|effect size|power\b/i;

/** Essential tokens from the key points that the narration doesn't contain. */
export function missingEssentials(notes: Notes, narration: string): { point: NotePoint; missing: string[] }[] {
  const said = normalize(narration);
  const saidDigits = digitRuns(narration);
  const gaps: { point: NotePoint; missing: string[] }[] = [];
  for (const point of notes.points ?? []) {
    if ((point.importance ?? 2) < 2) continue;
    const missing = (point.mustKeep ?? []).filter((token) => typeof token === "string" && token.trim())
      // Statistics stay in the highlights, not the spoken TL;DR.
      .filter((token) => !STATISTIC.test(token))
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
 * Optional: a Groq model with a higher per-minute token limit, for texts too
 * long for the main one. On the free tier every model has 8,000 tokens a
 * minute (prompt and reply together), so there is none; on the Developer
 * tier the limits are far higher and it isn't needed.
 */
const longTextModel = () => process.env.GROQ_LONG_MODEL || undefined;

type CallOptions = { effort: "low" | "medium" | "high"; json?: boolean; maxTokens?: number; model?: string; retriedEmpty?: boolean };

/**
 * Amazon Bedrock first (BEDROCK_MODELS: model IDs, best first; the Lambda's
 * role signs the calls, so there's no key), then Groq if every Bedrock model
 * fails. Without BEDROCK_MODELS, Groq only. "anthropic.…" IDs are Claude in
 * Amazon Bedrock (the Messages API); any other ID (openai.gpt-oss-120b-1:0,
 * global.anthropic.claude-haiku-4-5-…, amazon.nova-pro-v1:0…) goes through
 * Bedrock's Converse API. "@us-west-2" after an ID calls that region.
 */
async function complete(fetchImpl: Fetch, messages: { role: string; content: string }[], options: CallOptions,
                        attempt = 0): Promise<string> {
  const models = (process.env.BEDROCK_MODELS ?? "").split(",").map((m) => m.trim()).filter(Boolean);
  for (const model of models) {
    if ((bedrockUnavailable.get(model) ?? 0) > Date.now()) continue;
    try {
      return /^anthropic\./.test(model) ? await bedrockComplete(model, messages, options) : await converseComplete(model, messages, options);
    } catch (error) {
      const status = error instanceof APIError ? error.status
        : /AccessDenied|ResourceNotFound|Validation/.test((error as { name?: string })?.name ?? "") ? 403 : undefined;
      // No access to this model (or it's unknown here): skip it for a while.
      if (status === 400 || status === 403 || status === 404) bedrockUnavailable.set(model, Date.now() + 10 * 60_000);
      console.warn("bedrock failed", model, status ?? "", error instanceof Error ? error.message.slice(0, 200) : error);
    }
  }
  if (models.length && !process.env.GROQ_API_KEY) throw new UpstreamError("The AI service is busy. Please try again.", true);
  return groqComplete(fetchImpl, messages, options, attempt);
}

const bedrockUnavailable = new Map<string, number>(); // model → skip until (ms)
let bedrock: AnthropicBedrockMantle | null = null;
let bedrockToken: string | undefined;

/** The TL;DR's JSON shape, so Claude's answer always parses. */
const TLDR_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["contentType", "mainPoint", "keyPoints", "bottomLine", "narration", "nextStep"],
  properties: {
    contentType: { type: "string", enum: Object.keys(CONTENT_GUIDES) },
    mainPoint: { type: "string" },
    keyPoints: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["text", "mustKeep", "importance"],
        properties: {
          text: { type: "string" },
          mustKeep: { type: "array", items: { type: "string" } },
          importance: { type: "integer", enum: [1, 2, 3] },
        },
      },
    },
    bottomLine: { type: "string" },
    narration: { type: "string" },
    nextStep: { type: "string" },
  },
};

async function bedrockComplete(model: string, messages: { role: string; content: string }[], options: CallOptions): Promise<string> {
  // A Bedrock API key (AWS_BEARER_TOKEN_BEDROCK, from Parameter Store) is used
  // when there is one, else the Lambda's role. A key added later takes effect at once.
  if (!bedrock || bedrockToken !== process.env.AWS_BEARER_TOKEN_BEDROCK) {
    bedrockToken = process.env.AWS_BEARER_TOKEN_BEDROCK;
    bedrockUnavailable.clear();
    bedrock = new AnthropicBedrockMantle({ awsRegion: process.env.BEDROCK_REGION || process.env.AWS_REGION || "us-east-1", timeout: 55_000, maxRetries: 1 });
  }
  const system = messages.filter((m) => m.role === "system").map((m) => m.content).join("\n\n");
  const response = await bedrock.messages.create({
    model,
    max_tokens: options.maxTokens ?? 16_000,
    ...(system ? { system } : {}),
    messages: messages.filter((m) => m.role !== "system").map((m) => ({ role: m.role === "assistant" ? "assistant" : "user", content: m.content })),
    output_config: {
      effort: options.effort,
      ...(options.json ? { format: { type: "json_schema", schema: TLDR_SCHEMA } } : {}),
    },
  });
  if (response.stop_reason === "refusal") throw new UpstreamError("The AI declined to summarize this text.");
  const text = response.content.map((block) => (block.type === "text" ? block.text : "")).join("").trim();
  if (!text) throw new UpstreamError("Bedrock returned an empty response.");
  return text;
}

const converseClients = new Map<string, BedrockRuntimeClient>();

/** Any Bedrock text model, through the Converse API. */
async function converseComplete(entry: string, messages: { role: string; content: string }[], options: CallOptions): Promise<string> {
  const [modelId, region = process.env.AWS_REGION || "us-east-1"] = entry.split("@");
  let client = converseClients.get(region);
  if (!client) converseClients.set(region, client = new BedrockRuntimeClient({ region, maxAttempts: 2 }));
  const system = messages.filter((m) => m.role === "system").map((m) => ({ text: m.content }));
  const response = await client.send(new ConverseCommand({
    modelId,
    ...(system.length ? { system } : {}),
    messages: messages.filter((m) => m.role !== "system").map((m) => ({ role: m.role === "assistant" ? "assistant" : "user", content: [{ text: m.content }] })),
    inferenceConfig: { maxTokens: options.maxTokens ?? 8_000 },
    // gpt-oss thinks first; how much follows the request (low for short texts).
    ...(/gpt-oss/.test(modelId) ? { additionalModelRequestFields: { reasoning_effort: options.effort } } : {}),
  }), { abortSignal: AbortSignal.timeout(55_000) });
  const text = (response.output?.message?.content ?? []).map((block) => block.text ?? "").join("").trim();
  if (!text) throw new UpstreamError("Bedrock returned an empty response.");
  return text;
}

async function groqComplete(fetchImpl: Fetch, messages: { role: string; content: string }[], options: CallOptions,
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
  // is too long for it, use the long-text model if there is one, or say so.
  const maxTokens = options.maxTokens ?? 8_000;
  const tooLarge = body.error?.message ?? "";
  if (/request too large/i.test(tooLarge)) {
    const [, limit, requested] = /Limit (\d+), Requested (\d+)/i.exec(tooLarge)?.map(Number) ?? [];
    const promptTokens = requested - maxTokens;  // NaN when Groq doesn't say
    if (maxTokens > 2_500 && !(promptTokens + 2_000 > limit)) {
      console.warn("groq: request too large, asking for a smaller reply", maxTokens);
      return groqComplete(fetchImpl, messages, { ...options, maxTokens: Math.round(maxTokens / 2) }, attempt);
    }
    const longModel = longTextModel();
    if (longModel && model !== longModel) {
      console.warn("groq: text too long for", model, "so using", longModel, { promptTokens, limit });
      return groqComplete(fetchImpl, messages, { ...options, model: longModel, maxTokens: 8_000 }, attempt);
    }
    throw new UpstreamError(tooLarge, false, true);
  }
  if (response.status === 429) {
    // Groq's per-minute limit: wait as long as it asks (if that's short) and try once more.
    const wait = Number(/try again in ([\d.]+)s/i.exec(body.error?.message ?? "")?.[1] ?? response.headers.get("retry-after") ?? NaN);
    if (attempt === 0 && Number.isFinite(wait) && wait <= 12) {
      await sleep(Math.ceil(wait * 1000) + 300);
      return groqComplete(fetchImpl, messages, options, attempt + 1);
    }
    throw new UpstreamError(body.error?.message ?? "Groq rate limit", true);
  }
  if (!response.ok) throw new UpstreamError(body.error?.message ?? `Groq returned ${response.status}`);
  const content = body.choices?.[0]?.message?.content?.trim();
  if (!content) {
    // The model sometimes spends the whole reply thinking and says nothing:
    // ask once more with less thinking before giving up.
    if (!options.retriedEmpty) return groqComplete(fetchImpl, messages, { ...options, effort: "low", retriedEmpty: true }, attempt);
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

  if (sourceWords < SINGLE_PASS_WORDS) return direct("low");

  // 1. Key points and narration, in one call.
  let result: (Notes & { narration: string }) | null = null;
  try {
    result = parseTLDR(await complete(fetchImpl, [
      { role: "system", content: INSTRUCTIONS },
      { role: "user", content: `${tldrRequest(sourceWords)}\n\nTEXT:\n${input}` },
    ], { effort: sourceWords > LONG_TEXT_WORDS ? "medium" : "low", json: true }));
  } catch (error) {
    if (error instanceof UpstreamError && (error.rateLimited || error.tooLong)) throw error;
    console.warn("tldr failed", error instanceof Error ? error.message : error);
  }
  if (!result) return direct("low");

  // 2. Check in code; 3. repair only if something essential is missing or wrong.
  let narration = result.narration;
  // The must-know points have to be heard; the others are in the highlights.
  const gaps = missingEssentials({ ...result, points: result.points.filter((p) => (p.importance ?? 2) >= 3) }, narration);
  const invented = inventedNumbers(narration, input);
  // A second call costs seconds: only for invented numbers or when several
  // must-know points weren't said (one or two still show in the highlights).
  if (gaps.length >= 3 || invented.length) {
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
