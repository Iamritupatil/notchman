#if DEBUG
import Foundation

/// Debug-only launch arguments for screenshots and UI review:
///
///     -demoScreen home|history|player|account|signIn|onboarding|paywall
///
/// Seeds sample history and opens the requested screen. Never compiled into
/// release builds.
@MainActor
enum DemoMode {
    static var screen: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-demoScreen"), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    static func apply(to env: AppEnvironment) {
        guard let screen else { return }
        AppGroup.defaults.set(screen != "onboarding", forKey: SettingsKey.hasCompletedOnboarding)
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
            env.router.sheet = .paywall
        case "player":
            if let item = env.history.item(id: sampleIDs[0]) {
                env.listen(to: item, fromStart: true)
            }
        default:
            break
        }
    }

    private static let sampleIDs = (0..<4).map { UUID(uuidString: "00000000-0000-0000-0000-00000000000\($0)")! }

    private static func seed(_ env: AppEnvironment) {
        guard env.history.item(id: sampleIDs[0]) == nil else { return }
        let samples: [(SourceType, String, String, Int, Bool)] = [
            (.chatGPT, "ChatGPT", "Here's how the architecture would work. So the three key takeaways are speed, cost, and reliability. First, speed matters because users leave slow apps.", 0, true),
            (.text, "Messages", "So the plan for Saturday is brunch at eleven, then the park if the weather holds.", 0, true),
            (.reddit, "Reddit", "I've been building this for eighteen months and here is everything I learned about shipping.", -1, true),
            (.email, "Mail", "Following up on the proposal we discussed last week, with the updated numbers attached.", -1, true),
        ]
        for (index, sample) in samples.enumerated() {
            let item = ListeningItem(id: sampleIDs[index], source: sample.1, sourceType: sample.0,
                                     title: TextCleaner.title(from: sample.2, maxLength: 34),
                                     originalText: sample.2, spokenText: sample.2,
                                     createdAt: Calendar.current.date(byAdding: .day, value: sample.3, to: .now)!,
                                     duration: [182, 64, 240, 120][index], isQuickListen: sample.4)
            env.history.context.insert(item)
        }
        env.history.save()
    }
}
#endif
