# Notchman server (AWS Lambda)

This server makes the cloud TL;DRs:

- **Summary:** Groq `openai/gpt-oss-120b`, written in the message's language.
- **Voice:** ElevenLabs Flash v2.5, a natural voice in 32 languages.
- **Limits:** per-user limits are counted in DynamoDB.

It runs on **AWS Lambda** (a Function URL) and costs only what you use. For testing, that's close to $0 and covered by AWS credits.

**Security and cost**
- **Every install has an ID.** The app sends a random install ID (kept in the iPhone's Keychain); daily limits are counted per install.
- **Spending is capped.** Besides per-install limits, the server stops at a total daily cap across all users (`GlobalDailyTLDRs`, `GlobalDailyVoiceCharacters`), so the Groq and ElevenLabs bills can't run away.
- **API keys stay on AWS.** The Groq and ElevenLabs keys live in **AWS Systems Manager Parameter Store**. They're never in the app, the repo or a chat.
- **Messages aren't kept.** Message text is never stored or logged. Only counters are stored, and they expire automatically.

| Endpoint | Body | Reply |
|---|---|---|
| `POST /tldr` | `{ text, length?, transactions? }` | `{ summary, audio?, audioFormat?, plan, used, limit, remaining }` (`audio` is a base64 MP3) |
| `POST /usage` | `{ transactions? }` | `{ plan, used, limit, remaining }` |

**Beta:** while subscriptions aren't live, every TestFlight tester gets `BetaDailyTLDRs` cloud TL;DRs per day (default 20). Set it to `0` to turn this off.

---

## Set up (once, from Windows)

### 1. Install the tools

- **AWS CLI:** <https://awscli.amazonaws.com/AWSCLIV2.msi>
- **AWS SAM CLI:** <https://github.com/aws/aws-sam-cli/releases/latest/download/AWS_SAM_CLI_64_PY3.msi>
- **Node.js 22:** <https://nodejs.org>

Open a **new** PowerShell window afterwards.

### 2. Sign the CLI in to AWS

1. In the AWS console, go to **IAM** → **Users** → **Create user** (for example `notchman-deploy`).
2. Attach the policy **AdministratorAccess**. This is for deploying only.
3. Open the user → **Security credentials** → **Create access key** → choose **Command Line Interface**.
4. Run this and paste the key ID and secret when asked. Use region `us-east-1`, which is close to Groq and ElevenLabs.
   ```powershell
   aws configure
   ```

### 3. Store the API keys in AWS (not in the app, repo or chat)

In the AWS console (region **us-east-1**), go to **Systems Manager** → **Parameter Store** → **Create parameter**. Create two parameters:

| Name | Type | Value |
|---|---|---|
| `/notchman/GROQ_API_KEY` | **SecureString** | your Groq key |
| `/notchman/ELEVENLABS_API_KEY` | **SecureString** | your ElevenLabs key |

### 5. Deploy

```powershell
cd notchman\server
npm install
npm run deploy:first
```

When it asks, answer:

| Question | Answer |
|---|---|
| Stack Name | `notchman` |
| AWS Region | `us-east-1` |
| FirebaseProjectId / FirebaseProjectNumber / FirebaseAppId | press Enter (unused) |
| Other parameters | press Enter for the defaults |
| "ApiFunction Function Url has no authentication. Is this okay?" | **y**. The server applies its own limits. |
| "Save arguments to configuration file" | **y** |

At the end it prints **ApiUrl**, something like `https://abc123.lambda-url.us-east-1.on.aws/`. From then on, `npm run deploy` redeploys without questions.

### 6. Connect the TestFlight build

Put the printed **ApiUrl** in `project.yml` as `NOTCHMAN_API_URL` (or send it to Claude). Then run **Actions → TestFlight**.

---

## Deploy from GitHub (no PowerShell)

Add two repository secrets (Settings → Secrets and variables → Actions → Secrets):

| Name | Value |
|---|---|
| `AWS_ACCESS_KEY_ID` | the `notchman-deploy` user's access key ID |
| `AWS_SECRET_ACCESS_KEY` | its secret access key |

From then on, every change to `server/` deploys itself (Actions → **Deploy server**), and you can run it by hand from the same page. The Groq and ElevenLabs keys stay in Parameter Store.

## Try the keys without deploying

```powershell
cd notchman\server
npm install
npm run try
```

This asks for both keys (hidden), prints a TL;DR and saves `tldr-test.mp3`.

## Develop

```bash
npm test          # handlers, Lambda routing, token checks, DynamoDB store
npm run typecheck
npm run bundle    # → dist/lambda.mjs
```

## Watch spending

- **AWS:** Billing → Budgets → create a monthly budget alert.
- **Groq:** set a spend limit.
- **ElevenLabs:** set a character limit on the API key.
