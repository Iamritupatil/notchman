import { targetWords, type SummaryLength } from "./plans.js";

/** Keep in sync with SummarizationPrompt.instructions in the app. */
export const INSTRUCTIONS = `You turn long written messages into short scripts that will be read aloud by a text-to-speech voice.

Write for the ear, not the eye:
- Plain conversational sentences. No bullet points, headings, markdown, tables, emoji or URLs.
- Open naturally, for example: "Okay, here's the important part."
- When there are several points, say how many, then walk through them: "There are three main ideas. First, …"
- Create the shortest spoken explanation that preserves all materially useful information: every fact, number, name, decision, reason, warning, recommendation, caveat, step, action item, deadline and conclusion. Losing information is worse than running long.
- Remove repetition, filler, redundant examples, formatting and conversational padding.
- If there are steps or a list, keep every item, in order.
- Keep just enough context for the listener to follow.
- Drop repetition, filler, pleasantries, citations and anything that only makes sense visually.
- If the text contains code, describe what it does in one sentence instead of reading it.
- Never invent facts that aren't in the text.
- Always answer in the same language as the message.`;

export const MAX_INPUT_CHARACTERS = 60_000;

export class UpstreamError extends Error {}

export function wordCount(text: string): number {
  return text.trim().split(/\s+/).filter(Boolean).length;
}

/**
 * Calls Groq (OpenAI-compatible API) with our server-side key. Default model is
 * OpenAI's open-weight gpt-oss-120b; set GROQ_MODEL=openai/gpt-oss-20b to halve cost.
 * The summary is written in the same language as the message.
 */
export async function summarize(text: string, length: SummaryLength,
                                fetchImpl: typeof fetch = fetch): Promise<string> {
  const apiKey = process.env.GROQ_API_KEY;
  if (!apiKey) throw new UpstreamError("GROQ_API_KEY is not configured on the server.");
  const input = text.slice(0, MAX_INPUT_CHARACTERS);
  const sourceWords = wordCount(input);
  // "detailed" (Complete, the default) has no duration target: length follows
  // the information. The timed lengths are upper limits.
  const request = length === "detailed"
    ? `Rewrite the following message for listening. Do not target a fixed duration; use as many words as needed to keep all useful information, and never more than the message itself (about ${sourceWords} words). Write in the same language as the message.`
    : `Rewrite the following message as a spoken summary of about ${targetWords(length, sourceWords)} words, in the same language as the message. Include every key point even if that takes more words.`;

  const response = await fetchImpl("https://api.groq.com/openai/v1/chat/completions", {
    method: "POST",
    headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model: process.env.GROQ_MODEL ?? "openai/gpt-oss-120b",
      // Medium effort noticeably improves coverage of every key point.
      reasoning_effort: "medium",
      max_completion_tokens: 6_000,
      messages: [
        { role: "system", content: INSTRUCTIONS },
        { role: "user", content: `${request}\n\nMESSAGE:\n${input}` },
      ],
    }),
  });

  const body = (await response.json().catch(() => ({}))) as {
    choices?: { message?: { content?: string } }[];
    error?: { message?: string };
  };
  if (!response.ok) throw new UpstreamError(body.error?.message ?? `Groq returned ${response.status}`);
  const summary = body.choices?.[0]?.message?.content?.trim();
  if (!summary) throw new UpstreamError("Groq returned an empty summary.");
  return summary;
}
