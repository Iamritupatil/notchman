# Notchman backend (Firebase)

Cloud Functions that make TL;DRs. The app never contains an API key; the OpenAI key lives only in Google Secret Manager.

| Plan | TL;DRs / month |
|---|---|
| Free | 10 |
| Pro | 100 |
| Pro+ | 250 |

Functions (both are callable from the app):

| Function | Request | Response |
|---|---|---|
| `tldr` | `{ text, length?, transactions? }` | `{ summary, plan, used, limit, remaining }` |
| `usage` | `{ transactions? }` | `{ plan, used, limit, remaining }` |

## Security

- **App Check (App Attest)** is enforced on every call. Only the genuine Notchman app on a real iPhone gets through, and `tldr` tokens are single-use, which blocks replays.
- **Firebase Auth** is required. Every user has an anonymous account, and allowances are counted per user.
- **Plans come from Apple-signed StoreKit transactions**, which the backend verifies. Forged receipts count as Free. Paid allowances follow the subscription, so reinstalling doesn't reset them.
- **Limits** are enforced by the server:
  - monthly TL;DRs per plan
  - 6 requests per user per minute
  - input size
  - a daily ceiling on total Free TL;DRs (`FREE_DAILY_GLOBAL_CAP`)
- **Failed summaries are refunded**, so users aren't charged for errors.
- **Firestore rules deny all client access.** Only the functions can read or write the counters.
- **Message text is never stored or logged.** Only counters are kept, and they expire automatically.

## Set up (once)

1. **Create the project.** At [console.firebase.google.com](https://console.firebase.google.com), create a project and switch it to the **Blaze** plan. Cloud Functions need Blaze, and the free usage allowance still applies. Put the project ID in `.firebaserc`.
2. **Register the iOS app.** Add an iOS app with bundle ID `com.notchman.app`. Download **GoogleService-Info.plist** into `Notchman/Resources/`. Without it, the app skips the cloud and summarizes on device.
3. **Anonymous sign-in.** Go to Authentication → Sign-in method and enable **Anonymous**.
4. **App Check.** Go to App Check → Apps → Notchman and register **App Attest**. Then go to App Check → APIs → Cloud Functions and choose **Enforce**. For the simulator, register the debug token that Xcode prints on launch.
5. **Firestore.** Create a Firestore database. Then add a TTL policy on collection `quotas`, field `expiresAt`, so old counters delete themselves.
6. **Store the OpenAI key.** This is the only place it ever goes:
   ```bash
   cd firebase
   firebase functions:secrets:set OPENAI_API_KEY
   ```
7. **Deploy:**
   ```bash
   cd firebase/functions && npm install && npm run deploy
   ```

## Configuration

These optional settings go in `firebase/functions/.env`, which isn't committed:

| Name | Default | Meaning |
|---|---|---|
| `OPENAI_MODEL` | `gpt-5.4-nano` | Model used for TL;DRs |
| `FREE_DAILY_GLOBAL_CAP` | `5000` | Most Free TL;DRs per day across all users |
| `APPLE_BUNDLE_ID` | `com.notchman.app` | Must match the app |
| `APPLE_APP_ID` | — | The app's numeric Apple ID. Required to accept real App Store purchases. |
| `ALLOW_XCODE_TRANSACTIONS` | — | `true` only for development, so purchases made through Xcode's StoreKit testing count |

## Spending safety

- **Google Cloud:** Billing → Budgets & alerts. Set a monthly budget with email alerts.
- **OpenAI:** set a monthly **usage limit** in the OpenAI dashboard.

## Develop

```bash
cd firebase/functions
npm install
npm test
npm run typecheck
```
