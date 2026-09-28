import AppIntents
import CoreImage
import Foundation

#if canImport(VisualIntelligence)
import VisualIntelligence

/// Notchman inside Apple's Visual Intelligence (iOS 26, Apple Intelligence
/// iPhones): take a screenshot, highlight a message, and "TL;DR" results from
/// Notchman appear. No shortcut or setup needed.
///
/// The query reads the text in what the user highlighted (on device, Vision)
/// and offers one result per message. Tapping one opens Notchman and plays its
/// TL;DR.
@available(iOS 26.0, *)
struct ScreenMessageValueQuery: IntentValueQuery {
    func values(for input: SemanticContentDescriptor) async throws -> [ScreenMessageEntity] {
        guard let pixelBuffer = input.pixelBuffer else { return [] }
        let cgImage: CGImage? = pixelBuffer.withUnsafeBuffer { buffer in
            let image = CIImage(cvPixelBuffer: buffer)
            return CIContext().createCGImage(image, from: image.extent)
        }
        guard let cgImage else { return [] }

        let lines = try await ScreenTextReader.lines(in: cgImage)
        // The highlight is already cropped, so keep everything, even near the edges.
        let options = MessageBlockDetector.Options(topInset: 0, bottomInset: 0, minimumCharacters: 40)
        var blocks = MessageBlockDetector.blocks(from: lines, options: options)
            .sorted { $0.characterCount > $1.characterCount }
        let everything = lines.map(\.text).joined(separator: " ")
        if blocks.isEmpty, everything.count >= 40 {
            blocks = [MessageBlock(id: 0, lines: lines, box: CGRect(x: 0, y: 0, width: 1, height: 1))]
        }

        let source = MessageBlockDetector.guessSource(from: lines)
        let entities = blocks.prefix(3).map { block in
            ScreenMessageEntity(text: block.text, source: source)
        }
        ScreenMessageStore.remember(entities)
        return entities
    }
}
#endif

/// A message found in a screenshot, offered as a TL;DR result.
struct ScreenMessageEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Message"
    static let defaultQuery = ScreenMessageEntityQuery()

    let id: String
    let text: String
    let sourceRaw: String

    init(id: String = UUID().uuidString, text: String, source: SourceType) {
        self.id = id
        self.text = text
        self.sourceRaw = source.rawValue
    }

    var source: SourceType { SourceType(rawValue: sourceRaw) ?? .text }

    var displayRepresentation: DisplayRepresentation {
        let words = ReadingEstimator.wordCount(text)
        let preview = text.split(separator: " ").prefix(12).joined(separator: " ")
        return DisplayRepresentation(
            title: "TL;DR with Notchman",
            subtitle: "\(preview)… · \(words) words",
            image: .init(systemName: "headphones"))
    }
}

struct ScreenMessageEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ScreenMessageEntity] {
        identifiers.compactMap(ScreenMessageStore.entity(id:))
    }
}

/// Keeps the latest results so the open intent can find them by ID. Stored in
/// the app group because the query and the open intent can run separately.
enum ScreenMessageStore {
    private static let key = "visualIntelligence.results"

    static func remember(_ entities: [ScreenMessageEntity]) {
        let values = entities.map { ["id": $0.id, "text": $0.text, "source": $0.sourceRaw] }
        AppGroup.defaults.set(values, forKey: key)
    }

    static func entity(id: String) -> ScreenMessageEntity? {
        let values = AppGroup.defaults.array(forKey: key) as? [[String: String]] ?? []
        guard let match = values.first(where: { $0["id"] == id }), let text = match["text"] else { return nil }
        return ScreenMessageEntity(id: id, text: text, source: SourceType(rawValue: match["source"] ?? "") ?? .text)
    }
}

/// Opens Notchman and plays the TL;DR of the chosen message.
struct OpenScreenMessageIntent: OpenIntent {
    static let title: LocalizedStringResource = "TL;DR Message"

    @Parameter(title: "Message")
    var target: ScreenMessageEntity

    init() {}

    func perform() async throws -> some IntentResult {
        let source = target.source
        let content = ExtractedContent(text: target.text, title: nil, sourceType: source,
                                       sourceName: source == .text ? "Screenshot" : source.displayName, url: nil)
        await MainActor.run {
            AppEnvironment.shared.ingest(content, action: .quickListen)
        }
        return .result()
    }
}
