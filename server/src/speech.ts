import { UpstreamError } from "./summarize.js";

export interface Speech {
  /** MP3 audio, base64-encoded for the callable response. */
  audioBase64: string;
  format: "mp3";
  characters: number;
  /** The ElevenLabs voice that spoke it (the app checks it's the one chosen). */
  voiceId: string;
}

/**
 * ElevenLabs text-to-speech. Multilingual v2 is ElevenLabs' most natural
 * voice model (29 languages, detected from the text). Flash v2.5 is faster and
 * half the price but flatter. Voice and model are configurable.
 */
/** Neighbouring text, so a voice made in pieces flows naturally across them. */
export interface SpeechContext {
  previousText?: string;
  nextText?: string;
  /** ElevenLabs voice ID; defaults to ELEVENLABS_VOICE_ID. */
  voiceId?: string;
}

/** ElevenLabs voice IDs are 20 letters and digits. */
export const VOICE_ID = /^[A-Za-z0-9]{20}$/;

/** Sarah, one of ElevenLabs' current default voices. */
export const DEFAULT_VOICE_ID = "EXAVITQu4vr4xnSDxMaL";

/**
 * The voices the Notchman apps offer (ElevenLabs' standard voices). Only these
 * are spoken with, so nobody can use other voices on Notchman's account.
 */
const NOTCHMAN_VOICES = new Set([
  // Desktop (desktop/src/config.js)
  "21m00Tcm4TlvDq8ikWAM", "9BWtsMINqrJLrRacOk9x", "EXAVITQu4vr4xnSDxMaL", "JBFqnCBsd6RMkjVDRZzb", "XB0fDUnXU5powFXDhCwa",
  "nPczCjzI2devNBz1zQrb", "onwK4e9ZLuTAKqWW03F9", "pFZP5JQG7iQjIQuC4Bku", "pNInz6obpgDQGcFmaJgB",
  // iPhone
  "FGY2WhTYpPnrIDTdsKH5", "IKne3meq5aSn9XLyUdCD", "TX3LPaxmHKxFdv7VOQHJ", "Xb7hH8MSUJpSbSDYk0k2", "XrExE9yKIg1WjnnlVkGX",
  "bIHbv24MWmeRgasZH58o", "cgSgspJ2msm6clMCkdW9", "cjVigY5qzO86Huf0OWal", "iP95p4xoKVk53GoZ742B",
]);

/** True for a voice the apps offer (or the server's configured default). */
export function isNotchmanVoice(voiceId: string): boolean {
  return NOTCHMAN_VOICES.has(voiceId) || voiceId === process.env.ELEVENLABS_VOICE_ID;
}

export async function synthesize(text: string, fetchImpl: typeof fetch = fetch,
                                 context: SpeechContext = {}): Promise<Speech> {
  const apiKey = process.env.ELEVENLABS_API_KEY;
  if (!apiKey) throw new UpstreamError("ELEVENLABS_API_KEY is not configured on the server.");
  // The chosen voice, or the configured default for callers that send none.
  // An invalid choice is rejected by the handler, never swapped silently.
  const voice = context.voiceId && VOICE_ID.test(context.voiceId)
    ? context.voiceId
    : process.env.ELEVENLABS_VOICE_ID ?? DEFAULT_VOICE_ID;
  console.log("elevenlabs", JSON.stringify({ voice, characters: text.length, requested: context.voiceId ?? null }));
  const configured = process.env.ELEVENLABS_MODEL;
  const model = configured && configured !== "unused" ? configured : "eleven_flash_v2_5";
  // 128 kbps: clean, full-bandwidth speech. A two-minute TL;DR is about 2 MB,
  // inside Lambda's 6 MB response limit even after base64.
  const url = `https://api.elevenlabs.io/v1/text-to-speech/${encodeURIComponent(voice)}?output_format=mp3_44100_128`;

  const response = await fetchImpl(url, {
    method: "POST",
    headers: { "xi-api-key": apiKey, "Content-Type": "application/json", Accept: "audio/mpeg" },
    body: JSON.stringify({
      text,
      model_id: model,
      // Hindi (Devanagari, often with English words mixed in): say so, so it isn't read as another language.
      ...(isHindi(text) && /flash_v2_5|turbo_v2_5/.test(model) ? { language_code: "hi" } : {}),
      ...(context.previousText ? { previous_text: context.previousText.slice(-1_000) } : {}),
      ...(context.nextText ? { next_text: context.nextText.slice(0, 1_000) } : {}),
      // Warm, steady narration: a little expressive without wobbling.
      voice_settings: { stability: 0.45, similarity_boost: 0.8, style: 0.15, use_speaker_boost: true },
    }),
  });
  if (!response.ok) {
    const detail = await response.text().catch(() => "");
    throw new UpstreamError(`ElevenLabs returned ${response.status}${detail ? `: ${detail.slice(0, 200)}` : ""}`);
  }
  const audio = Buffer.from(await response.arrayBuffer());
  if (audio.length === 0) throw new UpstreamError("ElevenLabs returned no audio.");
  return { audioBase64: audio.toString("base64"), format: "mp3", characters: text.length, voiceId: voice };
}

// --- ElevenLabs balance ------------------------------------------------------

let balance: { remaining: number; at: number } | undefined;

/**
 * Credits left on the ElevenLabs account (cached for 5 minutes and counted
 * down locally between checks), or undefined if it can't be read (then
 * nothing is blocked on it).
 */
