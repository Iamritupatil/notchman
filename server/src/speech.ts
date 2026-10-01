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
  const model = configured && configured !== "unused" ? configured : "eleven_multilingual_v2";
  // 128 kbps: clean, full-bandwidth speech. A two-minute TL;DR is about 2 MB,
  // inside Lambda's 6 MB response limit even after base64.
  const url = `https://api.elevenlabs.io/v1/text-to-speech/${encodeURIComponent(voice)}?output_format=mp3_44100_128`;

  const response = await fetchImpl(url, {
    method: "POST",
    headers: { "xi-api-key": apiKey, "Content-Type": "application/json", Accept: "audio/mpeg" },
    body: JSON.stringify({
      text,
      model_id: model,
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
