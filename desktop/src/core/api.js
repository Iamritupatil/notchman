'use strict';

// The Notchman server (AWS): /tldr writes the summary (Groq), /speak voices a
// piece of text (ElevenLabs). The keys live on the server; this app only sends
// a random install ID, which per-install daily limits are counted against.

class ApiError extends Error {
  constructor(message, status) {
    super(message);
    this.name = 'ApiError';
    this.status = status;
  }
}

function createClient({ baseURL, installId, fetch: fetchImpl = fetch }) {
  const base = baseURL.replace(/\/+$/, '');

  async function post(path, body, timeoutMs) {
    let response;
    try {
      response = await fetchImpl(`${base}${path}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-Notchman-Install': installId },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(timeoutMs),
      });
    } catch {
      throw new ApiError("Couldn't reach Notchman. Check your connection.", 0);
    }
    const data = await response.json().catch(() => ({}));
    if (!response.ok) {
      // The server's messages are written for people ("Today's listening time
      // is used up..."); anything technical gets a plain fallback.
      const friendly = typeof data.message === 'string' && response.status !== 401 && response.status < 500;
      throw new ApiError(friendly ? data.message : 'Something went wrong. Please try again.', response.status);
    }
    return data;
  }

  return {
    /** Plan and allowances: { plan, used, limit, period, voiceUsed, voiceLimit, voicePeriod }. */
    async usage() {
      return post('/usage', {}, 15000);
    },
    /** @returns {Promise<string>} the spoken summary */
    async tldr(text) {
      const data = await post('/tldr', { text, length: 'detailed', voice: false }, 45000);
      if (typeof data.summary !== 'string' || !data.summary.trim()) throw new ApiError('Something went wrong. Please try again.', 200);
      return data.summary.trim();
    },
    /** @returns {Promise<Buffer>} MP3 audio of one piece */
    async speak({ text, previousText, nextText, voiceId }) {
      const data = await post('/speak', { text, previousText, nextText, voiceId }, 30000);
      if (typeof data.audio !== 'string') throw new ApiError('Something went wrong. Please try again.', 200);
      return Buffer.from(data.audio, 'base64');
    },
  };
}

module.exports = { createClient, ApiError };
