'use strict';

// The Notchman server (AWS): /tldr writes the summary (Groq), /speak voices a
// piece of text (ElevenLabs). The keys live on the server; this app only sends
// a random install ID, which per-install daily limits are counted against.

class ApiError extends Error {
  /** `reason`: the server's details.reason, e.g. 'too_long' (the app offers Upgrade). */
  constructor(message, status, reason) {
    super(message);
    this.name = 'ApiError';
    this.status = status;
    this.reason = reason;
  }
}

function createClient({ baseURL, installId, deviceId, fetch: fetchImpl = fetch }) {
  const base = baseURL.replace(/\/+$/, '');

  async function post(path, body, timeoutMs) {
    let response;
    try {
      response = await fetchImpl(`${base}${path}`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Notchman-Install': installId,
          ...(deviceId ? { 'X-Notchman-Device': deviceId } : {}),
        },
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
      const friendly = typeof data.message === 'string' && response.status !== 401 && (response.status < 500 || response.status === 503);
      const reason = data.details && typeof data.details.reason === 'string' ? data.details.reason : undefined;
      throw new ApiError(friendly ? data.message : 'Something went wrong. Please try again.', response.status, reason);
    }
    return data;
  }

  return {
    /** Plan and allowances: { plan, used, limit, period, voiceUsed, voiceLimit, voicePeriod }. */
    async usage() {
      return post('/usage', {}, 15000);
    },
    /** Once a day: which version and platform this install runs (counts installs; nothing personal). */
    async hello(info) {
      return post('/hello', info, 10000);
    },
    /** A Dodo Payments checkout link for this install: { url }. The email is filled in at checkout. */
    async checkout(plan, email) {
      return post('/checkout', { plan, ...(email ? { email } : {}) }, 15000);
    },
    /** @returns {Promise<string>} the spoken summary */
    /** @returns {Promise<{summary: string, highlights: string[]}>} the spoken TL;DR and its key points */
    async tldr(text) {
      const data = await post('/tldr', { text, length: 'detailed', voice: false }, 60000);
      if (typeof data.summary !== 'string' || !data.summary.trim()) throw new ApiError('Something went wrong. Please try again.', 200);
      const highlights = Array.isArray(data.highlights) ? data.highlights.filter((h) => typeof h === 'string' && h.trim()).slice(0, 10) : [];
      return { summary: data.summary.trim(), highlights };
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
