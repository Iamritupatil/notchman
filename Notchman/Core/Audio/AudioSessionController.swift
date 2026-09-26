import AVFoundation
import os

/// Owns AVAudioSession configuration and translates system audio events
/// (calls, Siri, other apps, headphones unplugged) into simple callbacks.
@MainActor
final class AudioSessionController {
    var onInterruptionBegan: (() -> Void)?
    /// `true` when the system says it's appropriate to resume automatically.
    var onInterruptionEnded: ((_ shouldResume: Bool) -> Void)?
    /// Headphones/AirPods disconnected: pause, never keep talking out of the speaker.
    var onOutputDeviceLost: (() -> Void)?

    private let session = AVAudioSession.sharedInstance()
    private let log = Logger(subsystem: "com.notchman", category: "AudioSession")
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification,
                                            object: session, queue: .main) { [weak self] note in
            let info = note.userInfo ?? [:]
            MainActor.assumeIsolated { self?.handleInterruption(info) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification,
                                            object: session, queue: .main) { [weak self] note in
            let info = note.userInfo ?? [:]
            MainActor.assumeIsolated { self?.handleRouteChange(info) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification,
                                            object: session, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleMediaServicesReset() }
        })
    }

    /// Spoken-audio playback: keeps running in the background and on the Lock
    /// Screen, and pauses other audio (like a podcast app would).
    func activate() {
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [])
            try session.setActive(true)
        } catch {
            log.error("Failed to activate audio session: \(error.localizedDescription, privacy: .public)")
        }
    }

    func deactivate() {
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            log.debug("Deactivate failed (usually harmless): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handleInterruption(_ info: [AnyHashable: Any]) {
        guard let rawType = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        switch type {
        case .began:
            onInterruptionBegan?()
        case .ended:
            let rawOptions = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume)
            onInterruptionEnded?(shouldResume)
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ info: [AnyHashable: Any]) {
        guard let rawReason = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason) else { return }
        if reason == .oldDeviceUnavailable {
            onOutputDeviceLost?()
        }
    }

    private func handleMediaServicesReset() {
        log.error("Media services were reset; reconfiguring audio session.")
        onOutputDeviceLost?()
        activate()
    }
}
