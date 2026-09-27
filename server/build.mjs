// Bundles the Lambda into dist/ for `sam deploy`. The AWS SDK is part of the
// Lambda Node.js runtime, so it isn't bundled.
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
  external: ["@aws-sdk/*"],
  banner: { js: "import { createRequire } from 'node:module'; const require = createRequire(import.meta.url);" },
  legalComments: "none",
});
await writeFile("dist/package.json", JSON.stringify({ type: "module" }));
console.log("Bundled dist/lambda.mjs");
