/**
 * Runs every case through the real TL;DR pipeline (Groq) and scores it:
 * facts kept, numbers invented, length and time. `npm run eval`.
 */
import { CASES, mentions } from "./cases.js";
import { summarize, wordCount } from "../src/summarize.js";

const digits = (s: string) => new Set((s.replace(/(\d),(?=\d{3})/g, "$1").match(/\d+(?:\.\d+)?/g) ?? []));

let kept = 0;
let total = 0;
const rows: string[] = [];
for (const c of CASES) {
  const started = Date.now();
  let summary = "";
  try {
    summary = await summarize(c.text, "detailed");
  } catch (error) {
    summary = `(failed: ${error instanceof Error ? error.message : error})`;
  }
  const seconds = ((Date.now() - started) / 1000).toFixed(1);
  const missing = c.facts.filter((f) => !mentions(summary, f.any)).map((f) => f.fact);
  const source = digits(c.text);
  const invented = [...digits(summary)].filter((d) => !source.has(d));
  kept += c.facts.length - missing.length;
  total += c.facts.length;
  rows.push(`${c.name}: ${c.facts.length - missing.length}/${c.facts.length} facts, ${wordCount(summary)} words (source ${wordCount(c.text)}), ${seconds}s` +
    (invented.length ? `, numbers not in the source: ${invented.join(", ")}` : ""));
  console.log(`\n=== ${c.name} ===\n${summary}\n--- missing: ${missing.length ? missing.join("; ") : "nothing"}`);
}
console.log(`\n=== Score ===\n${rows.join("\n")}\nTOTAL: ${kept}/${total} facts kept (${Math.round((kept / total) * 100)}%)`);