export async function elevenLabsRemaining(now = Date.now(), fetchImpl: typeof fetch = fetch): Promise<number | undefined> {
  if (balance && now - balance.at < 5 * 60_000) return balance.remaining;
  const apiKey = process.env.ELEVENLABS_API_KEY;
  if (!apiKey) return undefined;
  try {
    const response = await fetchImpl("https://api.elevenlabs.io/v1/user/subscription", {
      headers: { "xi-api-key": apiKey }, signal: AbortSignal.timeout(3000),
    });
    if (!response.ok) {
      console.warn("elevenlabs balance", response.status);
      return undefined;
    }
    const body = await response.json() as { character_count?: number; character_limit?: number };
    if (typeof body.character_count !== "number" || typeof body.character_limit !== "number") return undefined;
    balance = { remaining: body.character_limit - body.character_count, at: now };
    if (balance.remaining < 5000) console.warn("elevenlabs balance low", balance.remaining);
    return balance.remaining;
  } catch (error) {
    console.warn("elevenlabs balance failed", error instanceof Error ? error.message : error);
    return undefined;
  }
}

/** Counts spent characters against the cached balance until the next check. */
export function spendBalance(characters: number): void {
  if (balance) balance.remaining -= characters;
}

/** For tests. */
export function resetBalance(): void {
  balance = undefined;
}

// --- Standard voice (Azure neural) ---------------------------------------------

/** Mostly Hindi (Devanagari) text, even with English words mixed in. */
export function isHindi(text: string): boolean {
  const devanagari = (text.match(/[\u0900-\u097F]/g) ?? []).length;
  const latin = (text.match(/[A-Za-z]/g) ?? []).length;
  return devanagari > 0 && devanagari >= latin * 0.5;
}

/** Hindi neural voices for Hindi text: a woman's or a man's voice, like the chosen Notchman voice. */
const AZURE_HINDI_MALE = new Set(["JBFqnCBsd6RMkjVDRZzb", "onwK4e9ZLuTAKqWW03F9", "nPczCjzI2devNBz1zQrb", "pNInz6obpgDQGcFmaJgB"]);

/** Each Notchman voice's closest Azure neural voice (multilingual where possible). */
const AZURE_VOICES: Record<string, string> = {
  "21m00Tcm4TlvDq8ikWAM": "en-US-AvaMultilingualNeural", // Rachel
  "EXAVITQu4vr4xnSDxMaL": "en-US-EmmaMultilingualNeural", // Sarah
  "9BWtsMINqrJLrRacOk9x": "en-US-AvaMultilingualNeural", // Aria
  "XB0fDUnXU5powFXDhCwa": "en-GB-SoniaNeural", // Charlotte
  "pFZP5JQG7iQjIQuC4Bku": "en-GB-LibbyNeural", // Lily
  "JBFqnCBsd6RMkjVDRZzb": "en-GB-RyanNeural", // George
  "onwK4e9ZLuTAKqWW03F9": "en-GB-ThomasNeural", // Daniel
  "nPczCjzI2devNBz1zQrb": "en-US-BrianMultilingualNeural", // Brian
  "pNInz6obpgDQGcFmaJgB": "en-US-AndrewMultilingualNeural", // Adam
};

const escapeXML = (text: string) => text.replace(/[<>&'"]/g, (c) =>
  ({ "<": "&lt;", ">": "&gt;", "&": "&amp;", "'": "&apos;", "\"": "&quot;" })[c]!);

/**
 * Azure AI Speech neural text-to-speech: natural, and about a tenth of
 * ElevenLabs' price (500,000 characters a month free). Needs AZURE_SPEECH_KEY
 * (Parameter Store) and AZURE_SPEECH_REGION.
 */
export async function synthesizeAzure(text: string, context: SpeechContext = {},
                                      fetchImpl: typeof fetch = fetch): Promise<Speech> {
  const key = process.env.AZURE_SPEECH_KEY;
  if (!key) throw new UpstreamError("AZURE_SPEECH_KEY is not configured on the server.");
  const region = process.env.AZURE_SPEECH_REGION || "eastus";
  const requested = context.voiceId ?? process.env.ELEVENLABS_VOICE_ID ?? DEFAULT_VOICE_ID;
  const hindi = isHindi(text);
  const voice = hindi ? (AZURE_HINDI_MALE.has(requested) ? "hi-IN-MadhurNeural" : "hi-IN-SwaraNeural")
    : AZURE_VOICES[requested] ?? "en-US-AvaMultilingualNeural";
  const ssml = `<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="${hindi ? "hi-IN" : "en-US"}"><voice name="${voice}">${escapeXML(text)}</voice></speak>`;
  const response = await fetchImpl(`https://${region}.tts.speech.microsoft.com/cognitiveservices/v1`, {
    method: "POST",
    headers: {
      "Ocp-Apim-Subscription-Key": key,
      "Content-Type": "application/ssml+xml",
      "X-Microsoft-OutputFormat": "audio-24khz-96kbitrate-mono-mp3",
      "User-Agent": "notchman",
    },
    body: ssml,
    signal: AbortSignal.timeout(20_000),
  });
  if (!response.ok) {
    const detail = await response.text().catch(() => "");
    throw new UpstreamError(`Azure speech returned ${response.status}${detail ? `: ${detail.slice(0, 200)}` : ""}`);
  }
  const audio = Buffer.from(await response.arrayBuffer());
  if (audio.length === 0) throw new UpstreamError("Azure speech returned no audio.");
  console.log("azure", JSON.stringify({ voice, characters: text.length }));
  // voiceId: the Notchman voice that was asked for (the app checks it).
  return { audioBase64: audio.toString("base64"), format: "mp3", characters: text.length, voiceId: requested };
}
