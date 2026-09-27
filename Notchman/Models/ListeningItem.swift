import Foundation
import SwiftData

/// One thing the user listened to (or will). Stored locally with SwiftData.
@Model
final class ListeningItem {
    @Attribute(.unique) var id: UUID
    /// Display name of the source, e.g. "ChatGPT", "r/swift", "nytimes.com".
    var source: String
    var sourceType: SourceType
    var title: String
    /// Exactly what was shared, before cleaning.
    var originalText: String
    /// What the voice reads: cleaned text, or a Quick Listen summary.
    var spokenText: String
    var createdAt: Date
    var lastPlayedAt: Date?
    /// Estimated seconds at 1x.
    var duration: Double
    /// 0...1 through `spokenText`.
    var currentProgress: Double
    var completed: Bool
    var isSaved: Bool
    var url: String?
    var wordCount: Int = 0
    var isQuickListen: Bool = false
    /// A recorded voice clip for this item (cloud TL;DRs), in `ListeningItem.audioDirectory`.
    /// Nil means the text is read by Apple's on-device voice.
    var audioFileName: String? = nil

    init(id: UUID = UUID(), source: String, sourceType: SourceType, title: String, originalText: String,
         spokenText: String, createdAt: Date = .now, duration: Double, currentProgress: Double = 0,
         completed: Bool = false, isSaved: Bool = false, url: String? = nil, wordCount: Int = 0,
         isQuickListen: Bool = false) {
        self.id = id
        self.source = source
        self.sourceType = sourceType
        self.title = title
        self.originalText = originalText
        self.spokenText = spokenText
        self.createdAt = createdAt
        self.duration = duration
        self.currentProgress = currentProgress
        self.completed = completed
        self.isSaved = isSaved
        self.url = url
        self.wordCount = wordCount
        self.isQuickListen = isQuickListen
    }

    convenience init(content: ExtractedContent, spokenText: String, isQuickListen: Bool = false) {
        let title = content.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(source: content.sourceName,
                  sourceType: content.sourceType,
                  title: (title?.isEmpty == false ? title : nil) ?? TextCleaner.title(from: spokenText),
                  originalText: content.text,
                  spokenText: spokenText,
                  duration: ReadingEstimator.duration(of: spokenText),
                  url: content.url?.absoluteString,
                  wordCount: ReadingEstimator.wordCount(spokenText),
                  isQuickListen: isQuickListen)
    }

    /// Where recorded TL;DR voice clips are kept.
    static var audioDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Audio", isDirectory: true)
    }

    var audioURL: URL? {
        guard let audioFileName else { return nil }
        let url = Self.audioDirectory.appendingPathComponent(audioFileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var remainingDuration: Double { duration * (1 - min(max(currentProgress, 0), 1)) }
    var hasStarted: Bool { currentProgress > 0.01 && !completed }
}

extension ListeningItem {
    /// Sample content for previews and first launch in the simulator.
    static var samples: [ListeningItem] {
        [
            ListeningItem(source: "ChatGPT", sourceType: .chatGPT, title: "How to structure a SwiftUI app",
                          originalText: "", spokenText: "How to structure a SwiftUI app.", duration: 262,
                          currentProgress: 0.35),
            ListeningItem(source: "r/iOSProgramming", sourceType: .reddit, title: "What I learned shipping my first app",
                          originalText: "", spokenText: "What I learned shipping my first app.", duration: 184,
                          completed: true),
            ListeningItem(source: "Claude", sourceType: .claude, title: "Comparing three database options",
                          originalText: "", spokenText: "Comparing three database options.", duration: 95, isSaved: true),
        ]
    }
}
