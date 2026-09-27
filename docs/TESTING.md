# Test Notchman with your own API keys

There are three parts:
- **Part A:** check your keys on your computer (about 5 minutes).
- **Part B:** put them on the server (once).
- **Part C:** run the app on your iPhone.

> **Where keys go:** only into the hidden prompt in Part A or into Firebase Secret Manager in Part B.
> Never paste a key into the app, a code file, GitHub, email or a chat.

---

## Part A: check your keys (any computer, no Firebase)

1. Create the keys:
   - **Groq:** [console.groq.com](https://console.groq.com) → API Keys → Create API Key.
   - **ElevenLabs:** [elevenlabs.io](https://elevenlabs.io) → Developers → API Keys → Create. Give it access to **Text to Speech** only, and set a monthly character limit (for example 50,000 while testing).
2. Install [Node.js 22](https://nodejs.org).
3. In a terminal:
   ```bash
   git clone https://github.com/Iamritupatil/notchman.git
   cd notchman
   git checkout claude/optimistic-thompson-c0u9ac
   cd firebase/functions
   npm install
   npm run try
   ```
4. Paste each key when asked. Nothing shows while you paste, and nothing is saved.

You'll see the TL;DR text. `tldr-test.mp3` (in `firebase/functions`) is the ElevenLabs voice, so open it to listen.

**To try your own message,** for example a Hindi chat or a long ChatGPT answer, save it as a text file and run:
```bash
npm run try -- ~/Desktop/message.txt
```

**Optional:** to try another voice or model, set these before `npm run try`:
- `ELEVENLABS_VOICE_ID=<id from the Voice Library>`
- `ELEVENLABS_MODEL=eleven_multilingual_v2` (a higher-quality voice that costs about twice as much)
- `GROQ_MODEL=openai/gpt-oss-20b`

---

## Part B: put the keys on the server (Firebase, once)

1. **Create the Firebase project** at [console.firebase.google.com](https://console.firebase.google.com).
2. **Switch to the Blaze plan.** Cloud Functions need it, and the free allowance still applies.
   - In Google Cloud → Billing → Budgets, add a budget alert, for example ₹1,000 a month.
3. **Anonymous sign-in:** Authentication → Sign-in method → **Anonymous** → Enable.
4. **Firestore:**
   - Firestore Database → Create database (production mode).
   - Then Firestore → TTL → add a policy for collection group `quotas`, field `expiresAt`.
5. **Install the Firebase tool, sign in and pick your project.** Run these from the `firebase` folder inside `notchman`, not the main folder:
   ```bash
   npm install -g firebase-tools
   firebase login
   cd notchman/firebase
   firebase use --add
   ```
   Choose your project from the list, and type `default` when it asks for an alias.
6. **Store the keys in Secret Manager.** Each command asks you to paste the key:
   ```bash
   firebase functions:secrets:set GROQ_API_KEY
   firebase functions:secrets:set ELEVENLABS_API_KEY
   ```
7. **Allow test purchases while testing.** Create `firebase/functions/.env` containing:
   ```
   ALLOW_XCODE_TRANSACTIONS=true
   ```
   On Windows PowerShell, from the `firebase` folder: `Set-Content functions\.env "ALLOW_XCODE_TRANSACTIONS=true"`
   This lets free Xcode test purchases count as Pro. **Delete this line before launch** (see the end of this guide).
8. **Deploy:**
   ```bash
   cd functions
   npm run deploy
   ```

---

## Part C: run the app on your iPhone (needs a Mac)

Parts A and B work on Windows. Part C doesn't, because Apple only lets iPhone apps be built with Xcode on a Mac. Without a Mac, use a borrowed or rented cloud Mac, or TestFlight built by GitHub Actions (needs the Apple Developer account).

Test builds, meaning anything run from Xcode, have Pro/Pro+ and the cloud switched on. App Store builds stay free and on-device until you turn them on in `FeatureFlags.swift`.

1. **Register the app in Firebase.**
   - Project settings → Add app → iOS, with bundle ID `com.notchman.app`.
   - Download **GoogleService-Info.plist** into `Notchman/Resources/`.
2. **Register App Attest:** App Check → Apps → Notchman → **App Attest** → Save.
3. **Open the project on the Mac**, using Xcode 16 or newer:
   ```bash
   brew install xcodegen
   cd notchman
   xcodegen generate
   open Notchman.xcodeproj
   ```
4. **Set your team.** In Xcode, select the Notchman target → Signing & Capabilities → Team (your Apple Developer account).
   - Do the same for the NotchmanShare, NotchmanWidgets and NotchmanSafari targets.
   - If Xcode says `com.notchman.app` is taken, change `APP_BUNDLE_ID` and `APP_GROUP_ID` in `project.yml`, run `xcodegen generate` again, and add `APPLE_BUNDLE_ID=<your id>` to `firebase/functions/.env`.
5. **Run it.** Plug in your iPhone, pick it at the top of Xcode and press ▶. On the iPhone, allow Developer Mode if asked.
6. **Register the test token (once).**
   - In Xcode's console at the bottom, find `Firebase App Check debug token: XXXXXXXX-…`.
   - Firebase console → App Check → Apps → Notchman → ⋮ → **Manage debug tokens** → Add, and paste it.
   - Without this, cloud TL;DRs are refused and the app quietly makes them on the phone instead.
7. **Buy Pro for free.** In the app, go to Account → Go Premium → Pro. This is a test purchase: it's free and only works in Xcode builds.
8. **Try a TL;DR:**
   - **Quickest:** Home → **Try Notchman** → paste a long message → **TL;DR**. You should hear the ElevenLabs voice.
   - **Real flow:** in ChatGPT or WhatsApp, take a screenshot → Share → **Listen with Notchman** → glass borders → TL;DR.
   - Settings → TL;DR should show *39 of 40 left*.
9. **Try the Free plan.**
   - In Xcode: Debug → StoreKit → Manage Transactions → delete the purchase.
   - TL;DRs are now made on the iPhone with Apple's voice, 10 a month.

### If something's off

| What you see | Why | Fix |
|---|---|---|
| A TL;DR in Apple's voice, not ElevenLabs | The server's voice step failed | Run `firebase functions:log` and look for `voice failed`. It's usually the ElevenLabs key or its character limit. |
| A plain summary that starts "Okay, here's the quick version" | The cloud wasn't used | Check that `GoogleService-Info.plist` is in `Notchman/Resources`, that the debug token is registered (step 6), and that you bought Pro (step 7). |
| "Out of TL;DRs" right away | The server thinks you're on Free | Make sure `ALLOW_XCODE_TRANSACTIONS=true` is in `.env`, then run `npm run deploy` again. |
| Xcode signing errors | Team or bundle ID | See step 4. |

---

## Before launch

- [ ] Remove `ALLOW_XCODE_TRANSACTIONS` from `firebase/functions/.env` and deploy. Test purchases can be faked, so they must never count in production.
- [ ] Set `APPLE_APP_ID` in `.env` so real App Store purchases verify.
- [ ] Create the Pro and Pro+ subscriptions in App Store Connect with the IDs in `PremiumStore.swift`.
- [ ] Set `paidPlans` and `cloudTLDR` to `true` for Release in `Notchman/Core/Shared/FeatureFlags.swift`.
- [ ] Go through the checklist in [SECURITY.md](SECURITY.md).
