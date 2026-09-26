import SwiftUI

struct RootView: View {
    @AppStorage(SettingsKey.hasCompletedOnboarding, store: AppGroup.defaults)
    private var hasCompletedOnboarding = false

    var body: some View {
        if hasCompletedOnboarding {
            MainView()
                .transition(.opacity)
        } else {
            OnboardingView {
                withAnimation(.smooth) { hasCompletedOnboarding = true }
            }
        }
    }
}

/// Home navigation stack, persistent mini player, and app-wide sheets.
struct MainView: View {
    @Environment(AppRouter.self) private var router
    @Environment(PlaybackManager.self) private var playback

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.path) {
            HomeView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .history: HistoryView()
                    case .settings: SettingsView()
                    }
                }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if playback.isActive {
                MiniPlayerView()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth, value: playback.isActive)
        .sheet(item: $router.sheet) { sheet in
            switch sheet {
            case .player:
                PlayerView()
            case .review(let id):
                ReadyToListenView(itemID: id)
            case .tryNotchman:
                TryNotchmanView()
            }
        }
        .appAlert()
    }
}

/// Shows `router.alert`. Applied at the root and inside sheets, because an
/// alert can only appear from the topmost presentation.
struct AppAlertModifier: ViewModifier {
    @Environment(AppRouter.self) private var router

    func body(content: Content) -> some View {
        let alert = router.alert
        content.alert(alert?.title ?? "", isPresented: Binding(
            get: { router.alert != nil },
            set: { if !$0 { router.alert = nil } }
        ), presenting: alert) { alert in
            if alert.showsSettingsButton {
                Button("Open Settings") { router.openSettings() }
            }
            Button("OK", role: .cancel) {}
        } message: { alert in
            Text(alert.message)
        }
    }
}

extension View {
    func appAlert() -> some View {
        modifier(AppAlertModifier())
    }
}
