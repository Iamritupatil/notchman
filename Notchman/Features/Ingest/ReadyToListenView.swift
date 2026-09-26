import SwiftUI

/// "Ready to listen" card shown when content arrives without an explicit action.
struct ReadyToListenView: View {
    let itemID: UUID

    @Environment(AppEnvironment.self) private var env
    @Environment(AppRouter.self) private var router

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if let item = env.history.item(id: itemID) {
                content(item)
            } else {
                Text("This item is gone").foregroundStyle(Theme.secondaryText)
            }
        }
        .presentationDetents([.height(470)])
        .presentationDragIndicator(.visible)
        .appAlert()
    }

    private func content(_ item: ListeningItem) -> some View {
        VStack(spacing: 14) {
            ShibaSprite(isActive: true)
                .frame(width: 96)
                .padding(.top, 30)

            Text("Ready to listen")
                .font(.title2.weight(.bold))

            SourceBadge(type: item.sourceType, name: item.source, url: item.url)

            Text(item.title)
                .font(.body)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text(TimeFormatter.summary(words: item.wordCount, seconds: item.duration))
                .font(.subheadline)
                .foregroundStyle(Theme.tertiaryText)
                .monospacedDigit()

            Spacer(minLength: 8)

            HStack(spacing: 12) {
                Button {
                    Haptics.tap()
                    env.quickListen(to: item)
                } label: {
                    if router.isPreparingQuickListen {
                        ProgressView()
                    } else {
                        Label("TL;DR", systemImage: "bolt.fill")
                    }
                }
                .buttonStyle(.notchmanSecondary)
                .disabled(router.isPreparingQuickListen)

                Button {
                    Haptics.tap()
                    env.listen(to: item)
                } label: {
                    Label("Read full", systemImage: "play.fill")
                }
                .buttonStyle(.notchmanPrimary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }
}
