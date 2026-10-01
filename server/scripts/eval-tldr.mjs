// Evaluates TL;DR quality on the 7 test cases in eval-cases.mjs.
//
//   node scripts/eval-tldr.mjs                 (uses the deployed server)
//   node scripts/eval-tldr.mjs <server URL>
//
// For each case it prints the TL;DR and checks:
//   coverage    every must-know fact is present
//   faithful    no numbers that aren't in the source (likely invented)
//   spoken      no headings, bullets, markdown or "here's a summary" phrasing
//   compression TL;DR length vs the original, with listening times at 150 wpm
// Results are also written to eval-results.md. This uses the real server, so it
// counts against the day's beta TL;DR allowance (7 requests).

import { writeFile } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import { CASES } from "./eval-cases.mjs";

const SERVER = (process.argv[2] || "https://x6clb2pbdxbr55i5sdradcnqw40bmqrt.lambda-url.us-east-1.on.aws").replace(/\/+$/, "");
const INSTALL = randomUUID();

const words = (s) => s.trim().split(/\s+/).filter(Boolean).length;
const minutes = (w) => {
  const seconds = Math.round((w / 150) * 60);
  return seconds < 60 ? `${seconds}s` : `${Math.floor(seconds / 60)}m ${String(seconds % 60).padStart(2, "0")}s`;
};
const numbersIn = (s) => new Set((s.replace(/(\d),(?=\d)/g, "$1").match(/\d+(?:\.\d+)?/g) || []).map(Number));

const REPORT_STYLE = [/^\s*#/m, /^\s*[-*•]\s/m, /^\s*\d+[.)]\s/m, /\*\*/, /here'?s (a|the) summary/i, /point number/i, /in summary,/i, /tl;dr/i];

async function tldr(text) {
  const started = Date.now();
  const response = await fetch(`${SERVER}/tldr`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-Notchman-Install": INSTALL },
    body: JSON.stringify({ text, length: "detailed", voice: false }),
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(`${response.status} ${body.message || ""}`);
  return { summary: body.summary, ms: Date.now() - started };
}

const report = [`# TL;DR evaluation\n\nServer: ${SERVER}\nDate: ${new Date().toISOString()}\n`];
let passed = 0;

for (const testCase of CASES) {
  process.stdout.write(`\n${testCase.name}… `);
  let result;
  try {
    result = await tldr(testCase.text);
  } catch (error) {
    console.log(`FAILED: ${error.message}`);
    report.push(`## ${testCase.name}\n\nRequest failed: ${error.message}\n`);
    continue;
  }
  const { summary, ms } = result;
  const sourceWords = words(testCase.text);
  const summaryWords = words(summary);
  const ratio = summaryWords / sourceWords;

  const missing = testCase.mustCover.filter((re) => !re.test(summary)).map(String);
  const wrong = testCase.mustNot.filter((re) => re.test(summary)).map(String);
  const sourceNumbers = numbersIn(testCase.text);
  const invented = [...numbersIn(summary)].filter((n) => !sourceNumbers.has(n) && n > 1);
  const reportStyle = REPORT_STYLE.filter((re) => re.test(summary)).map(String);
  const tooLong = testCase.maxRatio && ratio > testCase.maxRatio;

  const ok = !missing.length && !wrong.length && !invented.length && !reportStyle.length && !tooLong;
  if (ok) passed++;
  const coverage = `${testCase.mustCover.length - missing.length}/${testCase.mustCover.length}`;
  console.log(`${ok ? "PASS" : "CHECK"}  coverage ${coverage}, ${minutes(sourceWords)} → ${minutes(summaryWords)} (${Math.round(ratio * 100)}%), ${(ms / 1000).toFixed(1)}s`);
  if (missing.length) console.log(`   missing: ${missing.join("  ")}`);
  if (wrong.length) console.log(`   should not say: ${wrong.join("  ")}`);
  if (invented.length) console.log(`   numbers not in the source: ${invented.join(", ")}`);
  if (reportStyle.length) console.log(`   report-style: ${reportStyle.join("  ")}`);
  if (tooLong) console.log(`   too long for repetitive content (${Math.round(ratio * 100)}% of the original)`);

  report.push(`## ${testCase.name} — ${ok ? "PASS" : "CHECK"}

- Coverage: ${coverage}${missing.length ? ` (missing: ${missing.join(", ")})` : ""}
- Original: ${sourceWords} words (${minutes(sourceWords)}) → TL;DR: ${summaryWords} words (${minutes(summaryWords)}), ${Math.round(ratio * 100)}%
- Time to make it: ${(ms / 1000).toFixed(1)} s${invented.length ? `\n- Numbers not in the source: ${invented.join(", ")}` : ""}${wrong.length ? `\n- Should not say: ${wrong.join(", ")}` : ""}${reportStyle.length ? `\n- Report-style: ${reportStyle.join(", ")}` : ""}

> ${summary.replace(/\n+/g, "\n> ")}
`);
}

console.log(`\n${passed}/${CASES.length} passed all automatic checks. Full TL;DRs: eval-results.md`);
report.push(`\n**${passed}/${CASES.length} passed all automatic checks.** Automatic checks catch missing facts, invented numbers and report-style wording; read the TL;DRs too for clarity and accuracy.\n`);
await writeFile(new URL("../eval-results.md", import.meta.url), report.join("\n"));
