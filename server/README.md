# Notchman server (AWS Lambda)

This server makes the cloud TL;DRs:

- **Summary:** Groq `openai/gpt-oss-120b`, written in the message's language.
- **Voice:** ElevenLabs Flash v2.5, a natural voice in 32 languages.
- **Limits:** per-user limits are counted in DynamoDB.

It runs on **AWS Lambda** (a Function URL) and costs only what you use. For testing, that's close to $0 and covered by AWS credits.

**Security**
- **Only the real app can call it.** Firebase **App Check** (App Attest) checks that each request comes from the genuine Notchman app on a real iPhone.
- **Every user has an identity.** Firebase **anonymous Auth** gives each user an ID so their TL;DRs can be counted. Both App Check and Auth are free on Firebase's Spark plan, so no Blaze or card is needed.
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

### 4. Set up Firebase (free Spark plan)

In the Firebase console, open your project:

1. **Authentication** → **Sign-in method** → turn on **Anonymous**.
2. **Project settings** → **Your apps** → **Add app** → **iOS**, with bundle ID `app.notchman`.
   - Download **GoogleService-Info.plist**.
   - Note the app's **App ID**, which looks like `1:1234567890:ios:abc123`.
3. **App Check** → **Apps** → Notchman → register **App Attest**.
4. **Project settings** → note the **Project ID** and **Project number**.

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
| FirebaseProjectId / FirebaseProjectNumber / FirebaseAppId | from step 4 |
| Other parameters | press Enter for the defaults |
| "ApiFunction Function Url has no authentication. Is this okay?" | **y**. The server checks the Firebase tokens itself. |
| "Save arguments to configuration file" | **y** |

At the end it prints **ApiUrl**, something like `https://abc123.lambda-url.us-east-1.on.aws/`. From then on, `npm run deploy` redeploys without questions.

### 6. Connect the TestFlight build

In the GitHub repo, go to **Settings** → **Secrets and variables** → **Actions**:

- **Variables** tab → **New repository variable**
  - `NOTCHMAN_API_URL` = the **ApiUrl** from step 5
- **Secrets** tab → **New repository secret**
  - `GOOGLE_SERVICE_INFO_PLIST_BASE64` = the plist, base64-encoded. In PowerShell, in the folder with the file:
    ```powershell
    [Convert]::ToBase64String([IO.File]::ReadAllBytes("GoogleService-Info.plist")) | Set-Clipboard
    ```
    Then paste it as the secret value.

Then run **Actions → TestFlight**. TL;DRs in that build use Groq and the ElevenLabs voice.

---

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
