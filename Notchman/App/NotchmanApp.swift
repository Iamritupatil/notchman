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
                .onOpenURL { env.handle(url: $0) }
        }
        .modelContainer(env.modelContainer)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                env.processInbox()
            case .background:
                env.playback.persistProgress()
            default:
                break
            }
        }
    }
}
