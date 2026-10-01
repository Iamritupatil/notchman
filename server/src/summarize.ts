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
 *   1. Understand: read the whole text and extract structured notes (purpose,
 *      main point, every material fact / number / reason / caveat / action,
 *      how points relate, jargon with plain meanings, certainty levels).
 *   2. Explain: write the spoken narration from those notes (with the source
 *      for faithfulness), reorganised for clarity and shaped by content type.
 *   3. Check coverage (in code): every number, date, name and term the notes
 *      marked as essential must appear in the narration.
 *   4. Repair (only if something was dropped): add the missing points back.
 *
 * Short messages need no notes: one careful call does all of it.
 * Length follows information density; there is no duration target.
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
- Use natural transitions where they help ("Basically…", "Here's why that matters…", "The catch is…", "So the takeaway is…"), without repeating the same one.
- Write numbers, amounts, percentages, dates and times in digits exactly as the text has them ("31%", "₹4.5 lakh", "17 March", "5 pm"); the voice reads digits naturally.
- Length follows the information: a padded post may need two sentences, a dense explanation several minutes. Never pad, never cut something important to be shorter.
- Always answer in the same language as the text.`;

/** How to shape the explanation for each kind of content. */
const CONTENT_GUIDES: Record<string, string> = {
  social_post: "A social media post: give the main claim, the reasoning and evidence behind it, the important numbers or examples, and the lesson or takeaway. Skip the hook-style framing and self-promotion.",
  ai_explanation: "An AI assistant's answer: keep every concept, the reasoning, the steps in order, the options and when each applies, caveats and the recommendation. Describe what any code does instead of reading it.",
  conversation: "A conversation or message: say who wants what, the decisions, requests, important details, dates, times, deadlines and action items, with just enough context. Make clear who needs to do what.",
  educational: "Educational content: act like a concise teacher. Cover every important concept, define terms simply, explain how ideas relate, and use a quick example where it helps.",
  news: "News or informational content: who, what, when, where, why, the consequences, and what is still uncertain or disputed.",
  argument: "An argument or debate: state the question, each side's position and its strongest reasons, where they agree or conflict, and the conclusion if there is one. Do not take sides the text didn't take.",
  document: "An email, document, policy or announcement: what it is about, what changes, who is affected, what they must do and by when, and any conditions or exceptions.",
  other: "Explain what the text is about and everything a reader would need from it.",
};

export const MAX_INPUT_CHARACTERS = 60_000;

/** Below this many words, one careful call covers everything. */
export const SINGLE_PASS_WORDS = 160;

export class UpstreamError extends Error {}

export function wordCount(text: string): number {
  return text.trim().split(/\s+/).filter(Boolean).length;
}

// --- Structured notes (stage 1) --------------------------------------------

export interface NotePoint {
  kind: string;
  text: string;
  /** Exact numbers, dates, names or terms that must survive into the narration. */
  mustKeep?: string[];
  certainty?: string;
  /** 3 = essential, 2 = important, 1 = minor. */
  importance?: number;
}

export interface Notes {
  contentType: string;
  language?: string;
  purpose?: string;
  mainPoint?: string;
  points: NotePoint[];
  jargon?: { term: string; plainMeaning: string }[];
  relationships?: string[];
  conclusion?: string;
}

const NOTES_REQUEST = `Read the ENTIRE text below carefully before writing anything. Then return JSON (no other text) with the notes someone would need to explain it fully without the original:

{
  "contentType": one of "social_post", "ai_explanation", "conversation", "educational", "news", "argument", "document", "other",
  "language": the text's language,
  "purpose": what the text is for, in one sentence,
  "mainPoint": the central message, in one sentence,
  "points": [
    {
      "kind": one of "fact", "claim", "number", "date", "reason", "cause_effect", "comparison", "decision", "instruction", "step", "recommendation", "warning", "caveat", "limitation", "exception", "condition", "dependency", "deadline", "action_item", "conclusion", "definition", "counterpoint", "context",
      "text": the point stated completely and precisely (keep conditions, who/what, and certainty words such as may or likely),
      "mustKeep": [exact numbers, amounts, percentages, dates, times, names and technical terms from this point that must not be lost],
      "certainty": "certain", "likely", "possible" or "disputed" as the TEXT states it,
      "importance": 3 if the listener must know it, 2 if it matters, 1 if minor
    }
  ],
  "jargon": [{"term": a term an ordinary listener may not know, "plainMeaning": a plain explanation faithful to the text}],
  "relationships": [how points connect: causes, trade-offs, what depends on what],
  "conclusion": the overall conclusion or takeaway, if any
}

Rules: include every materially important point, even small ones like a deadline or an exception. Merge repeated points into one. Do not include greetings, filler or promotion. Do not add anything that isn't in the text.`;

/** Stage 3: essential tokens from the notes that the narration doesn't contain. */
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

async function complete(fetchImpl: Fetch, messages: { role: string; content: string }[],
                        options: { effort: "low" | "medium" | "high"; json?: boolean; maxTokens?: number }): Promise<string> {
  const apiKey = process.env.GROQ_API_KEY;
  if (!apiKey) throw new UpstreamError("GROQ_API_KEY is not configured on the server.");
  const response = await fetchImpl("https://api.groq.com/openai/v1/chat/completions", {
    method: "POST",
    headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model: process.env.GROQ_MODEL ?? "openai/gpt-oss-120b",
      reasoning_effort: options.effort,
      max_completion_tokens: options.maxTokens ?? 8_000,
      ...(options.json ? { response_format: { type: "json_object" } } : {}),
      messages,
    }),
  });
  const body = (await response.json().catch(() => ({}))) as {
    choices?: { message?: { content?: string } }[];
    error?: { message?: string };
  };
  if (!response.ok) throw new UpstreamError(body.error?.message ?? `Groq returned ${response.status}`);
  const content = body.choices?.[0]?.message?.content?.trim();
  if (!content) throw new UpstreamError("Groq returned an empty response.");
  return content;
}

