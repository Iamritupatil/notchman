import SwiftUI

/// "Ready to listen" card shown when content arrives without an explicit action.
struct ReadyToListenView: View {
    let itemID: UUID

    @Environment(AppEnvironment.self) private var env
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let item = env.history.item(id: itemID) {
                content(item)
            } else {
                ContentUnavailableView("This item is gone", systemImage: "questionmark.circle")
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .appAlert()
    }

    private func content(_ item: ListeningItem) -> some View {
        VStack(spacing: 18) {
            Text("Ready to listen")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 28)

            SourceBadge(type: item.sourceType, name: item.source)

            Text(item.title)
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
                .lineLimit(3)

            Text(TimeFormatter.summary(words: item.wordCount, seconds: item.duration))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Spacer(minLength: 8)

            VStack(spacing: 10) {
                Button {
                    Haptics.tap()
                    env.listen(to: item)
                } label: {
                    Label("Read", systemImage: "play.fill")
                }
                .buttonStyle(.notchmanPrimary)

                Button {
                    Haptics.tap()
                    env.quickListen(to: item)
                } label: {
                    if router.isPreparingQuickListen {
                        ProgressView()
                    } else {
                        Label("Quick Listen", systemImage: "bolt.fill")
                    }
                }
                .buttonStyle(.notchmanSecondary)
                .disabled(router.isPreparingQuickListen)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }
}
