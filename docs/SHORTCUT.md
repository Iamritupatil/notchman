# The one-press shortcut

iOS doesn't let apps capture another app's screen, so "one press" runs a tiny
shortcut: **Take Screenshot → TL;DR My Screen**. Notchman then shows the screen
with glass borders, picks the main message after 3 seconds, and plays its TL;DR.

To make it a one-tap install for everyone:

1. On an iPhone with Notchman installed, open **Shortcuts** → **+**.
2. Add **Take Screenshot**, then **TL;DR My Screen** (under Notchman). Name the
   shortcut **TL;DR My Screen**.
3. Long-press the shortcut → **Share** → **Copy iCloud Link**.
4. Put that link in `project.yml` as `NOTCHMAN_SHORTCUT_URL` (or send it to
   Claude) and run a new build.

From then on, Home → **Add the Shortcut** opens Shortcuts with it ready to add.
Users then choose it in Settings → Action Button (or Back Tap), because iOS
doesn't let apps assign those themselves.

On iOS 26 iPhones with Apple Intelligence, no shortcut is needed: take a
screenshot, open Visual Intelligence, highlight the message and choose
**TL;DR with Notchman**.
