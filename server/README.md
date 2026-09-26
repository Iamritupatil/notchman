# Notchman server

Makes TL;DRs for the app. It holds the AI keys (the app never does), and it counts each plan's monthly allowance.

| Plan | TL;DRs / month |
|---|---|
| Free | 10 |
| Pro | 100 |
| Pro+ | 250 |

```
POST /api/tldr   { installId, text, length?, transactions? } → { summary, plan, used, limit, remaining }
POST /api/usage  { installId, transactions? }                → { plan, used, limit, remaining }
```

- `installId` is an anonymous UUID the app keeps in the Keychain. It's used to count Free-plan TL;DRs.
- `transactions` are the app's signed StoreKit transactions. The server verifies Apple's signature to find out the plan, so a forged receipt just means Free.
- Paid plans are counted per subscription, so reinstalling the app doesn't reset the count.
- If the summary fails, the TL;DR isn't counted.
- Messages are never stored. Only the monthly counters are.

## Deploy (Vercel)

1. In Vercel, click **Add New → Project** and import this repo. Set **Root Directory** to `server`.
2. Go to **Storage → Marketplace → Upstash for Redis** and connect it to the project. That adds the Redis environment variables automatically.
3. Under **Settings → Environment Variables**, add:

   | Variable | Value |
   |---|---|
   | `OPENAI_API_KEY` | Your OpenAI key. **Only ever set it here**, never in the app or the repo. |
   | `OPENAI_MODEL` | Optional. Defaults to `gpt-5.4-nano`. |
   | `APPLE_BUNDLE_ID` | `com.notchman.app`, or your bundle ID |
   | `APPLE_APP_ID` | Your app's numeric Apple ID from App Store Connect. Needed to accept real App Store purchases. |
   | `FREE_DAILY_GLOBAL_CAP` | Optional. The most Free TL;DRs per day across all users, as a spend safety net. Defaults to 5000. |
   | `ALLOW_XCODE_TRANSACTIONS` | `true` only on a development deployment, so purchases made through Xcode's StoreKit testing count |

4. Deploy, then put the URL in `project.yml`:

   ```yaml
   NOTCHMAN_API_BASE_URL: "https://your-project.vercel.app"
   ```

   and run `xcodegen generate`.

## Develop

```bash
cd server
npm install
npm test          # vitest
npm run typecheck
```

## Before launch

Add **App Attest** (DeviceCheck) so only the genuine Notchman app can call the API. Until then, the Free plan's daily global cap limits what anyone scripting fake installs could cost.
