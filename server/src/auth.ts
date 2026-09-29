/**
 * Who is calling. Each Notchman install sends a random ID it keeps in the
 * iPhone's Keychain (`X-Notchman-Install`). It isn't a password: it's what
 * per-install daily limits are counted against. Cost is bounded by those
 * limits plus a total daily cap across all installs (see handlers.ts), so a
 * misused ID can't run up the Groq or ElevenLabs bill.
 */
export class AuthError extends Error {}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Returns the caller's install ID, or throws `AuthError`. */
export function installIdFrom(headers: Record<string, string | undefined>): string {
  const id = headers["x-notchman-install"]?.trim();
  if (!id) throw new AuthError("Missing install ID.");
  if (!UUID.test(id)) throw new AuthError("Invalid install ID.");
  return `install:${id.toLowerCase()}`;
}
