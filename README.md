# Notchman

**Read less. Listen instead.**

Notchman is a native iOS utility that turns long messages (ChatGPT and Claude answers, Reddit threads, emails, forum posts, articles) into natural spoken audio. You see a long message, tap **Share → Listen with Notchman**, and it starts reading. You can leave the app and it keeps going, with controls in the Dynamic Island and on the Lock Screen.

Swift · SwiftUI · AVSpeechSynthesizer · SwiftData · ActivityKit · App Intents · Share Extension · Safari Web Extension. It has no third-party dependencies.

---

## Getting started

Requirements: Xcode 16 or later, and iOS 17 or later (for SwiftData, interactive Live Activities and `@Observable`).

```bash
brew install xcodegen
xcodegen generate
open Notchman.xcodeproj
```

The Xcode project is generated from [`project.yml`](project.yml) and isn't committed. Before running on a device:

1. Set your team, either in Xcode or with `DEVELOPMENT_TEAM` in `project.yml`.
2. If `com.notchman.app` is taken, change `APP_BUNDLE_ID` and `APP_GROUP_ID` in `project.yml`. Everything else reads them from there.
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
    Summarization/     SummarizationProvider + Mock (on-device), Apple Intelligence, OpenAI
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

**Quick Listen.** `SummarizationProvider.summarizeForListening(_:targetDuration:)` produces audio-first scripts. Quick Listen is off by default. The providers are:
- **Basic:** extractive and on-device. It keeps numbers, decisions and warnings.
- **Apple Intelligence:** Foundation Models, iOS 26+ on supported devices.
- **OpenAI:** uses the user's own key, stored in the Keychain. No key is ever hard-coded.

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
| 8. Quick Listen architecture | Done. Basic, Apple Intelligence and OpenAI providers |

**Known limits.**
- Text shared from native apps, such as the ChatGPT app, doesn't say which app it came from, so it's labeled "Text" unless the content itself identifies the source.
- `AVSpeechSynthesizer` speed-to-rate mapping is tuned by ear (`PlaybackSpeed`). The time display self-calibrates.
- The app icon is a placeholder, generated by `scripts/generate_icons.py`.
