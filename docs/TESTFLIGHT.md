# Put Notchman on your iPhone with TestFlight (no Mac needed)

GitHub's Macs build the app and send it to Apple's **TestFlight** app. You then install it on your iPhone and use it for real: share a LinkedIn post to it, double-tap the back of your phone on a WhatsApp chat, and so on. You can do everything below from a Windows PC in the browser.

**What you need:** an **Apple Developer Program** membership. It costs $99 a year, charged in rupees in India, and needs a card. Apple doesn't allow installing your own app on an iPhone any other way without a Mac.

---

## 1. Join the Apple Developer Program (once)

1. Go to [developer.apple.com/programs/enroll](https://developer.apple.com/programs/enroll) and sign in with your Apple ID. Two-factor authentication must be on.
2. Enroll as an **Individual** and pay. Approval usually takes 1–2 days.
3. When you're approved, go to [developer.apple.com/account](https://developer.apple.com/account) → **Membership details** and copy your **Team ID** (10 characters).

## 2. Register the app's ID (once)

Notchman's ID is `app.notchman`, which is the notchman.app domain reversed. The App Group is `group.app.notchman`. These are the defaults in the code.

In [developer.apple.com/account](https://developer.apple.com/account) → **Certificates, IDs & Profiles** → **Identifiers**:

1. Click **+**, choose **App Groups**, and set the Identifier to `group.app.notchman`.
2. Click **+** again, choose **App IDs** → **App**:
   - **Bundle ID:** Explicit, `app.notchman`
   - **Capabilities:** tick **App Groups** (then Configure and choose the group from step 1), **Sign in with Apple** and **App Attest**.

You don't need to register the Share, Safari and Dynamic Island extensions; the build registers them itself.

### Register your iPhone (once)

Apple won't sign an app for a team that has no devices, so register your iPhone:

1. Find its **UDID**:
   - **Windows:** install **Apple Devices** from the Microsoft Store (or iTunes) and plug in the iPhone. Click the iPhone, then click the **Serial Number** until it changes to **UDID**. Right-click it to copy.
   - **Mac:** Finder → the iPhone in the sidebar → click the text under its name until it shows the UDID.
2. In [developer.apple.com/account](https://developer.apple.com/account) → **Certificates, IDs & Profiles** → **Devices**, click **+**. Choose platform **iOS**, name it `My iPhone`, paste the UDID, then **Continue** → **Register**.

## 3. Create the app in App Store Connect (once)

At [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → **Apps** → **+** → **New App**:
- **Platform:** iOS
- **Name:** Notchman. If that's taken, try something like "Notchman: TL;DR Listener".
- **Bundle ID:** the one from step 2
- **SKU:** anything, for example `notchman1`

## 4. Create an API key for GitHub (once)

At App Store Connect → **Users and Access** → **Integrations** → **App Store Connect API** → **Team Keys**:
1. Click **Generate API Key**. Give it any name, and choose **Admin** access, which lets it create signing certificates.
2. **Download** the `.p8` file. You can only download it once, so keep it safe.
3. Note the **Key ID** (next to the key) and the **Issuer ID** (at the top of the page).

## 5. Give GitHub the secrets (once)

On GitHub, open the repo → **Settings** → **Secrets and variables** → **Actions**.

On the **Secrets** tab, click **New repository secret** for each of these:

| Name | Value |
|---|---|
| `APPLE_TEAM_ID` | Team ID from step 1 |
| `ASC_KEY_ID` | Key ID from step 4 |
| `ASC_ISSUER_ID` | Issuer ID from step 4 |
| `ASC_KEY_P8` | Open the `.p8` file in Notepad and paste **everything**, including the BEGIN and END lines |

Using different IDs? Add repository **Variables** `APP_BUNDLE_ID` and `APP_GROUP_ID` with your values. With `app.notchman` you don't need them.

GitHub keeps secrets encrypted, and nobody can read them back, including you.

## 6. Build and upload

1. Go to the repo → **Actions** → **TestFlight** → **Run workflow**.
2. Choose the branch `claude/optimistic-thompson-c0u9ac` → **Run**.
3. Wait about 15 minutes for a green tick. Apple then processes the build for another 5–20 minutes.

If it goes red, open the run: the summary shows the error. Send it to Claude.

Run it again whenever you want a new build; each run gets a new build number.

## 7. Install it on your iPhone

1. In App Store Connect → your app → **TestFlight** → **Internal Testing**, click **+**, create a group, and add yourself. No Apple review is needed for this.
2. On your iPhone, install **TestFlight** from the App Store. Open the invite email, or open TestFlight directly, and tap **Install** next to Notchman.

### Want a QR code (for friends or testers)?

1. In **TestFlight** → **External Testing**, click **+** to create a group and add the build.
2. Apple reviews the first build, usually within a day.
3. Then click **Enable Public Link**. Paste that link into any QR code generator, or ask Claude to make the QR. Anyone who scans it with their iPhone camera gets Notchman through TestFlight, for up to 10,000 testers.

---

## 8. Try it on real apps

- **LinkedIn, Mail, ChatGPT and others:**
  1. Tap **Share** → **More** → turn on **Listen with Notchman** (first time only).
  2. From then on, Share → Listen with Notchman.
- **Any screen (Back Tap):**
  1. In the **Shortcuts** app, make a shortcut with two actions: **Take Screenshot**, then **TL;DR My Screen** (under Notchman).
  2. Go to Settings → Accessibility → Touch → **Back Tap** → Double Tap, and choose that shortcut.
  3. Now double-tap the back of your phone on any long message. Glass borders appear, and the TL;DR plays in the Dynamic Island.
- **Safari (chatgpt.com, claude.ai, reddit.com):**
  1. Settings → Apps → Safari → Extensions → **Notchman** → on, and allow it on those sites.
  2. A 🎧 button appears under long messages.

## What this build does and doesn't include

TestFlight builds are the **free, on-device version**:
- TL;DRs are made by Apple Intelligence on iPhone 15 Pro and newer, and by the built-in summarizer on older phones.
- They're read by Apple's voice, with 10 TL;DRs a month.

**Groq summaries and the ElevenLabs voice** need the Notchman server on AWS (see server/README.md). Once `NOTCHMAN_API_URL` and the Firebase plist are in GitHub, TestFlight builds use them automatically.
