# Notchman security & privacy

> **Current mode: free, on-device.** `FeatureFlags.cloudTLDR` and `FeatureFlags.paidPlans` are off. TL;DRs, voices and screenshot reading all run on the iPhone. There's no server, no API keys and no data collection, so the App Store privacy answer is "Data Not Collected". Everything below the line applies only once the cloud backend is switched on. At that point, add User ID and Purchase History back to `PrivacyInfo.xcprivacy`.

---

## Secrets

| Secret | Where it lives |
|---|---|
| OpenAI API key | Google Secret Manager, read by Cloud Functions at runtime. Never in the app, the repo or CI. |
| ElevenLabs key (future) | Same as the OpenAI key |
| App Store Server keys (future) | Same as the OpenAI key |

The app bundle contains no secrets. `GoogleService-Info.plist` only identifies the Firebase project; access is controlled by App Check, Auth and server-side rules, not by keeping that file private.

## Protecting the backend

1. **App Check with App Attest** makes sure calls come from the genuine app on a real device. `tldr` tokens are single-use.
2. **Firebase Auth**: each user has an anonymous account, and allowances are tied to it.
3. **Server-side limits**: monthly plan allowances, 6 requests per minute per user, input size limits, and a daily Free-tier ceiling.
4. **Receipt verification**: Pro and Pro+ come from Apple-signed StoreKit transactions that the server verifies. Paid allowances follow the subscription.
5. **Firestore rules** deny all client access.
6. **Spending alerts**: set a Google Cloud budget alert and an OpenAI usage limit before launch.

## On the device

- **History** is stored locally with SwiftData and never uploaded.
- **Account data** (the Sign in with Apple identity) is kept in the Keychain.
- **Network**: HTTPS only, under App Transport Security's defaults. There are no exceptions.
- **Logo lookups** send only an app name or a domain, never message content.
- **Privacy manifests** (`PrivacyInfo.xcprivacy`) exist for the app and each extension. They declare no tracking.

## Data handling

Text sent for a TL;DR is processed by the Cloud Function and OpenAI, then discarded. Notchman stores only per-user monthly counters, and they expire automatically. Your App Store privacy answers should match `PrivacyInfo.xcprivacy`:
- **User ID** (the anonymous account), used for app functionality
- **Purchase history** (plan verification), used for app functionality

## Before submitting to the App Store

- [ ] Firebase App Check is set to **Enforce** for Cloud Functions.
- [ ] Google Cloud budget alerts and an OpenAI usage limit are set.
- [ ] The Firestore TTL policy on `quotas.expiresAt` is set.
- [ ] `APPLE_APP_ID` is set, so real App Store purchases verify.
- [ ] Review the Share Extension's direct "open app" call (`ShareViewController.openContainingApp`). It's not a documented API, and App Review may object. The notification fallback already covers the flow if you remove it.
