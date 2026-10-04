import { Webhook } from "standardwebhooks";
import { describe, expect, it } from "vitest";
import { applyWebhook, createCheckout, dodoEntitlement, verifyWebhook } from "../src/billing.js";
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
