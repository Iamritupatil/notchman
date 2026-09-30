import SwiftData
import SwiftUI

@main
struct NotchmanApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let env = AppEnvironment.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(env)
                .environment(env.router)
                .environment(env.playback)
                .environment(env.history)
                .environment(env.account)
                .environment(env.premium)
                .task {
                    #if DEBUG
                    DemoMode.apply(to: env)
                    #endif
                    await env.account.refreshCredentialState()
                    await env.refreshUsage()
                }
                .onOpenURL { env.handle(url: $0) }
        }
        .modelContainer(env.modelContainer)
        .onChange(of: scenePhase) { _, phase in
            // Note the clipboard's copy counter whenever Notchman runs, so the
            // island can tell a fresh copy from old content later.
            env.acquisition.observeClipboard()
            switch phase {
            case .active:
                env.processInbox()
                // A Read / TL;DR the island couldn't finish (iOS hid the
                // clipboard) completes now, as the same action.
                env.runPendingActionIfAny()
                if AppGroup.defaults.bool(forKey: SettingsKey.hasCompletedOnboarding) {
                    env.playback.showInDynamicIsland()
                    env.showPrivacyNoticeIfNeeded()
                }
            case .background:
                env.playback.persistProgress()
            default:
                break
            }
        }
    }
}