export function parseNotes(raw: string): Notes | null {
  const start = raw.indexOf("{");
  const end = raw.lastIndexOf("}");
  if (start < 0 || end <= start) return null;
  try {
    const value = JSON.parse(raw.slice(start, end + 1)) as Partial<Notes>;
    if (!Array.isArray(value.points) || value.points.length === 0) return null;
    return {
      contentType: typeof value.contentType === "string" && value.contentType in CONTENT_GUIDES ? value.contentType : "other",
      language: value.language,
      purpose: value.purpose,
      mainPoint: value.mainPoint,
      points: value.points.filter((p): p is NotePoint => Boolean(p) && typeof p.text === "string"),
      jargon: Array.isArray(value.jargon) ? value.jargon : [],
      relationships: Array.isArray(value.relationships) ? value.relationships : [],
      conclusion: value.conclusion,
    };
  } catch {
    return null;
  }
}

function narrationRequest(notes: Notes, sourceWords: number): string {
  const guide = CONTENT_GUIDES[notes.contentType] ?? CONTENT_GUIDES.other;
  return `Write the spoken explanation now.

Content type: ${guide}

Use the NOTES as your checklist: every point with importance 2 or 3 must be in your explanation, with its numbers, dates, names, conditions and certainty intact; include importance-1 points only if they help understanding. Explain the jargon in plain words where it first comes up. Use the SOURCE to stay faithful and to get the meaning exactly right; do not add anything that is in neither.

Organise it for understanding, not in the source's order: start with the main point, then the supporting points grouped by how they relate, and end with the conclusion, recommendation or what the listener needs to do, if there is one.

Before answering, check silently: what important information would the listener still not know after hearing this? Add it. Then: what can be removed without reducing understanding? Remove it. The source is about ${sourceWords} words; let the information decide the length. Reply with only the narration.`;
}

/**
 * Summarizes text for listening. `detailed` (the default, "Complete") has no
 * duration target. The timed lengths are upper limits kept for older apps.
 */
export async function summarize(text: string, length: SummaryLength,
                                fetchImpl: Fetch = fetch): Promise<string> {
  const input = text.slice(0, MAX_INPUT_CHARACTERS);
  const sourceWords = wordCount(input);

  if (length !== "detailed") {
    return complete(fetchImpl, [
      { role: "system", content: INSTRUCTIONS },
      { role: "user", content: `Explain the following text in about ${targetWords(length, sourceWords)} spoken words. Include every key point even if that takes more words.\n\nTEXT:\n${input}` },
    ], { effort: "medium" });
  }

  if (sourceWords < SINGLE_PASS_WORDS) {
    return complete(fetchImpl, [
      { role: "system", content: INSTRUCTIONS },
      { role: "user", content: `Explain the following text for listening. Understand all of it first, keep every material detail exactly (numbers, dates, names, conditions, who needs to do what), and drop only what adds nothing. It is short, so the explanation may be one or two sentences; never longer than the text itself. Reply with only the narration.\n\nTEXT:\n${input}` },
    ], { effort: "medium" });
  }

  // 1. Understand: structured notes.
  let notes: Notes | null = null;
  try {
    notes = parseNotes(await complete(fetchImpl, [
      { role: "system", content: "You analyse texts precisely and return only valid JSON." },
      { role: "user", content: `${NOTES_REQUEST}\n\nTEXT:\n${input}` },
    ], { effort: "medium", json: true }));
  } catch (error) {
    // Notes are a quality step; without them, explain directly.
    console.warn("notes failed", error instanceof Error ? error.message : error);
  }
  if (!notes) {
    return complete(fetchImpl, [
      { role: "system", content: INSTRUCTIONS },
      { role: "user", content: `Explain the following text for listening. Read all of it first, then explain everything important in the clearest order, not sentence by sentence. Reply with only the narration.\n\nTEXT:\n${input}` },
    ], { effort: "medium" });
  }

  // 2. Explain from the notes.
  const notesJSON = JSON.stringify(notes);
  let narration = await complete(fetchImpl, [
    { role: "system", content: INSTRUCTIONS },
    { role: "user", content: `NOTES:\n${notesJSON}\n\nSOURCE:\n${input}\n\n${narrationRequest(notes, sourceWords)}` },
  ], { effort: "medium" });

  // 3. Coverage check in code; 4. repair only if something essential is missing.
  const gaps = missingEssentials(notes, narration);
  if (gaps.length) {
    const list = gaps.map((g) => `- ${g.point.text} (must include: ${g.missing.join(", ")})`).join("\n");
    try {
      narration = await complete(fetchImpl, [
        { role: "system", content: INSTRUCTIONS },
        { role: "user", content: `This spoken explanation left out important information. Rewrite it so these points are included naturally, exactly as stated (numbers, dates, names and certainty intact), keeping everything else that is already there and adding no filler.\n\nMISSING:\n${list}\n\nEXPLANATION:\n${narration}\n\nSOURCE (for accuracy):\n${input}\n\nReply with only the narration.` },
      ], { effort: "low" });
    } catch (error) {
      console.warn("repair failed", error instanceof Error ? error.message : error);
    }
  }
  return narration;
}
