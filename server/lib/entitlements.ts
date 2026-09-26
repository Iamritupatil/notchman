import { Environment, SignedDataVerifier } from "@apple/app-store-server-library";
import { PLANS, PRODUCT_PLANS, type PlanID } from "./plans.js";

export interface Entitlement {
  plan: PlanID;
  /** Quota is counted per subscription for paid plans (survives reinstalls), per install for Free. */
  accountKey: string;
}

const PLAN_RANK: Record<PlanID, number> = { free: 0, pro: 1, proplus: 2 };
const APPLE_ROOTS = [
  "https://www.apple.com/certificateauthority/AppleRootCA-G3.cer",
  "https://www.apple.com/certificateauthority/AppleRootCA-G2.cer",
  "https://www.apple.com/appleca/AppleIncRootCertificate.cer",
];

let rootCertificates: Promise<Buffer[]> | undefined;

/** Apple's root CAs, from APPLE_ROOT_CERTS_BASE64 (comma-separated DER) or downloaded once from apple.com. */
function appleRoots(): Promise<Buffer[]> {
  rootCertificates ??= (async () => {
    const configured = process.env.APPLE_ROOT_CERTS_BASE64;
    if (configured) return configured.split(",").map((c) => Buffer.from(c.trim(), "base64"));
    const certs = await Promise.all(APPLE_ROOTS.map(async (url) => {
      const response = await fetch(url);
      if (!response.ok) throw new Error(`Couldn't download ${url}: ${response.status}`);
      return Buffer.from(await response.arrayBuffer());
    }));
    return certs;
  })();
  return rootCertificates;
}

const verifiers = new Map<Environment, SignedDataVerifier>();

async function verifierFor(environment: Environment): Promise<SignedDataVerifier> {
  const cached = verifiers.get(environment);
  if (cached) return cached;
  const bundleId = process.env.APPLE_BUNDLE_ID ?? "com.notchman.app";
  const appAppleId = process.env.APPLE_APP_ID ? Number(process.env.APPLE_APP_ID) : undefined;
  const verifier = new SignedDataVerifier(await appleRoots(), true, environment, bundleId, appAppleId);
  verifiers.set(environment, verifier);
  return verifier;
}

/** Reads the (unverified) environment claim so we pick the matching verifier. */
export function claimedEnvironment(jws: string): Environment | undefined {
  try {
    const payload = JSON.parse(Buffer.from(jws.split(".")[1], "base64url").toString("utf8"));
    const value = payload.environment as string;
    return (Object.values(Environment) as string[]).includes(value) ? (value as Environment) : undefined;
  } catch {
    return undefined;
  }
}

function environmentAllowed(environment: Environment): boolean {
  if (environment === Environment.PRODUCTION) return Boolean(process.env.APPLE_APP_ID);
  if (environment === Environment.SANDBOX) return process.env.ALLOW_SANDBOX_TRANSACTIONS !== "false";
  // Xcode / local StoreKit testing transactions aren't signed by Apple; development only.
  return process.env.ALLOW_XCODE_TRANSACTIONS === "true";
}

/**
 * Works out the caller's plan from the StoreKit transactions the app sends
 * (`Transaction.currentEntitlements` JWS strings). Anything that fails
 * verification is ignored, so a forged receipt simply means the Free plan.
 */
export async function resolveEntitlement(installId: string, signedTransactions: string[] = [],
                                         now = Date.now()): Promise<Entitlement> {
  let best: Entitlement = { plan: "free", accountKey: `install:${installId}` };
  for (const jws of signedTransactions.slice(0, 10)) {
    const environment = claimedEnvironment(jws);
    if (!environment || !environmentAllowed(environment)) continue;
    try {
      const transaction = await (await verifierFor(environment)).verifyAndDecodeTransaction(jws);
      const plan = transaction.productId ? PRODUCT_PLANS[transaction.productId] : undefined;
      if (!plan || transaction.revocationDate) continue;
      if (transaction.expiresDate && transaction.expiresDate < now) continue;
      if (PLAN_RANK[plan] > PLAN_RANK[best.plan]) {
        best = { plan, accountKey: `sub:${transaction.originalTransactionId ?? transaction.transactionId}` };
      }
    } catch {
      // Unverifiable receipts are treated as absent.
    }
  }
  return best;
}

export { PLANS };
