// Bundles the Lambda into dist/ for `sam deploy`.
import { build } from "esbuild";
import { mkdir, writeFile } from "node:fs/promises";

await mkdir("dist", { recursive: true });
await build({
  entryPoints: ["src/lambda.ts"],
  outfile: "dist/lambda.mjs",
  bundle: true,
  platform: "node",
  target: "node22",
  format: "esm",
  // The Lambda runtime has the AWS SDK clients this code uses; the Bedrock
  // SDK's own AWS pieces (signing, credentials) are bundled with it.
  external: ["@aws-sdk/client-dynamodb", "@aws-sdk/client-sns", "@aws-sdk/client-ssm"],
  banner: { js: "import { createRequire } from 'node:module'; const require = createRequire(import.meta.url);" },
  legalComments: "none",
});
await writeFile("dist/package.json", JSON.stringify({ type: "module" }));
console.log("Bundled dist/lambda.mjs");
