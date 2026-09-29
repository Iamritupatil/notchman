# Notchman

**Read less. Listen instead.**

Notchman is a native iOS utility that turns long messages (ChatGPT and Claude answers, Reddit threads, emails, forum posts, articles) into natural spoken audio. You see a long message, tap **Share → Listen with Notchman**, and it starts reading. You can leave the app and it keeps going, with controls in the Dynamic Island and on the Lock Screen.

Swift · SwiftUI · AVSpeechSynthesizer · SwiftData · ActivityKit · App Intents · Share Extension · Safari Web Extension. It has no third-party dependencies.

## Cost

Notchman launches **free, with no running costs**. TL;DRs are made on the iPhone: Apple Intelligence on supported devices, the built-in summarizer elsewhere. Voices are Apple's, and screenshot reading uses Apple's on-device Vision. There's no server, API key or credit card. The only cost is the $99/year Apple Developer account.

The cloud TL;DR server (Groq + ElevenLabs on AWS Lambda) is in `server/`. It's switched on for TestFlight testers; see [server/README.md](server/README.md).

## Design

Notchman is dark-first, with a pixel-art Shiba mascot, amber accents and [Silkscreen](https://fonts.google.com/specimen/Silkscreen) pixel type (SIL Open Font License, bundled in `Notchman/Resources/Fonts`).

The mascot and app icon come from the artwork in `design/art/`; `python3 scripts/import_art.py` turns it into app, extension and Safari assets.

The app has three tabs:
- **Home:** hero and recent listens.
- **History:** Today / Yesterday / Earlier, TL;DR badges, and Go Premium.
- **Account:** Sign in with Apple, Premium and settings.

The player is a full-screen sheet.

"TL;DR" is what the code calls Quick Listen (`SummarizationProvider`).

---

## Getting started

Requirements: Xcode 16 or later, and iOS 17 or later (for SwiftData, interactive Live Activities and `@Observable`).

```bash
brew install xcodegen
xcodegen generate
open Notchman.xcodeproj
```

**To test with your own Groq and ElevenLabs keys, follow [docs/TESTING.md](docs/TESTING.md).**

The Xcode project is generated from [`project.yml`](project.yml) and isn't committed. Before running on a device:

1. Set your team, either in Xcode or with `DEVELOPMENT_TEAM` in `project.yml`.
2. The app ID is `app.notchman` (the notchman.app domain reversed). To use another, change `APP_BUNDLE_ID` and `APP_GROUP_ID` in `project.yml`. Everything else reads them from there.
3. Run the **Notchman** scheme on an iPhone. The Dynamic Island needs a device or an iPhone 15/16/17 Pro simulator.

To use the Safari extension, turn it on under **Settings → Apps → Safari → Extensions → Notchman** and allow it on chatgpt.com, claude.ai and reddit.com.

### Tests

```bash
# Swift unit tests: TextCleaner, segmenter, extractors, Quick Listen, estimates
xcodebuild test -project Notchman.xcodeproj -scheme Notchman \
  -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO

# Safari/Share extension extractors (jsdom)
npm install && npm test
```

CI (`.github/workflows/ci.yml`) runs both on every push: a macOS job that generates the project, builds every target and runs the unit tests, and a Node job for the extractors.

---

## How content gets in

A normal iOS app can't read other apps' screens, and Notchman doesn't pretend to. Every entry point is a supported iOS mechanism:

| Entry point | How it works |
|---|---|
| **Share → Listen with Notchman** | Share Extension. It accepts plain text, URLs and Safari pages. In Safari, a JavaScript preprocessing step reads your selection, or the ChatGPT/Claude message you're looking at, or the article text, instead of just the URL. |
| **🎧 Listen button in Safari** | Safari Web Extension on chatgpt.com, claude.ai and reddit.com. It adds a small button under messages longer than ~250 characters and sends only that message. |
| **Safari toolbar → Listen to this page** | Extension popup. It reads the current page's selection, messages or article. |
| **Shortcuts / Siri / Action button** | App Intent **Listen with Notchman**, which takes text or a link. |
| **Links** | Shared URLs are fetched and cleaned with a built-in reader mode. Reddit uses its JSON API. |

### "Tap and TL;DR" (iPhone)

iOS doesn't let apps read other apps' screens, draw over them, or respond to taps on the notch or Dynamic Island. The iPhone version of the flow works like this instead:

1. The user double-taps the back of the phone (Back Tap) or presses the Action button. This runs a shortcut made of two actions: **Take Screenshot**, then **TL;DR My Screen**.
2. Notchman opens with the screenshot. On-device Vision OCR (`ScreenTextReader`) and layout grouping (`MessageBlockDetector`) find the messages.
3. Glass borders appear around each message. The user taps one within 3 seconds, or Notchman picks the longest one (`MessagePickerView`).
4. The TL;DR plays, and the Dynamic Island shows playback.

Sharing a screenshot to Notchman from the Share sheet starts the same picker. On Mac, where apps can capture the screen (with permission) and draw overlays, the plan is the real notch flow.

### Handing off from an extension to the app

Extensions put what they extracted into a file queue in the App Group (`SharedInbox`). The app is the only thing that writes to SwiftData.

- **Safari extension:** after queueing, the page opens `notchman://listen?id=…`. Safari asks "Open in Notchman?", which is the supported path.
- **Share Extension:** iOS has no public API for a share extension to open its app. Notchman tries a responder-chain call to `UIApplication.open`. It's widely used and works on current iOS, but Apple doesn't document it (see `ShareViewController.openContainingApp`). If that call fails, the Share Extension uses the supported fallback: the item stays queued, a local notification offers **Tap to listen**, and the app picks it up whenever it next becomes active.

---

## Architecture

```
Notchman/
  App/                 Entry point, AppEnvironment (composition root + ingest flow), router, App Intents
  Core/
    Audio/             SpeechService, PlaybackManager, SpeechSegmenter, VoiceCatalog,
                       AudioSessionController, NowPlayingController
    Extraction/        ContentExtractor protocol + SharedText, URL, SafariMessage,
                       GenericWeb and Reddit extractors
    Text/              TextCleaner, ReadingEstimator, RegexKit
    Storage/           HistoryStore (SwiftData), SharedInbox (App Group), AppSettings, KeychainStore
    Summarization/     SummarizationProvider: Notchman server (cloud), Apple Intelligence and Basic (on-device fallbacks)
    Cloud/             The Notchman API client (install ID, TL;DR, voice) and Check Cloud
    LiveActivity/      ActivityAttributes + LiveActivityManager
    Intents/           Live Activity control intents (shared with the widget)
    Shared/            AppGroup, DeepLink
  Models/              ListeningItem (@Model), SourceType
  Features/            Onboarding, Home, Player, History, Settings, Ingest, Developer
  DesignSystem/        Theme, buttons, SourceBadge, WaveformView, NotchmanMark
Extensions/
  ShareExtension/      "Listen with Notchman" + generated Preprocessing.js
  SafariExtension/     Native handler + Resources (manifest, extractors.js, content script, popup)
  LiveActivityWidget/  Dynamic Island + Lock Screen UI
NotchmanTests/         XCTest unit tests
tests/js/              Extractor tests (node:test + jsdom)
```

More detail is in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

**Playback.** `PlaybackManager` is a single `@Observable` object injected at the root, so playback survives navigation, sheets and backgrounding. It drives `SpeechService`, which queues short utterances (one per paragraph or list item) and reports progress as character offsets. Seeking and speed changes re-queue from the current word. Elapsed and remaining time come from a characters-per-second rate that is recalibrated from real speech while playing, which keeps the timers, ±15 s skips and the Live Activity honest.

**Background audio.** The app sets `UIBackgroundModes: audio` and uses an `AVAudioSession` in `.playback` / `.spokenAudio`. Interruptions (calls, Siri) pause playback and resume if iOS says to. Unplugging headphones or disconnecting AirPods pauses and does not auto-resume. Lock Screen, Control Center and AirPods controls go through `MPRemoteCommandCenter`.

**Live Activity.** The Live Activity starts on play and ends when playback finishes or stops. It's only updated on state changes: the widget uses timer-based `Text` and `ProgressView`, so time keeps moving without per-second updates. The −15 / play-pause / +15 buttons are `LiveActivityIntent`s, which iOS runs in the app's process, so they work without opening the app.

**TextCleaner.** It turns markdown, HTML and chat text into something that sounds natural:
- `## Architecture` becomes "Architecture."
- `**`, `__` and backticks are removed.
- Bullets and table rows become sentences.
- Long URLs are read as "There is a link here." Link text is read instead of the URL.
- Large code blocks are replaced with "This response contains a Python code block, which I've skipped." (configurable).
- Citations and emoji are dropped, and `->`, `~3` and `e.g.` are made speakable.

**Quick Listen.** `SummarizationProvider.summarizeForListening(_:targetDuration:)` produces audio-first scripts. TL;DR (Quick Listen) defaults to the free on-device Basic provider. The providers are:
- **Basic:** extractive and on-device. It keeps numbers, decisions and warnings.
- **Apple Intelligence:** Foundation Models, iOS 26+ on supported devices.
- **Notchman server (`server/`, AWS Lambda), Pro and Pro+ (and TestFlight testers):** Groq (`gpt-oss-120b`) writes the summary in the message's language and ElevenLabs (Multilingual v2) voices TL;DRs and full reads, piece by piece so audio starts in a second or two. The Lambda reads both keys from AWS Parameter Store and enforces per-install and total daily limits in DynamoDB. See [server/README.md](server/README.md) and [docs/SECURITY.md](docs/SECURITY.md).

If an AI provider fails with a network error, Quick Listen falls back to Basic.

---

## Acceptance test A (developer screen)

1. Open Notchman, finish onboarding, and tap **Try Notchman**.
2. Pick **ChatGPT answer (markdown + code)** or paste your own text. Expand **Preview spoken text** to see what will be read.
3. Tap **Read**. Speech starts and the player opens.
4. Pause and resume with the play button, the mini player, the Dynamic Island or the Lock Screen.
5. Change speed (0.8x–2x). Speech continues from the current word at the new rate.
6. Close the player: the item is in **Recent** with its progress. Kill and relaunch the app, tap the item, and it resumes where you left off.

Also worth checking on a device:
- Lock the screen and make sure speech continues.
- Get a call and confirm it pauses, then resumes afterwards.
- Disconnect AirPods and confirm it pauses.
- Share from Safari on chatgpt.com.
- Tap 🎧 Listen under a long Claude answer.

---

## Status

| Milestone | State |
|---|---|
| 1. Project, navigation, onboarding, home, player, history, settings | Done |
| 2. SpeechService, PlaybackManager, TextCleaner, play/pause/speed | Done |
| 3. SwiftData history, persist and resume | Done |
| 4. Background playback, interruptions, remote commands | Done. Needs on-device verification |
| 5. Share Extension | Done. Needs on-device verification |
| 6. Dynamic Island / Live Activity | Done. Needs on-device verification |
| 7. Safari extension (ChatGPT → Claude → Reddit) | Done. Site selectors will need maintenance as those sites change |
| 8. Quick Listen (TL;DR) | Done. Cloud TL;DRs via the Notchman server, with on-device fallback |

**Account and Premium.**
- **Sign in with Apple** works and is stored in the Keychain on this iPhone. There's no Notchman server, so nothing syncs yet.
- **Continue with Email** says it's coming soon.
- **Premium** uses StoreKit 2's native subscription store. Product IDs are in `PremiumStore`, and `StoreKit/Notchman.storekit` lets you test purchases in the simulator.
- Plans: Free has 10 TL;DRs a month, made on the iPhone (counted in the Keychain, so reinstalling doesn't reset it). Pro has 40 and Pro+ 100, made by the server, which enforces them. Listening to full messages is unlimited on every plan.

**Known limits.**
- Text shared from native apps, such as the ChatGPT app, doesn't say which app it came from, so it's labeled "Text" unless the content itself identifies the source.
- `AVSpeechSynthesizer` speed-to-rate mapping is tuned by ear (`PlaybackSpeed`). The time display self-calibrates.
- The app icon and mascot are the design artwork in `design/art/`, imported by `scripts/import_art.py`.
