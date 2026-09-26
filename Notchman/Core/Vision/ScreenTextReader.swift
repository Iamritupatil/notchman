import CoreGraphics
import Foundation
import Vision

/// On-device OCR for screenshots, using Apple's Vision framework (free, private).
enum ScreenTextReader {
    enum ReaderError: LocalizedError {
        case noText
        var errorDescription: String? { "Notchman couldn't find any text in this screenshot." }
    }

    static func lines(in image: CGImage) async throws -> [TextLine] {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])

            let lines = (request.results ?? []).compactMap { observation -> TextLine? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                let box = observation.boundingBox // normalized, bottom-left origin
                return TextLine(text: candidate.string,
                                box: CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height),
                                confidence: candidate.confidence)
            }
            guard !lines.isEmpty else { throw ReaderError.noText }
            return lines
        }.value
    }
}
