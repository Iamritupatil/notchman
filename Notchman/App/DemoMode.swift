#if DEBUG
import AVFoundation
import Foundation

/// Debug-only launch arguments for screenshots and UI review:
///
///     -demoScreen home|history|settings|player|keyPoints|fullread|generating|account|signIn|paywall
///                 onboarding|onboardingIsland|onboardingPaste|onboardingTry
///     -demoAudience study|work|focus|ai|shiba   (optional: whose sample texts to show)
///
/// Seeds sample history and opens the requested screen. Never compiled into
/// release builds. Each audience's samples become its App Store page's
/// screenshots (scripts/store_screenshots.py).
@MainActor
enum DemoMode {
    static var screen: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-demoScreen"), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    /// Sample texts for one kind of person: what they'd actually listen to.
    struct Audience {
        /// (source type, source name, text, days ago, is a TL;DR)
        let samples: [(SourceType, String, String, Int, Bool)]
        let keyPoints: [String]
        /// The link being read on the "generating" screen: (source name, title).
        let generating: (String, String)
    }

    static var audience: Audience {
        let args = ProcessInfo.processInfo.arguments
        let name = args.firstIndex(of: "-demoAudience").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
        return audiences[name ?? ""] ?? standard
    }

    // Generic sources only: these screens become App Store screenshots, which
    // can't show other companies' names or logos.
    private static let standard = Audience(
        samples: [
            (.webpage, "Web", "Here's how the architecture would work. So the three key takeaways are speed, cost, and reliability. First, speed matters because users leave slow apps.", 0, true),
            (.text, "Copied text", "So the plan for Saturday is brunch at eleven, then the park if the weather holds.", 0, true),
            (.webpage, "Web", "I've been building this for eighteen months and here is everything I learned about shipping.", -1, false),
            (.email, "Email", "Following up on the proposal we discussed last week, with the updated numbers attached.", -1, true),
        ],
        keyPoints: [
            "Three priorities: speed, cost and reliability",
            "Users leave apps that take more than 3 seconds to load",
            "A cache in front of the database cuts load time by 60%",
            "Hosting stays under $40 a month up to 10,000 users",
            "Retries and a status page cover most outages",
        ],
        generating: ("Web", "Post by Aayan Agarwal"))

    private static let audiences: [String: Audience] = [
        "study": Audience(
            samples: [
                (.webpage, "Research paper", "Practice tests beat re-reading.\nIn a 12-week study of 412 students at three universities, practising recall raised final exam scores from 66.1% to 74.3%, and six months later the gap grew to 13.8 points.", 0, true),
                (.text, "Lecture notes", "Cell respiration, chapter 7.\nGlycolysis happens in the cytoplasm and makes two ATP; the Krebs cycle runs in the mitochondria.", 0, true),
                (.webpage, "Reading", "The French Revolution, part two:\nfrom the storming of the Bastille in 1789 to the Reign of Terror.", -1, false),
                (.email, "Email", "Assignment 3 is due Friday at 5 pm.\nSubmit one PDF, and cite at least four sources.", -1, true),
            ],
            keyPoints: [
                "412 students at 3 universities, over a 12-week term",
                "Final exam: 74.3% with retrieval practice vs 66.1% re-reading",
                "Six months later the gap grew to 13.8 points",
                "It took only about 18 extra minutes a week",
                "Weaker students gained the most: 12.9 points vs 4.1",
            ],
            generating: ("Research paper", "Retrieval practice · 10 pages")),
        "work": Audience(
            samples: [
                (.email, "Email", "Q3 launch plan:\nwhat changes. The launch moves from October 14 to October 28, the budget goes up 12% to $48,000, and Priya now owns the beta.", 0, true),
                (.text, "Copied text", "Notes from the client call:\nthey renew at $24,000 a year if onboarding takes under two weeks.", 0, true),
                (.webpage, "Web", "The quarterly report:\nrevenue grew 18% while costs stayed flat, led by the new enterprise plan.", -1, false),
                (.email, "Email", "Following up on the proposal we discussed last week, with the updated numbers attached.", -1, true),
            ],
            keyPoints: [
                "Launch moves from Oct 14 to Oct 28",
                "Budget goes up 12% to $48,000",
                "Priya owns the beta; feedback is due Friday",
                "Export and dark mode are cut from this release",
                "All-hands on Thursday at 3 pm to walk through it",
            ],
            generating: ("Email", "Thread: launch checklist · 42 replies")),
        "focus": Audience(
            samples: [
                (.webpage, "Article", "The science of sleeping better.\nKeep the same wake-up time every day, stop caffeine by 2 pm, and get daylight in the morning.", 0, true),
                (.text, "Copied text", "Long message about the trip, sorry!\nWe land at 6:40, so let's meet at gate B.", 0, true),
                (.webpage, "Article", "Why walking after meals helps:\na ten-minute walk lowers blood sugar spikes.", -1, false),
                (.email, "Email", "Your appointment is confirmed for Tuesday at 10:30.\nPlease arrive 15 minutes early.", -1, true),
            ],
            keyPoints: [
                "Wake up at the same time every day, weekends too",
                "Stop caffeine by 2 pm: it lasts 6+ hours",
                "No screens for 30 minutes before bed",
                "Keep the bedroom cool, around 18-20 °C",
                "Get daylight in the first hour after waking",
            ],
            generating: ("Article", "How to sleep better · 14 min read")),
        "ai": Audience(
            samples: [
                (.text, "AI answer", "Your 7-day Japan trip plan.\nSpend days one to three in Tokyo, take the bullet train to Kyoto on day four, and add a day trip to Nara.", 0, true),
                (.text, "AI answer", "Here's a weekly workout plan:\nthree strength days, two short runs and one long walk.", 0, true),
                (.text, "AI answer", "Explaining compound interest:\nmoney grows on both what you put in and what it already earned.", -1, false),
                (.text, "AI answer", "Ten dinner ideas under 30 minutes, with a shopping list for all of them.", -1, true),
            ],
            keyPoints: [
                "Days 1-3: Tokyo, with Shibuya, Asakusa and teamLab",
                "Day 4: bullet train to Kyoto, about 2 h 15 min",
                "A 7-day JR Pass costs about ¥50,000",
                "Days 5-6: Kyoto temples and a day trip to Nara",
                "Book popular temples early: they open at 8 am",
            ],
            generating: ("AI answer", "AI answer · 1,200 words")),
        "shiba": Audience(
            samples: [
                (.text, "Group chat", "Saturday plan, finally sorted!\nWe meet at Cafe Mocha at 11:30, not 11, because Rohan's train is late. Bring ₹500 each for lunch.", 0, true),
                (.text, "Copied text", "Mom's recipe:\ntwo cups of rice, a pinch of saffron, and let it rest for ten minutes.", 0, true),
                (.webpage, "Web", "The best street food in Mumbai, from vada pav to pani puri, and where to find it.", -1, false),
                (.email, "Email", "Your order has shipped and arrives Thursday between 9 am and 1 pm.", -1, true),
            ],
            keyPoints: [
                "Meet at Cafe Mocha at 11:30, not 11",
                "Rohan's train gets in late",
                "Bring ₹500 each for lunch",
                "Priya already paid the deposit",
                "Walk to the lake after lunch",
            ],
            generating: ("Group chat", "Group chat · 38 messages")),
    ]

