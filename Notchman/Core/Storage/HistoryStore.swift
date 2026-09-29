import AVFoundation
import Foundation
import Observation
import os
import SwiftData

/// Listening history persistence. Views read with `@Query`; mutations go
/// through here so playback and UI agree on what's saved.
@MainActor
@Observable
final class HistoryStore {
    let context: ModelContext
    private let log = Logger(subsystem: "com.notchman", category: "History")

    init(context: ModelContext) {
        self.context = context
    }

    func item(id: UUID) -> ListeningItem? {
        var descriptor = FetchDescriptor<ListeningItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Creates an item from extracted content, or returns the existing one if
    /// the exact same text was shared before (so re-sharing resumes it).
    @discardableResult
    func addItem(from content: ExtractedContent, options: TextCleaner.Options) -> ListeningItem {
        let original = content.text
        var descriptor = FetchDescriptor<ListeningItem>(
            predicate: #Predicate { $0.originalText == original && $0.isQuickListen == false })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }

        let spoken = TextCleaner(options: options).clean(content.text)
        let item = ListeningItem(content: content, spokenText: spoken)
        context.insert(item)
        save()
        return item
    }

    /// Saves a TL;DR. `audio` is the recorded voice (MP3) when the server made one;
    /// without it, Apple's on-device voice reads the summary.
    func addQuickListen(for original: ListeningItem, summary: String, audio: Data? = nil) -> ListeningItem {
        let content = ExtractedContent(text: original.originalText, title: original.title,
                                       sourceType: original.sourceType, sourceName: original.source,
                                       url: original.url.flatMap(URL.init(string:)))
        let item = ListeningItem(content: content, spokenText: summary, isQuickListen: true)
        if let audio, let clipDuration = saveAudio(audio, for: item.id) {
            item.audioFileName = "\(item.id.uuidString).mp3"
            item.duration = clipDuration
        }
        context.insert(item)
        save()
        return item
    }

    /// Keeps the voice made while listening, so the item replays instantly.
    func attachAudio(_ audio: Data, to id: UUID) {
        guard let item = item(id: id), item.audioFileName == nil,
              let clipDuration = saveAudio(audio, for: id) else { return }
        item.audioFileName = "\(id.uuidString).mp3"
        item.duration = clipDuration
        save()
    }

    func updateProgress(id: UUID, progress: Double, completed: Bool) {
        guard let item = item(id: id) else { return }
        item.currentProgress = min(max(progress, 0), 1)
        item.completed = completed
        save()
    }

    func toggleSaved(_ item: ListeningItem) {
        item.isSaved.toggle()
        save()
    }

    func delete(_ item: ListeningItem) {
        if let url = item.audioURL { try? FileManager.default.removeItem(at: url) }
        context.delete(item)
        save()
    }

    /// Writes a voice clip and returns its length, or nil if it isn't playable.
    private func saveAudio(_ data: Data, for id: UUID) -> TimeInterval? {
        let directory = ListeningItem.audioDirectory
        let url = directory.appendingPathComponent("\(id.uuidString).mp3")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            guard let duration = try? AVAudioPlayer(contentsOf: url).duration, duration > 0 else {
                try? FileManager.default.removeItem(at: url)
                return nil
            }
            return duration
        } catch {
            log.error("Couldn't save TL;DR audio: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func save() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            log.error("Save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
