// Try your Groq and ElevenLabs keys on your own computer, before deploying.
//
//   cd server && npm install && npm run try
//   npm run try -- path/to/message.txt      (summarize your own text)
//
// Keys are typed in hidden and kept only in memory; nothing is saved.
// If GROQ_API_KEY / ELEVENLABS_API_KEY are already set in the environment, those are used.
import { readFile, writeFile } from "node:fs/promises";
import readline from "node:readline";
import { summarize } from "../lib/summarize.js";
import { synthesize } from "../lib/speech.js";

const SAMPLE = `Great question! There are three main ways to structure a SwiftUI app, and the right one depends on how big it will get.

1. **Single-module MVVM.** Keep views small and put state in @Observable view models. This is the fastest way to start and is fine for most apps under 20 screens.
2. **Feature modules.** Split the app into Swift packages per feature (Onboarding, Player, History). Build times drop and teams can work in parallel, but it costs about a day of setup.
3. **The Composable Architecture.** Very testable, with one store per feature, but it has a steep learning curve and adds a dependency.

My recommendation: start with option 1, and move a feature into its own package the moment it passes about 2,000 lines. Whatever you pick, avoid putting network calls directly in views — that's the number one thing that makes SwiftUI apps hard to test.`;

function askHidden(question) {
  return new Promise((resolve) => {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout, terminal: true });
    rl._writeToOutput = (s) => { if (s.includes(question)) rl.output.write(question); };
    rl.question(question, (answer) => { rl.close(); process.stdout.write("\n"); resolve(answer.trim()); });
  });
}

async function main() {
  const file = process.argv[2];
  const text = file ? await readFile(file, "utf8") : SAMPLE;

  process.env.GROQ_API_KEY ||= await askHidden("Groq API key (hidden): ");
  process.env.ELEVENLABS_API_KEY ||= await askHidden("ElevenLabs API key (hidden, Enter to skip the voice): ");

  console.log(`\nSummarizing ${text.length} characters with ${process.env.GROQ_MODEL ?? "openai/gpt-oss-120b"} on Groq…`);
  let started = Date.now();
  const summary = await summarize(text, "oneMinute");
  console.log(`Done in ${((Date.now() - started) / 1000).toFixed(1)} s:\n\n${summary}\n`);

  if (!process.env.ELEVENLABS_API_KEY) {
    console.log("No ElevenLabs key, so no voice. In the app, Apple's voice would read this.");
    return;
  }
  started = Date.now();
  const speech = await synthesize(summary);
  const out = new URL("../tldr-test.mp3", import.meta.url);
  await writeFile(out, Buffer.from(speech.audioBase64, "base64"));
  console.log(`Voice made in ${((Date.now() - started) / 1000).toFixed(1)} s with ${process.env.ELEVENLABS_MODEL ?? "eleven_flash_v2_5"}.`);
  console.log(`Saved ${out.pathname}. Open it to listen.`);
  console.log(`About ${speech.characters} characters ≈ $${(speech.characters * 0.05 / 1000).toFixed(3)} of ElevenLabs Flash.`);
}

main().catch((error) => {
  console.error(`\n✗ ${error?.message ?? error}`);
  if (/401|invalid|unauthorized/i.test(String(error?.message))) {
    console.error("  That key looks wrong. Copy it again from the provider's dashboard.");
  }
  process.exit(1);
});
