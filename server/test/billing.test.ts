import { Webhook } from "standardwebhooks";
import { describe, expect, it } from "vitest";
import { applyWebhook, createCheckout, dodoEntitlement, linkSubscription, verifyWebhook } from "../src/billing.js";
import { route } from "../src/lambda.js";
import { resolveEntitlement } from "../src/entitlements.js";
import { MemoryQuotaStore } from "../src/quota.js";

const SECRET = "whsec_" + Buffer.from("notchman-test-secret-0123456789ab").toString("base64");
const INSTALL = "5e7c0c4e-0000-4000-8000-5e7c0c4ec4ec";

function signed(body: string, at = new Date()) {
  const id = "msg_1";
  const signature = new Webhook(SECRET).sign(id, at, body);
  return { "webhook-id": id, "webhook-timestamp": String(Math.floor(at.getTime() / 1000)), "webhook-signature": signature };
}

describe("Dodo Payments", () => {
  process.env.DODO_PRO_PRODUCT_ID = "pdt_pro";
  process.env.DODO_PROPLUS_PRODUCT_ID = "pdt_plus";

  it("accepts Dodo's signatures (Standard Webhooks) and rejects anything else", () => {
    const body = JSON.stringify({ type: "subscription.active" });
    expect(verifyWebhook(body, signed(body), SECRET)).toBe(true);
    expect(verifyWebhook(body + " ", signed(body), SECRET)).toBe(false);
    expect(verifyWebhook(body, signed(body, new Date(Date.now() - 10 * 60_000)), SECRET)).toBe(false);
    expect(verifyWebhook(body, {}, SECRET)).toBe(false);
  });

  it("turns an active subscription into the plan, and an expired one back into Free", async () => {
    const store = new MemoryQuotaStore();
    const next = new Date(Date.now() + 20 * 86_400_000).toISOString();
    const event = (type: string, status: string) => ({ type, data: {
      subscription_id: "sub_1", product_id: "pdt_plus", status, next_billing_date: next, metadata: { install_id: INSTALL },
    } });
    await applyWebhook(event("subscription.active", "active"), store);
    expect(await dodoEntitlement(INSTALL, store)).toEqual({ plan: "proplus", accountKey: "dodo:sub_1" });
    expect(await resolveEntitlement(INSTALL, [], Date.now(), store)).toMatchObject({ plan: "proplus" });
    // Cancelled: still paid until the billing date.
    await applyWebhook(event("subscription.cancelled", "cancelled"), store);
    expect(await dodoEntitlement(INSTALL, store)).toMatchObject({ plan: "proplus" });
    await applyWebhook(event("subscription.expired", "expired"), store);
    expect(await dodoEntitlement(INSTALL, store)).toBeNull();
  });

  it("creates a checkout for this install's plan", async () => {
    process.env.DODO_API_KEY = "sk_test";
    process.env.DODO_ENVIRONMENT = "test_mode";
    let sent: { url: string; body: Record<string, unknown> } | undefined;
    const fetchImpl = (async (url: string, init?: RequestInit) => {
      sent = { url, body: JSON.parse(String(init?.body)) };
      return new Response(JSON.stringify({ session_id: "cks_1", checkout_url: "https://checkout.dodopayments.com/x" }), { status: 200 });
    }) as unknown as typeof fetch;
    expect(await createCheckout(INSTALL, "pro", fetchImpl)).toBe("https://checkout.dodopayments.com/x");
    expect(sent?.url).toBe("https://test.dodopayments.com/checkouts");
    expect(sent?.body).toMatchObject({ product_cart: [{ product_id: "pdt_pro", quantity: 1 }], metadata: { install_id: INSTALL, plan: "pro" } });
    delete process.env.DODO_API_KEY;
  });
});

