# Test Notchman with your own API keys

There are three parts:
- **Part A:** check your keys on your computer (about 5 minutes).
- **Part B:** put them on the server (once).
- **Part C:** run the app on your iPhone.

> **Where keys go:** only into the hidden prompt in Part A or into AWS Parameter Store in Part B.
> Never paste a key into the app, a code file, GitHub, email or a chat.

---

## Part A: check your keys (any computer)

1. Create the keys:
   - **Groq:** [console.groq.com](https://console.groq.com) → API Keys → Create API Key.
   - **ElevenLabs:** [elevenlabs.io](https://elevenlabs.io) → Developers → API Keys → Create. Give it access to **Text to Speech** only, and set a monthly character limit (for example 50,000 while testing).
2. Install [Node.js 22](https://nodejs.org).
3. In a terminal:
   ```bash
   git clone https://github.com/Iamritupatil/notchman.git
   cd notchman
   git checkout claude/optimistic-thompson-c0u9ac
   cd server
   npm install
   npm run try
   ```
4. Paste each key when asked. Nothing shows while you paste, and nothing is saved.

You'll see the TL;DR text. `tldr-test.mp3` (in `server`) is the ElevenLabs voice, so open it to listen.

**To try your own message,** for example a Hindi chat or a long ChatGPT answer, save it as a text file and run:
```bash
npm run try -- ~/Desktop/message.txt
```

**Optional:** to try another voice or model, set these before `npm run try`:
- `ELEVENLABS_VOICE_ID=<id from the Voice Library>`
- `ELEVENLABS_MODEL=eleven_multilingual_v2` (a higher-quality voice that costs about twice as much)
- `GROQ_MODEL=openai/gpt-oss-20b`

---

## Part B: put the keys on the server (AWS, once)

Follow **[server/README.md](../server/README.md)**. In short:
1. Store both keys in AWS Parameter Store.
2. Run `npm run deploy:first` in `server/`.
3. Put the printed **ApiUrl** in `project.yml` as `NOTCHMAN_API_URL`.

---

## Part C: run the app on your iPhone (needs a Mac)

**No Mac? Use [TESTFLIGHT.md](TESTFLIGHT.md)** to build on GitHub and install through TestFlight.

Parts A and B work on Windows. Part C doesn't, because Apple only lets iPhone apps be built with Xcode on a Mac. Without a Mac, use a borrowed or rented cloud Mac, or TestFlight built by GitHub Actions (needs the Apple Developer account).

Test builds, meaning anything run from Xcode, have Pro/Pro+ and the cloud switched on. App Store builds stay free and on-device until you turn them on in `FeatureFlags.swift`.

3. **Open the project on the Mac**, using Xcode 16 or newer:
   ```bash
   brew install xcodegen
   cd notchman
   xcodegen generate
   open Notchman.xcodeproj
   ```
4. **Set your team.** In Xcode, select the Notchman target → Signing & Capabilities → Team (your Apple Developer account).
   - Do the same for the NotchmanShare, NotchmanWidgets and NotchmanSafari targets.
   - If Xcode says `app.notchman` is taken, change `APP_BUNDLE_ID` and `APP_GROUP_ID` in `project.yml`, run `xcodegen generate` again, and add `APPLE_BUNDLE_ID=<your id>` to `server/.env`.
5. **Run it.** Plug in your iPhone, pick it at the top of Xcode and press ▶. On the iPhone, allow Developer Mode if asked.
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
| A TL;DR in Apple's voice, not ElevenLabs | The server's voice step failed | In AWS CloudWatch, open the Lambda's logs and look for `voice failed`. It's usually the ElevenLabs key or its character limit. |
| A plain summary that starts "Okay, here's the quick version" | The cloud wasn't used | Open Settings, tap Version 7 times, then Check Cloud to see which step fails. |
| "Out of TL;DRs" right away | The server thinks you're on Free | Make sure `ALLOW_XCODE_TRANSACTIONS=true` is in `.env`, then run `npm run deploy` again. |
| Xcode signing errors | Team or bundle ID | See step 4. |

---

## Before launch

- [ ] Remove `ALLOW_XCODE_TRANSACTIONS` from `server/.env` and deploy. Test purchases can be faked, so they must never count in production.
- [ ] Set `APPLE_APP_ID` in `.env` so real App Store purchases verify.
- [ ] Create the Pro and Pro+ subscriptions in App Store Connect with the IDs in `PremiumStore.swift`.
- [ ] Set `paidPlans` and `cloudTLDR` to `true` for Release in `Notchman/Core/Shared/FeatureFlags.swift`.
- [ ] Go through the checklist in [SECURITY.md](SECURITY.md).
