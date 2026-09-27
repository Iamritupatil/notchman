import SwiftData
import SwiftUI
import UIKit

struct HomeView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(AppRouter.self) private var router
    @Environment(PlaybackManager.self) private var playback

    @Query(HomeView.recentDescriptor) private var recent: [ListeningItem]

    static var recentDescriptor: FetchDescriptor<ListeningItem> {
        var descriptor = FetchDescriptor<ListeningItem>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = 4
        return descriptor
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                topBar
                hero

                if !recent.isEmpty {
                    recentSection
                }

                BackTapCard()
                ShareTipCard()

                Button {
                    Haptics.tap()
                    env.tldrCopiedText()
                } label: {
                    Label("TL;DR what I copied", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.notchmanPrimary)

                #if DEBUG
                Button {
                    router.sheet = .tryNotchman
                } label: {
                    Label("Try Notchman (developer)", systemImage: "text.badge.plus")
                }
                .buttonStyle(.notchmanSecondary)
                #endif
            }
            .padding(.horizontal, Theme.horizontalPadding)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            ShibaSprite(isActive: playback.isPlaying)
                .frame(width: 38)
            Text("Notchman")
                .font(.pixel(24))
                .foregroundStyle(Theme.amber)
            Spacer()
            NavigationLink(value: Route.settings) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(Theme.cardRaised, in: Circle())
            }
            .accessibilityLabel("Settings")
        }
        .padding(.top, 12)
    }

    private var hero: some View {
        VStack(spacing: 18) {
            MascotStage(isActive: playback.isPlaying, width: 180)
                .frame(height: 190)
            VStack(spacing: 8) {
                Text("Read less.\nListen instead.")
                    .font(.system(size: 34, weight: .bold))
                    .multilineTextAlignment(.center)
                Text("Long message? Let Notchman read it.")
                    .font(.body)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .card()
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                Button("See All") {
                    withAnimation(.snappy) { router.tab = .history }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.amber)
            }
            .padding(.horizontal, 6)

            VStack(spacing: 0) {
                ForEach(recent) { item in
                    Button {
                        Haptics.tap()
                        env.listen(to: item)
                    } label: {
                        HistoryRow(item: item, isCurrent: playback.nowPlaying?.itemID == item.id && playback.isPlaying)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu { HistoryItemMenu(item: item) }

                    if item.id != recent.last?.id {
                        Divider().overlay(Theme.stroke).padding(.leading, 88)
                    }
                }
            }
            .card()
        }
    }
}

/// How to get "tap and TL;DR" on iPhone: a two-action shortcut on Back Tap or
/// the Action button (iOS doesn't let apps respond to taps on the notch).
private struct BackTapCard: View {
    @State private var isExpanded = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(.snappy) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "hand.tap.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.amber)
                        .frame(width: 52, height: 52)
                        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Copy → tap the island → TL;DR")
                            .font(.headline)
                        Text("The Shiba waits in your Dynamic Island.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    step(1, "In ChatGPT, Claude, WhatsApp, LinkedIn or anywhere: copy the long message.")
                    step(2, "Tap the Shiba in the Dynamic Island (or press the Action button set to Notchman TL;DR).")
                    step(3, "The TL;DR plays. Tip: Settings → Notchman → Paste from Other Apps → Allow, so iOS stops asking.")
                }
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(.notchmanPrimary)
            }
        }
        .padding(16)
        .card()
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.black)
                .frame(width: 22, height: 22)
                .background(Theme.amber, in: Circle())
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
    }
}

private struct ShareTipCard: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "square.and.arrow.up")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.amber)
                .frame(width: 52, height: 52)
                .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("Share → Listen with Notchman")
                    .font(.headline)
                Text("Works from ChatGPT, Claude, Reddit, Safari, Mail and more.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .card()
    }
}
