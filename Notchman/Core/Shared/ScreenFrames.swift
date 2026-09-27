import Foundation

/// Hand-off between the screen-reading broadcast extension and the app.
///
/// While "Screen reading" is on (a ReplayKit broadcast the user starts once),
/// the extension saves a JPEG of the screen about twice a second into the App
/// Group, keeping the last few. When the user taps Notchman in the Dynamic
/// Island, the app picks the newest frame taken *before* Notchman came to the
/// front: that's the ChatGPT / WhatsApp / LinkedIn screen the user was looking at.
enum ScreenFrames {
    static let keep = 6
    static let interval: TimeInterval = 0.5

    static var directory: URL {
        let url = AppGroup.containerURL.appendingPathComponent("Screen", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Written by the extension on every frame; its age tells the app whether the broadcast is running.
    static var heartbeatURL: URL { directory.appendingPathComponent("heartbeat") }
    /// Written by the app while it's in the foreground, so the extension skips Notchman's own screens.
    static var appActiveURL: URL { directory.appendingPathComponent("app-active") }

    struct Frame {
        let url: URL
        let time: Date
    }

    static func frameURL(at time: Date) -> URL {
        directory.appendingPathComponent(String(format: "frame-%.3f.jpg", time.timeIntervalSince1970))
    }

    static func frames() -> [Frame] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.compactMap { url in
            let name = url.deletingPathExtension().lastPathComponent
            guard name.hasPrefix("frame-"), let seconds = Double(name.dropFirst("frame-".count)) else { return nil }
            return Frame(url: url, time: Date(timeIntervalSince1970: seconds))
        }
        .sorted { $0.time > $1.time }
    }

    /// Deletes all but the newest `keep` frames.
    static func prune() {
        for old in frames().dropFirst(keep) {
            try? FileManager.default.removeItem(at: old.url)
        }
    }

    static func removeAll() {
        for frame in frames() { try? FileManager.default.removeItem(at: frame.url) }
        try? FileManager.default.removeItem(at: heartbeatURL)
    }

    /// True if the broadcast wrote a frame in the last few seconds.
    static var isBroadcasting: Bool {
        guard let date = modificationDate(heartbeatURL) else { return false }
        return Date().timeIntervalSince(date) < 5
    }

    /// The newest frame taken before `date`, i.e. before Notchman opened.
    static func frame(before date: Date) -> Frame? {
        frames().first { $0.time < date }
    }

    // MARK: App foreground flag

    static func setAppActive(_ active: Bool) {
        if active {
            try? Data().write(to: appActiveURL)
        } else {
            try? FileManager.default.removeItem(at: appActiveURL)
        }
    }

    /// The app refreshes the flag every second while in front, so a flag left
    /// behind by a crash or force-quit expires on its own.
    static var isAppActive: Bool {
        guard let date = modificationDate(appActiveURL) else { return false }
        return Date().timeIntervalSince(date) < 3
    }

    static func modificationDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}
