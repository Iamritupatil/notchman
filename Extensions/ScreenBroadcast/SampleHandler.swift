import CoreImage
import ReplayKit

/// "Notchman Screen Reading": a ReplayKit broadcast upload extension.
///
/// Nothing is uploaded anywhere. About twice a second it saves the current
/// screen into the App Group so that, when the user taps Notchman in the
/// Dynamic Island, the app can find the long message on the screen they were
/// reading. Frames are kept on the device, only the newest few are kept, and
/// they're all deleted when the broadcast stops.
final class SampleHandler: RPBroadcastSampleHandler {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var lastSave = Date.distantPast
    private let queue = DispatchQueue(label: "app.notchman.screen.frames")
    private var isSaving = false

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        ScreenFrames.removeAll()
        try? Data().write(to: ScreenFrames.heartbeatURL)
    }

    override func broadcastFinished() {
        ScreenFrames.removeAll()
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }
        let now = Date()
        guard now.timeIntervalSince(lastSave) >= ScreenFrames.interval, !isSaving else { return }
        lastSave = now
        try? Data().write(to: ScreenFrames.heartbeatURL)

        // Notchman's own screens are never useful to read.
        guard !ScreenFrames.isAppActive, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        var image = CIImage(cvPixelBuffer: pixels)
        if let raw = CMGetAttachment(sampleBuffer, key: RPVideoSampleOrientationKey as CFString, attachmentModeOut: nil) as? NSNumber,
           let orientation = CGImagePropertyOrientation(rawValue: raw.uint32Value) {
            image = image.oriented(orientation)
        }
        // A little smaller keeps memory well under the extension's limit; text stays sharp enough to read.
        image = image.transformed(by: CGAffineTransform(scaleX: 0.75, y: 0.75))

        isSaving = true
        queue.async { [context] in
            defer { self.isSaving = false }
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let jpeg = context.jpegRepresentation(of: image, colorSpace: space,
                                                        options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.7])
            else { return }
            try? jpeg.write(to: ScreenFrames.frameURL(at: now), options: .atomic)
            ScreenFrames.prune()
        }
    }
}
