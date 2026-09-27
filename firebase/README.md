# Notchman backend (Firebase)

Cloud Functions that make Pro and Pro+ TL;DRs. Each TL;DR is:

1. summarized by **Groq** (`openai/gpt-oss-120b`), in the same language as the message
2. recorded by **ElevenLabs** (`eleven_flash_v2_5`, 32 languages) as a 64 kbps MP3

The voice is best-effort. If ElevenLabs fails, the summary still comes back and the app reads it with Apple's voice. The app never contains an API key; both keys live only in Google Secret Manager.

| Plan | Cloud TL;DRs / month | Where |
|---|---|---|
| Free | 0 (10 on device) | iPhone only; never calls these functions successfully |
| Pro | 40 | Server |
| Pro+ | 100 | Server |

Cost per cloud TL;DR is about $0.046: ElevenLabs Flash about $0.045 for a one-minute summary, Groq about $0.0006.

Functions (both are callable from the app):

| Function | Request | Response |
|---|---|---|
| `tldr` | `{ text, length?, transactions? }` | `{ summary, audio?, audioFormat?, plan, used, limit, remaining }`. `audio` is a base64 MP3. |
| `usage` | `{ transactions? }` | `{ plan, used, limit, remaining }` |

## Security

- **App Check (App Attest)** is enforced on every call. Only the genuine Notchman app on a real iPhone gets through, and `tldr` tokens are single-use, which blocks replays.
- **Firebase Auth** is required. Every user has an anonymous account, and allowances are counted per user.
- **Plans come from Apple-signed StoreKit transactions**, which the backend verifies. Forged receipts count as Free. Paid allowances follow the subscription, so reinstalling doesn't reset them.
- **Limits** are enforced by the server:
  - monthly TL;DRs per plan
  - 6 requests per user per minute
  - input size
  - Free gets 0, so free users can never run up a bill
- **Failed summaries are refunded**, so users aren't charged for errors.
- **Firestore rules deny all client access.** Only the functions can read or write the counters.
- **Message text is never stored or logged.** Only counters are kept, and they expire automatically.

## Set up (once)

Step-by-step guide, including running the app: [docs/TESTING.md](../docs/TESTING.md). To check your keys first without Firebase, run `npm run try` in `firebase/functions`.

1. **Create the project.** At [console.firebase.google.com](https://console.firebase.google.com), create a project and switch it to the **Blaze** plan. Cloud Functions need Blaze, and the free usage allowance still applies. Then, from the `firebase` folder, run `firebase use --add`, pick the project and name it `default`.
2. **Register the iOS app.** Add an iOS app with bundle ID `app.notchman`. Download **GoogleService-Info.plist** into `Notchman/Resources/`. Without it, the app skips the cloud and summarizes on device. Then set `cloudTLDR` and `paidPlans` to `true` in `Notchman/Core/Shared/FeatureFlags.swift`.
3. **Anonymous sign-in.** Go to Authentication → Sign-in method and enable **Anonymous**.
4. **App Check.** Go to App Check → Apps → Notchman and register **App Attest**. Then go to App Check → APIs → Cloud Functions and choose **Enforce**. For the simulator, register the debug token that Xcode prints on launch.
5. **Firestore.** Create a Firestore database. Then add a TTL policy on collection `quotas`, field `expiresAt`, so old counters delete themselves.
6. **Store the API keys.** This is the only place they ever go. Each command asks you to paste the key; never put keys in the app, the repo or a chat:
   ```bash
   cd firebase
   firebase functions:secrets:set GROQ_API_KEY         # console.groq.com → API Keys
   firebase functions:secrets:set ELEVENLABS_API_KEY   # elevenlabs.io → Developers → API Keys
   ```
   On ElevenLabs, give the key access to **Text to Speech** only, and set a character limit on it.
7. **Deploy:**
   ```bash
   cd firebase/functions && npm install && npm run deploy
   ```

## Configuration

These optional settings go in `firebase/functions/.env`, which isn't committed:

| Name | Default | Meaning |
|---|---|---|
| `GROQ_MODEL` | `openai/gpt-oss-120b` | Summary model. `openai/gpt-oss-20b` costs half as much. |
| `ELEVENLABS_VOICE_ID` | `21m00Tcm4TlvDq8ikWAM` (Rachel) | Voice. Pick one in ElevenLabs' Voice Library and paste its ID. |
| `ELEVENLABS_MODEL` | `eleven_flash_v2_5` | Voice model. Flash is multilingual and half the price of `eleven_multilingual_v2`. |
| `APPLE_BUNDLE_ID` | `app.notchman` | Must match the app |
| `APPLE_APP_ID` | — | The app's numeric Apple ID. Required to accept real App Store purchases. |
| `ALLOW_XCODE_TRANSACTIONS` | — | `true` only for development, so purchases made through Xcode's StoreKit testing count |

## Spending safety

- **Google Cloud:** Billing → Budgets & alerts. Set a monthly budget with email alerts.
- **Groq:** set a monthly spend limit under Settings → Billing.
- **ElevenLabs:** choose a plan whose included characters cover your Pro/Pro+ usage, turn on usage-based billing only with a cap, and set a character limit on the API key.

## Develop

```bash
cd firebase/functions
npm install
npm test
npm run typecheck
```
