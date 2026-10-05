import { GetParametersCommand, SSMClient } from "@aws-sdk/client-ssm";

/**
 * The API keys come from AWS Systems Manager Parameter Store (SecureString)
 * into process.env. The keys never exist in the app, the repo or the Lambda
 * configuration.
 */
// Optional: REVENUECAT_SECRET_KEY (desktop purchases), AZURE_SPEECH_KEY (standard voice),
// DODO_API_KEY and DODO_WEBHOOK_SECRET (desktop payments).
const NAMES = ["GROQ_API_KEY", "ELEVENLABS_API_KEY", "REVENUECAT_SECRET_KEY", "AZURE_SPEECH_KEY", "DODO_API_KEY", "DODO_WEBHOOK_SECRET"] as const;
let loaded: Promise<void> | undefined;
let loadedAt = 0;

/**
 * Loads the keys once per Lambda instance, and looks again every 5 minutes
 * for any that are still missing (so a key added to Parameter Store later,
 * like Dodo's or Azure's, is picked up without a redeploy).
 */
export function loadSecrets(prefix = process.env.SECRETS_PREFIX ?? "/notchman/"): Promise<void> {
  const missing = NAMES.filter((name) => !process.env[name]);
  if (loaded && (missing.length === 0 || Date.now() - loadedAt < 5 * 60_000)) return loaded;
  loadedAt = Date.now();
  loaded = (async () => {
    if (missing.length === 0) return;
    const result = await new SSMClient({}).send(new GetParametersCommand({
      Names: missing.map((name) => prefix + name),
      WithDecryption: true,
    }));
    for (const parameter of result.Parameters ?? []) {
      const name = parameter.Name?.slice(prefix.length);
      if (name && parameter.Value) process.env[name] = parameter.Value;
    }
    if (result.InvalidParameters?.length) console.warn("not in Parameter Store:", result.InvalidParameters.join(", "));
  })().catch((error) => {
    loaded = undefined; // retry on the next request
    throw error;
  });
  return loaded;
}

/** Which keys this server has (yes/no only, never the values): for /status. */
export function configuredSecrets(): Record<string, boolean> {
  return Object.fromEntries(NAMES.map((name) => [name, Boolean(process.env[name])]));
}
