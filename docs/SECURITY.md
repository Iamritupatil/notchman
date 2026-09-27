# Notchman security & privacy

> **Current mode: free, on-device.** `FeatureFlags.cloudTLDR` and `FeatureFlags.paidPlans` are off. TL;DRs (10 a month), voices and screenshot reading all run on the iPhone. There's no server, no API keys and no data collection, so the App Store privacy answer is "Data Not Collected". Everything below the line applies only once the cloud backend is switched on for Pro and Pro+. At that point, add User ID, Purchase History and Other User Content back to `PrivacyInfo.xcprivacy`.

---

## Secrets

| Secret | Where it lives |
|---|---|
| Groq API key (`GROQ_API_KEY`) | AWS Systems Manager Parameter Store (SecureString), read by the Lambda at runtime. Never in the app, the repo or CI. |
| ElevenLabs API key (`ELEVENLABS_API_KEY`) | Same as the Groq key. Restrict it to Text to Speech and give it a character limit. |
| App Store Server keys (future) | Same as the Groq key |

The app bundle contains no secrets. `GoogleService-Info.plist` only identifies the Firebase project; access is controlled by App Check, Auth and server-side rules, not by keeping that file private.

## Protecting the backend

1. **App Check with App Attest** makes sure calls come from the genuine app on a real device. `tldr` tokens are single-use.
2. **Firebase Auth**: each user has an anonymous account, and allowances are tied to it.
3. **Server-side limits**: monthly plan allowances (Free 0, Pro 40, Pro+ 100), 6 requests per minute per user, and input size limits. Free users never reach the paid APIs.
4. **Receipt verification**: Pro and Pro+ come from Apple-signed StoreKit transactions that the server verifies. Paid allowances follow the subscription.
5. **DynamoDB** is reachable only by the Lambda's IAM role; counters expire through a TTL.
6. **Spending alerts**: set a AWS budget alert, a Groq spend limit and an ElevenLabs key character limit before launch.

## On the device

- **History** is stored locally with SwiftData and never uploaded.
- **Account data** (the Sign in with Apple identity) is kept in the Keychain.
- **Network**: HTTPS only, under App Transport Security's defaults. There are no exceptions.
- **Logo lookups** send only an app name or a domain, never message content.
- **Privacy manifests** (`PrivacyInfo.xcprivacy`) exist for the app and each extension. They declare no tracking.

## Data handling

For Pro and Pro+, text sent for a TL;DR is processed by the Notchman Lambda, Groq (summary) and ElevenLabs (voice). Notchman doesn't store or log it; it stores only per-user monthly counters, which expire automatically. Groq and ElevenLabs handle the text under their own data policies, so name them as processors in your privacy policy. ElevenLabs keeps generated audio in the account's history unless zero-retention mode is available on your plan. Your App Store privacy answers should match `PrivacyInfo.xcprivacy`:
- **User ID** (the anonymous account), used for app functionality
- **Purchase history** (plan verification), used for app functionality
- **Other user content** (the message being summarized), used for app functionality and not linked to the user's identity

## Before submitting to the App Store

- [ ] Firebase App Check has App Attest registered, and `FirebaseAppId` is set on the server so only Notchman's tokens are accepted.
- [ ] `BetaDailyTLDRs` is set to 0 once subscriptions are live.
- [ ] AWS budget alerts, a Groq spend limit and an ElevenLabs key character limit are set.
- [ ] `APPLE_APP_ID` is set, so real App Store purchases verify.
- [ ] Review the Share Extension's direct "open app" call (`ShareViewController.openContainingApp`). It's not a documented API, and App Review may object. The notification fallback already covers the flow if you remove it.
