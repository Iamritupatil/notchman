import { UpstreamError } from "./summarize.js";

export interface Speech {
  /** MP3 audio, base64-encoded for the callable response. */
  audioBase64: string;
  format: "mp3";
  characters: number;
}

/**
 * ElevenLabs text-to-speech. Flash v2.5 is ElevenLabs' fast, low-cost
 * multilingual model (~$0.05 per 1,000 characters at API rates); it detects
 * the language from the text. Voice and model are configurable.
 */
export async function synthesize(text: string, fetchImpl: typeof fetch = fetch): Promise<Speech> {
  const apiKey = process.env.ELEVENLABS_API_KEY;
  if (!apiKey) throw new UpstreamError("ELEVENLABS_API_KEY is not configured on the server.");
  const voice = process.env.ELEVENLABS_VOICE_ID ?? "21m00Tcm4TlvDq8ikWAM";
  const model = process.env.ELEVENLABS_MODEL ?? "eleven_flash_v2_5";
  // 64 kbps keeps a one-minute TL;DR around 480 KB, well within callable limits.
  const url = `https://api.elevenlabs.io/v1/text-to-speech/${encodeURIComponent(voice)}?output_format=mp3_44100_64`;

  const response = await fetchImpl(url, {
    method: "POST",
    headers: { "xi-api-key": apiKey, "Content-Type": "application/json", Accept: "audio/mpeg" },
    body: JSON.stringify({ text, model_id: model }),
  });
  if (!response.ok) {
    const detail = await response.text().catch(() => "");
    throw new UpstreamError(`ElevenLabs returned ${response.status}${detail ? `: ${detail.slice(0, 200)}` : ""}`);
  }
  const audio = Buffer.from(await response.arrayBuffer());
  if (audio.length === 0) throw new UpstreamError("ElevenLabs returned no audio.");
  return { audioBase64: audio.toString("base64"), format: "mp3", characters: text.length };
}
