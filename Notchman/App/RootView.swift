import SwiftUI

struct RootView: View {
    @AppStorage(SettingsKey.hasCompletedOnboarding, store: AppGroup.defaults)
    private var hasCompletedOnboarding = false

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                MainView()
                    .transition(.opacity)
            } else {
                OnboardingView {
                    withAnimation(.smooth) { hasCompletedOnboarding = true }
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.amber)
    }
}

/// Tabs (Home, History, Account), the floating tab bar, the mini player and
/// app-wide sheets.
struct MainView: View {
    @Environment(AppRouter.self) private var router
    @Environment(PlaybackManager.self) private var playback

    var body: some View {
        @Bindable var router = router

        ZStack {
            Theme.background.ignoresSafeArea()

            switch router.tab {
            case .home:
                NavigationStack(path: $router.homePath) {
                    HomeView().withRoutes()
                }
            case .history:
                NavigationStack(path: $router.historyPath) {
                    HistoryView().withRoutes()
                }
            case .account:
                NavigationStack(path: $router.accountPath) {
                    AccountView().withRoutes()
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                if playback.isActive {
                    MiniPlayerView()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                NotchTabBar(selection: $router.tab)
            }
            .padding(.bottom, 4)
        }
        .animation(.smooth, value: playback.isActive)
        .sheet(item: $router.sheet) { sheet in
            Group {
                switch sheet {
                case .player: PlayerView()
                case .review(let id): ReadyToListenView(itemID: id)
                case .tryNotchman: TryNotchmanView()
                case .signIn: SignInView()
                case .paywall: PaywallView()
                }
            }
            .preferredColorScheme(.dark)
            .tint(Theme.amber)
        }
        .appAlert()
    }
}

private extension View {
    func withRoutes() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .history: HistoryView()
            case .settings: SettingsView()
            }
        }
    }
}

/// Floating pill tab bar from the Notchman design.
struct NotchTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { tab in
                let isSelected = tab == selection
                Button {
                    Haptics.tap()
                    withAnimation(.snappy) { selection = tab }
                } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            if isSelected {
                                Circle()
                                    .fill(Theme.amber)
                                    .frame(width: 30, height: 30)
                                    .shadow(color: Theme.amber.opacity(0.6), radius: 10)
                            }
                            Image(systemName: tab.symbol)
                                .font(.system(size: isSelected ? 15 : 20, weight: .semibold))
                                .foregroundStyle(isSelected ? Color.black.opacity(0.85) : Theme.secondaryText)
                        }
                        .frame(height: 30)
                        Text(tab.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isSelected ? Theme.amber : Theme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, minHeight: 62)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(6)
        .background(Theme.card.opacity(0.92), in: Capsule())
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Theme.stroke))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
        .padding(.horizontal, 32)
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
