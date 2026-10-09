/**
 * Runs every case through the real TL;DR pipeline (Groq) and scores it:
 * facts kept, numbers invented, length and time. `npm run eval`.
 * Cases are spaced out so Groq's free per-minute limit doesn't skew results.
 */
import { CASES, mentions } from "./cases.js";
import * as pipeline from "../src/summarize.js";

const digits = (s: string) => new Set((s.replace(/(\d),(?=\d{3})/g, "$1").match(/\d+(?:\.\d+)?/g) ?? []));
const words = (s: string) => s.trim().split(/\s+/).filter(Boolean).length;
const pause = Number(process.env.EVAL_PAUSE_SECONDS ?? 65);
const label = process.env.EVAL_LABEL ?? "current";

type Result = { summary: string; highlights?: string[] };
const run = async (text: string): Promise<Result> => {
  const api = pipeline as unknown as { summarizeTLDR?: (t: string, l: "detailed") => Promise<Result>; summarize: (t: string, l: "detailed") => Promise<string> };
  return api.summarizeTLDR ? api.summarizeTLDR(text, "detailed") : { summary: await api.summarize(text, "detailed") };
};

let kept = 0;
let total = 0;
const rows: string[] = [];
for (const [index, c] of CASES.entries()) {
  if (index > 0) await new Promise((resolve) => setTimeout(resolve, pause * 1000));
  const started = Date.now();
  let result: Result;
  try {
    result = await run(c.text);
  } catch (error) {
    result = { summary: `(failed: ${error instanceof Error ? error.message.slice(0, 160) : error})` };
  }
  const seconds = ((Date.now() - started) / 1000).toFixed(1);
  const missing = c.facts.filter((f) => !mentions(result.summary, f.any)).map((f) => f.fact);
  const source = digits(c.text);
  const invented = [...digits(result.summary)].filter((d) => !source.has(d) && !/^[0-9]$/.test(d));
  kept += c.facts.length - missing.length;
  total += c.facts.length;
  rows.push(`${c.name}: ${c.facts.length - missing.length}/${c.facts.length} facts, ${words(result.summary)} words (source ${words(c.text)}), ${seconds}s` +
    (invented.length ? `, numbers not in the source: ${invented.join(", ")}` : ""));
  console.log(`\n=== [${label}] ${c.name} ===\n${result.summary}`);
  if (result.highlights?.length) console.log(`--- highlights:\n${result.highlights.map((h) => `  • ${h}`).join("\n")}`);
  console.log(`--- missing: ${missing.length ? missing.join("; ") : "nothing"}`);
}
console.log(`\n=== Score [${label}] ===\n${rows.join("\n")}\nTOTAL: ${kept}/${total} facts kept (${Math.round((kept / total) * 100)}%)`);