    static func apply(to env: AppEnvironment) {
        guard let screen else { return }
        // Offline, silent voice: screens show their real playing layout
        // without the Notchman server.
        env.playback.voiceSource = DemoVoiceSource()
        let onboarding = ["onboarding": 0, "onboardingAccount": 1, "onboardingIsland": 2, "onboardingPaste": 3, "onboardingTry": 4][screen]
        AppGroup.defaults.set(onboarding == nil, forKey: SettingsKey.hasCompletedOnboarding)
        AppGroup.defaults.set(onboarding ?? 0, forKey: "onboarding.step")
        // Past the agreement (the onboarding shows it as its first step).
        if onboarding != 0 { LegalAgreement.accept() } else { AppGroup.defaults.removeObject(forKey: LegalAgreement.versionKey) }
        // The one-time privacy notice would cover the screen being captured.
        VoiceConsent.hasSeenNotice = true
        seed(env)

        switch screen {
        case "history":
            env.router.tab = .history
        case "account":
            env.router.tab = .account
        case "signIn":
            env.router.tab = .account
            env.router.sheet = .signIn
        case "paywall":
            env.premium.useDemoPrices()
            env.router.sheet = .paywall
        case "player", "keyPoints":
            if let item = env.history.item(id: sampleIDs[0]) {
                env.listen(to: item, fromStart: true)
                env.router.sheet = .player
            }
        case "fullread":
            if let item = env.history.item(id: sampleIDs[2]) {
                env.listen(to: item, fromStart: true)
                env.router.sheet = .player
            }
        case "settings":
            env.router.homePath = [.settings]
            loadMiniPlayer(env)
        case "home":
            loadMiniPlayer(env)
        case "generating":
            env.session.begin(.tldr)
            env.session.setLink(true)
            env.session.setSource(audience.generating.0, title: audience.generating.1)
            env.session.set(.summarizing)
            env.router.sheet = .player
        default:
            break
        }
    }

    /// Something loaded (not opened), so the mini player shows above the tab bar.
    private static func loadMiniPlayer(_ env: AppEnvironment) {
        if let item = env.history.item(id: sampleIDs[1]) {
            env.playback.play(item, fromStart: true)
        }
    }

    private static let sampleIDs = (0..<4).map { UUID(uuidString: "00000000-0000-0000-0000-00000000000\($0)")! }

    private static func seed(_ env: AppEnvironment) {
        // Each launch shows one audience's samples: replace whatever was seeded before.
        for id in sampleIDs {
            if let old = env.history.item(id: id) { env.history.context.delete(old) }
        }
        env.history.save()
        let samples = audience.samples
        for (index, sample) in samples.enumerated() {
            let item = ListeningItem(id: sampleIDs[index], source: sample.1, sourceType: sample.0,
                                     title: TextCleaner.title(from: sample.2, maxLength: 34),
                                     originalText: sample.2, spokenText: sample.2,
                                     createdAt: Calendar.current.date(byAdding: .day, value: sample.3, to: .now)!,
                                     duration: [182, 64, 240, 120][index], isQuickListen: sample.4)
            if index == 0 { item.keyPoints = audience.keyPoints }
            env.history.context.insert(item)
        }
        env.history.save()
    }
}
/// Silent audio as long as the text would take to say, so playback runs offline.
struct DemoVoiceSource: VoiceSource {
    func speak(text: String, previousText: String?, nextText: String?, voiceID: String) async throws -> Data {
        try await Task.sleep(for: .milliseconds(300))
        let seconds = max(1, Double(text.utf16.count) / 15)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1)!
        let frames = AVAudioFrameCount(seconds * 8_000)
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
            buffer.frameLength = frames
            try file.write(from: buffer)
        }
        return try Data(contentsOf: url)
    }
}
#endif
