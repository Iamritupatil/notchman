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
        .preferredColorScheme(.light)
        .tint(Theme.amber)
        .foregroundStyle(Theme.primaryText)
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
            Theme.sky.ignoresSafeArea()

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
                case .screenPicker(let url): MessagePickerView(imageURL: url).interactiveDismissDisabled()
                case .voiceConsent: VoiceConsentView()
                }
            }
            .preferredColorScheme(.light)
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

/// Compact floating tab bar. The selected tab gets a capsule that follows the
/// bar's own capsule shape, so the highlight and the border line up.
struct NotchTabBar: View {
    @Binding var selection: AppTab
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                let isSelected = tab == selection
                Button {
                    Haptics.tap()
                    withAnimation(.snappy(duration: 0.25)) { selection = tab }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 17, weight: .semibold))
                            .frame(height: 20)
                        Text(tab.title)
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(isSelected ? Theme.amber : Theme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(Theme.amber.opacity(0.12))
                                .matchedGeometryEffect(id: "selection", in: highlight)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
        .background(Theme.card.opacity(0.85), in: Capsule())
        .overlay(Capsule().stroke(Theme.stroke, lineWidth: 0.5))
        .shadow(color: Theme.primaryText.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal, 48)
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
            if alert.showsUpgradeButton {
                Button("See Plans") { router.alert = nil; router.sheet = .paywall }
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
