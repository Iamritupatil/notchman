import { createSign, generateKeyPairSync } from "node:crypto";
import { describe, expect, it } from "vitest";
import { verifyIdentityToken } from "../src/accounts.js";
import { handleAccount, type Dependencies } from "../src/handlers.js";
import { MemoryQuotaStore } from "../src/quota.js";

const { privateKey, publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
const jwk = { ...publicKey.export({ format: "jwk" }), kid: "test-key", alg: "RS256", use: "sig" };
const keysFetch = (async () => new Response(JSON.stringify({ keys: [jwk] }))) as typeof fetch;

function token(claims: Record<string, unknown>, kid = "test-key"): string {
  const part = (value: unknown) => Buffer.from(JSON.stringify(value)).toString("base64url");
  const body = `${part({ alg: "RS256", kid })}.${part(claims)}`;
  const signature = createSign("RSA-SHA256").update(body).sign(privateKey).toString("base64url");
  return `${body}.${signature}`;
}

const now = Date.parse("2026-10-16T12:00:00Z");
const good = { iss: "https://appleid.apple.com", aud: "app.notchman", sub: "001234.abcd", email: "Ritu@Example.com",
               is_private_email: "false", exp: now / 1000 + 600 };

describe("Sign in with Apple tokens", () => {
  it("accepts Apple's token for this app", async () => {
    const identity = await verifyIdentityToken(token(good), "app.notchman", { now, fetchImpl: keysFetch });
    expect(identity).toEqual({ appleUserId: "001234.abcd", email: "ritu@example.com", privateEmail: false });
  });

  it("refuses tokens for another app, expired, or tampered with", async () => {
    await expect(verifyIdentityToken(token({ ...good, aud: "com.other" }), "app.notchman", { now, fetchImpl: keysFetch }))
      .rejects.toThrow("Not for this app");
    await expect(verifyIdentityToken(token({ ...good, exp: now / 1000 - 1 }), "app.notchman", { now, fetchImpl: keysFetch }))
      .rejects.toThrow("Expired");
    const [header, , signature] = token(good).split(".");
    const forged = `${header}.${Buffer.from(JSON.stringify({ ...good, sub: "someone-else" })).toString("base64url")}.${signature}`;
    await expect(verifyIdentityToken(forged, "app.notchman", { now, fetchImpl: keysFetch })).rejects.toThrow("Bad signature");
  });
});

describe("iPhone accounts", () => {
  function deps(plan: "free" | "pro" = "free") {
    const store = new MemoryQuotaStore();
    const sent: string[] = [];
    const d: Dependencies = {
      store,
      now: () => new Date(now),
      entitlement: async (userId) => (plan === "pro" ? { plan: "pro", accountKey: "sub:2000000123" } : { plan: "free", accountKey: `user:${userId}` }),
      verifyIdentity: async () => ({ appleUserId: "001234.abcd", email: "ritu@example.com", privateEmail: false }),
      notify: async (subject) => { sent.push(subject); },
    };
    return { store, d, sent };
  }

  it("keeps the email, Apple account ID, install and plan, and tells the owner once", async () => {
    const { store, d, sent } = deps("pro");
    const result = await handleAccount("install-1", { action: "signin", identityToken: "t", name: "Ritu" }, d);
    expect(result).toEqual({ ok: true, body: { signedIn: true, plan: "pro" } });
    const account = await store.getRecord("account_001234.abcd");
    expect(account).toMatchObject({ email: "ritu@example.com", appleUserId: "001234.abcd", name: "Ritu", plan: "pro",
                                     subscription: "2000000123", installs: [{ install: "install-1" }] });
    await handleAccount("install-1", { action: "signin", identityToken: "t" }, d);
    expect(sent).toEqual(["Notchman: new iPhone account (Pro)"]);
    expect((await store.getRecord("account_001234.abcd"))?.name).toBe("Ritu");
  });

  it("updates the plan after a purchase and tells the owner who bought", async () => {
    const free = deps("free");
    await handleAccount("install-1", { action: "signin", identityToken: "t" }, free.d);
    const paid = { ...free.d, entitlement: async () => ({ plan: "pro" as const, accountKey: "sub:2000000123" }) };
    const result = await handleAccount("install-1", { action: "refresh" }, paid);
    expect(result).toEqual({ ok: true, body: { signedIn: true, plan: "pro" } });
    expect(await free.store.getRecord("account_001234.abcd")).toMatchObject({ plan: "pro", subscription: "2000000123" });
    expect(free.sent).toContain("Notchman: ritu@example.com bought Pro");
  });

  it("deletes the account", async () => {
    const { store, d } = deps();
    await handleAccount("install-1", { action: "signin", identityToken: "t" }, d);
    expect(await handleAccount("install-1", { action: "delete" }, d)).toEqual({ ok: true, body: { deleted: true } });
    expect(await store.getRecord("account_001234.abcd")).toEqual({ deleted: true });
    expect(await handleAccount("install-1", { action: "refresh" }, d)).toEqual({ ok: true, body: { signedIn: false, plan: "free" } });
  });

  it("refuses a sign-in it can't confirm", async () => {
    const { d } = deps();
    expect(await handleAccount("install-1", { action: "signin" }, d)).toMatchObject({ ok: false, code: "invalid-argument" });
  });
});
