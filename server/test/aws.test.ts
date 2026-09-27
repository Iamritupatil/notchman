import { ConditionalCheckFailedException } from "@aws-sdk/client-dynamodb";
import { exportJWK, generateKeyPair, SignJWT, createLocalJWKSet } from "jose";
import { describe, expect, it } from "vitest";
import { AuthError, verifyAppCheck, verifyIdToken } from "../src/auth.js";
import { DynamoQuotaStore } from "../src/dynamo.js";
import { handleTLDR } from "../src/handlers.js";
import { route } from "../src/lambda.js";
import { MemoryQuotaStore } from "../src/quota.js";

const PROJECT = { id: "notchman-app", number: "123456789" };
const TEXT = "This is a long message that needs a TL;DR. ".repeat(10);

async function keys() {
  const { publicKey, privateKey } = await generateKeyPair("RS256");
  const jwk = { ...(await exportJWK(publicKey)), kid: "k1", alg: "RS256" };
  return { privateKey, jwks: createLocalJWKSet({ keys: [jwk] }) };
}

describe("Firebase token checks", () => {
  it("accepts a valid App Check token and rejects a wrong project", async () => {
    const { privateKey, jwks } = await keys();
    const token = await new SignJWT({}).setProtectedHeader({ alg: "RS256", kid: "k1" })
      .setIssuer(`https://firebaseappcheck.googleapis.com/${PROJECT.number}`)
      .setAudience([`projects/${PROJECT.number}`, `projects/${PROJECT.id}`])
      .setSubject("1:123456789:ios:abc").setExpirationTime("1h").sign(privateKey);
    await expect(verifyAppCheck(token, PROJECT, jwks)).resolves.toBeUndefined();
    await expect(verifyAppCheck(token, { ...PROJECT, number: "999" }, jwks)).rejects.toBeInstanceOf(AuthError);
    await expect(verifyAppCheck(token, { ...PROJECT, appId: "1:other" }, jwks)).rejects.toBeInstanceOf(AuthError);
    await expect(verifyAppCheck(undefined, PROJECT, jwks)).rejects.toBeInstanceOf(AuthError);
  });

  it("returns the user from a valid ID token", async () => {
    const { privateKey, jwks } = await keys();
    const token = await new SignJWT({}).setProtectedHeader({ alg: "RS256", kid: "k1" })
      .setIssuer(`https://securetoken.google.com/${PROJECT.id}`).setAudience(PROJECT.id)
      .setSubject("user-42").setExpirationTime("1h").sign(privateKey);
    await expect(verifyIdToken(token, PROJECT, jwks)).resolves.toBe("user-42");
    await expect(verifyIdToken("garbage", PROJECT, jwks)).rejects.toBeInstanceOf(AuthError);
  });
});

describe("beta allowance", () => {
  const free = async () => ({ plan: "free" as const, accountKey: "user:u" });
  const summarize = async () => "Short summary.";
  const synthesize = async () => ({ audioBase64: "QUJD", format: "mp3" as const, characters: 14 });

  it("gives Free users a daily cloud allowance during the beta", async () => {
    const deps = { store: new MemoryQuotaStore(), entitlement: free, summarize, synthesize, betaDailyTLDRs: 2, perMinuteLimit: 100 };
    expect(await handleTLDR("u", { text: TEXT }, deps)).toMatchObject({ ok: true, body: { limit: 2, remaining: 1, audio: "QUJD" } });
    expect((await handleTLDR("u", { text: TEXT }, deps)).ok).toBe(true);
    expect(await handleTLDR("u", { text: TEXT }, deps)).toMatchObject({ ok: false, code: "resource-exhausted" });
  });
});

describe("Lambda routing", () => {
  const event = (path: string, body: unknown, method = "POST") => ({
    rawPath: path, body: JSON.stringify(body), isBase64Encoded: false, headers: {},
    requestContext: { http: { method } },
  }) as never;
  const deps = {
    store: new MemoryQuotaStore(),
    entitlement: async () => ({ plan: "pro" as const, accountKey: "sub:1" }),
    summarize: async () => "Hi.", synthesize: async () => ({ audioBase64: "QQ==", format: "mp3" as const, characters: 3 }),
  };

  it("serves /tldr for authenticated users", async () => {
    const response = await route(event("/tldr", { text: TEXT }), { deps, authenticate: async () => "u1" });
    expect(response.statusCode).toBe(200);
    expect(JSON.parse(response.body!)).toMatchObject({ summary: "Hi.", audio: "QQ==", limit: 40 });
  });

  it("rejects missing tokens with 401 and wrong methods with 405", async () => {
    const denied = await route(event("/tldr", { text: TEXT }), { deps, authenticate: async () => { throw new AuthError("nope"); } });
    expect(denied.statusCode).toBe(401);
    expect((await route(event("/tldr", {}, "GET"), { deps })).statusCode).toBe(405);
  });

  it("maps errors to HTTP statuses", async () => {
    const response = await route(event("/tldr", { text: "short" }), { deps, authenticate: async () => "u1" });
    expect(response.statusCode).toBe(400);
  });
});

describe("DynamoDB quota store", () => {
  it("counts atomically and reports a full counter", async () => {
    const sent: string[] = [];
    let full = false;
    const client = {
      send: async (command: { constructor: { name: string } }) => {
        sent.push(command.constructor.name);
        if (command.constructor.name === "UpdateItemCommand") {
          if (full) throw new ConditionalCheckFailedException({ message: "full", $metadata: {} });
          return { Attributes: { count: { N: "1" } } };
        }
        return { Item: { count: { N: "3" } } };
      },
    };
    const store = new DynamoQuotaStore("quotas", client as never);
    expect(await store.consume("k", 3, new Date())).toEqual({ allowed: true, count: 1 });
    full = true;
    expect(await store.consume("k", 3, new Date())).toEqual({ allowed: false, count: 3 });
    expect(sent).toEqual(["UpdateItemCommand", "UpdateItemCommand", "GetItemCommand"]);
  });
});