describe("what happens when someone pays (the whole chain)", () => {
  process.env.DODO_PRO_PRODUCT_ID = "pdt_pro";
  process.env.DODO_PROPLUS_PRODUCT_ID = "pdt_plus";
  const APP_INSTALL = "8a1f3c2e-1111-4222-8333-944455556666";
  const next = () => new Date(Date.now() + 30 * 86_400_000).toISOString();
  const request = (path: string, body: unknown, headers: Record<string, string> = {}) => ({
    rawPath: path, body: typeof body === "string" ? body : JSON.stringify(body), isBase64Encoded: false, headers,
    requestContext: { http: { method: "POST", sourceIp: "203.0.113.9" } },
  }) as never;
  const inbox = () => {
    const mails: string[] = [];
    return { mails, notify: async (subject: string) => { mails.push(subject); } };
  };

  async function checkoutMetadata(): Promise<Record<string, unknown>> {
    process.env.DODO_API_KEY = "sk_test";
    process.env.DODO_ENVIRONMENT = "live_mode";
    let metadata: Record<string, unknown> = {};
    const fetchImpl = (async (_url: string, init: RequestInit) => {
      metadata = JSON.parse(String(init.body)).metadata;
      return new Response(JSON.stringify({ checkout_url: "https://checkout.dodopayments.com/x" }));
    }) as unknown as typeof fetch;
    // The app's request carries its install ID; the server names it "install:<id>".
    await createCheckout(`install:${APP_INSTALL}`, "pro", fetchImpl);
    delete process.env.DODO_API_KEY;
    delete process.env.DODO_ENVIRONMENT;
    return metadata;
  }

  async function deliver(type: string, data: Record<string, unknown>, deps: Record<string, unknown>) {
    process.env.DODO_WEBHOOK_SECRET = SECRET;
    const body = JSON.stringify({ type, data });
    const response = await route(request("/dodo-webhook", body, signed(body)), { deps: deps as never });
    expect(response.statusCode).toBe(200);
  }

  async function planInApp(deps: Record<string, unknown>) {
    const response = await route(request("/usage", {}, { "x-notchman-install": APP_INSTALL }), { deps: deps as never });
    return JSON.parse(String(response.body)).plan;
  }

  it("pays → Dodo's webhook → the app shows Pro, and the owner gets one email", async () => {
    const store = new MemoryQuotaStore();
    const { mails, notify } = inbox();
    const deps = { store, notify, voiceBalance: async () => undefined };
    const metadata = await checkoutMetadata();
    expect(await planInApp(deps)).toBe("free");
    const sub = { subscription_id: "sub_live_1", product_id: "pdt_pro", status: "active", next_billing_date: next(), metadata };
    await deliver("payment.succeeded", { payment_id: "pay_1", subscription_id: "sub_live_1", metadata }, deps);
    await deliver("subscription.active", sub, deps);
    await deliver("subscription.active", sub, deps); // Dodo retries: still one email
    expect(await planInApp(deps)).toBe("pro");
    expect(mails).toEqual(["Notchman: new Pro subscriber"]);
    // Renewal keeps it; expiry ends it.
    await deliver("subscription.renewed", { ...sub, next_billing_date: next() }, deps);
    expect(await planInApp(deps)).toBe("pro");
    await deliver("subscription.expired", { ...sub, status: "expired" }, deps);
    expect(await planInApp(deps)).toBe("free");
  });

  it("links a subscription that arrives without the install, as soon as the payment names it", async () => {
    const store = new MemoryQuotaStore();
    const { mails, notify } = inbox();
    const deps = { store, notify, voiceBalance: async () => undefined };
    const metadata = await checkoutMetadata();
    await deliver("subscription.active", { subscription_id: "sub_2", product_id: "pdt_pro", status: "active", next_billing_date: next() }, deps);
    expect(await planInApp(deps)).toBe("free");
    expect(mails).toEqual(["Notchman: a payment needs linking"]);
    await deliver("payment.succeeded", { payment_id: "pay_2", subscription_id: "sub_2", metadata }, deps);
    expect(await planInApp(deps)).toBe("pro");
  });

  it("the owner can link a payment by hand with the app's Install ID", async () => {
    const store = new MemoryQuotaStore();
    process.env.DODO_API_KEY = "sk_test";
    process.env.DODO_ENVIRONMENT = "live_mode";
    const fetchImpl = (async () => new Response(JSON.stringify({
      subscription_id: "sub_3", product_id: "pdt_plus", status: "active", next_billing_date: next(),
    }))) as unknown as typeof fetch;
    await expect(linkSubscription("not-an-id", "sub_3", store, fetchImpl)).rejects.toThrow(/install ID/);
    await linkSubscription(APP_INSTALL.toUpperCase(), "sub_3", store, fetchImpl);
    delete process.env.DODO_API_KEY;
    delete process.env.DODO_ENVIRONMENT;
    expect(await planInApp({ store, voiceBalance: async () => undefined })).toBe("proplus");
  });

  it("our own simulated payment never emails the owner", async () => {
    const store = new MemoryQuotaStore();
    const { mails, notify } = inbox();
    const metadata = { ...(await checkoutMetadata()), notchman_test: "true" };
    await deliver("subscription.active", { subscription_id: "sub_t", product_id: "pdt_pro", status: "active", next_billing_date: next(), metadata },
      { store, notify });
    expect(mails).toEqual([]);
  });
});
