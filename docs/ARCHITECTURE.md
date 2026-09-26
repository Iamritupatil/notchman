# Notchman architecture

## Data flow

```
 Share sheet ──► ShareExtension ─┐
 Safari 🎧 / popup ─► SafariWebExtensionHandler ─┤  ContentExtractionPipeline  ──►  SharedInbox (App Group JSON)
                                                 │   (Safari / Text / URL)               │
 Shortcuts intent ───────────────────────────────┘                                        ▼
 Developer screen ─────────────────────────────────────────────────────────────► AppEnvironment.ingest
                                                                                          │
                                         TextCleaner ◄── HistoryStore.addItem (SwiftData ListeningItem)
                                                                                          │
                                              ┌───────────── PlaybackManager ◄────────────┘
                                              │   ▲ state (@Observable) → SwiftUI
                                              ▼   │
                                        SpeechService (AVSpeechSynthesizer)
                                              │
               LiveActivityManager ◄──────────┼──────────► NowPlayingController (Lock Screen, AirPods)
               (Dynamic Island)               │
                                   AudioSessionController (interruptions, route changes)
```

## Key decisions

**Only the app writes to SwiftData.** Extensions write `PendingListen` JSON files to the App Group, and the app drains them on activation or when a `notchman://listen?id=` URL arrives. That avoids having several processes write to one store, and keeps extensions small and within their memory limits.

**Progress is tracked in characters, and time is derived from it.** `AVSpeechSynthesizer` reports character ranges, not time. `PlaybackManager` stores a characters-per-second estimate for the current speed. It starts from a value persisted from earlier sessions and blends in the observed rate every few seconds while playing. Elapsed time, remaining time, ±15 s skips, Now Playing info and the Live Activity timeline all use this one rate.

**Text is spoken as short utterances.** `SpeechSegmenter` splits cleaned text into paragraphs and list items, and packs sentences into chunks of 400 characters or fewer. This gives three things:
- natural pauses between blocks (`postUtteranceDelay`)
- fast re-queueing when seeking or changing speed, which restarts at the start of the current word
- bounded work per utterance

Callbacks from cancelled utterances are ignored by tracking only the current batch.

**The Live Activity is updated on events, not on a timer.** The content state carries `elapsed`, `duration`, `isPlaying` and `updatedAt`. The widget turns these into a timeline (`timelineStart...timelineEnd`) for `Text(timerInterval:)` and `ProgressView(timerInterval:)`, so the clock moves on its own. The app only pushes updates on play, pause, seek, speed change, finish, and the occasional calibration drift. That stays well within ActivityKit's update budget.

**Controls outside the app go through one command path.** The Live Activity buttons are `LiveActivityIntent`s, which iOS runs in the app process. Their `perform()` forwards to `PlaybackCommandCenter`, and `PlaybackManager` installs itself as the handler. Remote commands (Lock Screen, AirPods) use `MPRemoteCommandCenter` and map to the same methods.

**Extraction is pluggable.**
- `ContentExtractor` has `canHandle` / `extract` implementations. To add an integration, write an extractor and register it in `ContentExtractionPipeline.standard`.
- Page-level extraction runs in JavaScript: `extractors.js` defines `ChatGPTExtractor`, `ClaudeExtractor`, `RedditExtractor` and `GenericArticleExtractor`. The Safari content script, the Safari popup and the Share Extension's preprocessing file all use it. `scripts/build-js.mjs` generates the preprocessing file, and CI fails if the generated file is stale.
- The JS extractors output light markdown. `TextCleaner` then handles every source the same way.

**Quick Listen works without AI.** `QuickListenService` picks a `SummarizationProvider` from settings:
- The Basic provider (`MockSummarizationProvider`) is a real extractive summarizer. It scores sentences for numbers, decisions, warnings and position, and needs no network access.
- LLM providers share `SummarizationPrompt`, which asks for audio-first scripts.
- The summarizer's output goes through `TextCleaner` too.

## Share Extension → app hand-off

iOS gives share extensions no public API to open their containing app. `ShareViewController.openContainingApp` calls `UIApplication.open(_:options:completionHandler:)` through the responder chain, dynamically. This works on current iOS but is not documented by Apple.

When that call reports failure, `ShareViewModel` switches to the supported path:
- the item stays in the inbox
- a local notification ("Ready to listen · Tap to start") is posted, if the user allowed notifications during onboarding
- the extension shows "Saved to Notchman"
- the next time the app becomes active, it plays the item

If App Review objects to the direct open, delete `openContainingApp`. The fallback already covers the flow.

## Adding a new site to the Safari extension

1. Add an extractor object to `extractors.js`, with `matches(host)`, `blocks(doc)` returning `[{ element, anchor, text }]`, and `isStreaming(el, doc)`. Append it to `SITE_EXTRACTORS`.
2. Add the host to `content_scripts.matches` in `manifest.json`.
3. Map the site name in `SafariMessageExtractor.sourceType(site:url:)` and `SourceDetector`.
4. Add a jsdom test in `tests/js/extractors.test.mjs`, then run `npm test`. That also regenerates-checks the Share preprocessing file.
