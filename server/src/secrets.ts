import { GetParametersCommand, SSMClient } from "@aws-sdk/client-ssm";

/**
 * Loads the API keys from AWS Systems Manager Parameter Store (SecureString)
 * into process.env once per Lambda instance. The keys never exist in the app,
 * the repo or the Lambda configuration.
 */
const NAMES = ["GROQ_API_KEY", "ELEVENLABS_API_KEY"] as const;
let loaded: Promise<void> | undefined;

export function loadSecrets(prefix = process.env.SECRETS_PREFIX ?? "/notchman/"): Promise<void> {
  loaded ??= (async () => {
    const missing = NAMES.filter((name) => !process.env[name]);
    if (missing.length === 0) return;
    const result = await new SSMClient({}).send(new GetParametersCommand({
      Names: missing.map((name) => prefix + name),
      WithDecryption: true,
    }));
    for (const parameter of result.Parameters ?? []) {
      const name = parameter.Name?.slice(prefix.length);
      if (name && parameter.Value) process.env[name] = parameter.Value;
    }
  })().catch((error) => {
    loaded = undefined; // retry on the next request
    throw error;
  });
  return loaded;
}
