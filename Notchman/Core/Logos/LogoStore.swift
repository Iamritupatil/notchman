import CryptoKit
import Foundation
import os
import UIKit

/// Finds the real logo for any source, without a hard-coded list of apps.
///
/// Resolution order:
/// 1. A logo you bundled (`design/logos`, imported as `logo-<name>` assets).
/// 2. For web content: the site's own icon (apple-touch-icon, `<link rel=icon>`, favicon),
///    fetched from that site.
/// 3. For apps: the App Store icon, via Apple's public iTunes Search API, only on an
///    exact name match so a wrong logo is never shown.
/// Results (and misses) are cached on disk. Only the app name or domain is ever
/// sent, never message content.
actor LogoStore {
    static let shared = LogoStore()

    struct Logo {
        let image: UIImage
        /// App icons are full-bleed squares; site icons need padding inside the tile.
        let fillsTile: Bool
    }

    struct Query: Hashable, Sendable {
        var name: String
        var domain: String?

        var cacheKey: String {
            let raw = (domain ?? "app:" + name).lowercased()
            let digest = SHA256.hash(data: Data(raw.utf8))
            return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
        }
    }

    /// Names that describe a kind of content rather than an app; never looked up.
    static let genericNames: Set<String> = ["text", "copied text", "email", "web", "screenshot", "untitled"]
    /// Apple's own apps: only accept App Store results published by Apple.
    static let appleAppNames: Set<String> = ["mail", "messages", "notes", "safari", "news", "books"]
    /// A few well-known names whose App Store titles differ from how people say them.
    static let appStoreAliases: [String: String] = ["gemini": "Google Gemini", "gmail": "Gmail - Email by Google",
                                                                  "whatsapp": "WhatsApp Messenger"]

    private var memory: [String: Logo] = [:]
    private var inFlight: [String: Task<Logo?, Never>] = [:]
    private let session: URLSession
    private let log = Logger(subsystem: "com.notchman", category: "Logos")
    /// A miss can be a network blip, so try again the next day, not next week.
    private static let missRetryInterval: TimeInterval = 24 * 3600

    init(session: URLSession = .shared) {
        self.session = session
    }

    func logo(for query: Query) async -> Logo? {
        if let bundled = Self.bundledLogo(named: query.name) { return bundled }
        let key = query.cacheKey
        if let cached = memory[key] { return cached }
        if let task = inFlight[key] { return await task.value }

        let task = Task<Logo?, Never> { await self.resolve(query) }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if let result { memory[key] = result }
        return result
    }

    // MARK: - Resolution

    private func resolve(_ query: Query) async -> Logo? {
        let key = query.cacheKey
        if let cached = Self.readDisk(key) { return cached }
        if Self.recentlyMissed(key) { return nil }

        var logo: Logo?
        if let domain = query.domain {
            logo = await siteIcon(for: domain)
        }
        if logo == nil, !Self.genericNames.contains(query.name.lowercased()) {
            logo = await appStoreIcon(for: query.name)
        }

        if let logo {
            Self.writeDisk(logo, key: key)
        } else {
            Self.recordMiss(key)
        }
        return logo
    }

    private func siteIcon(for domain: String) async -> Logo? {
        let host = domain.hasPrefix("www.") ? String(domain.dropFirst(4)) : domain
        guard let base = URL(string: "https://\(host)") else { return nil }

        // Most sites serve a 180px icon here; it looks far better than a favicon.
        if let image = await fetchImage(base.appendingPathComponent("apple-touch-icon.png"), minimumSize: 32) {
            return Logo(image: image, fillsTile: true)
        }
        if let html = await fetchText(base), let href = Self.bestIconHref(in: html),
           let url = URL(string: href, relativeTo: base)?.absoluteURL,
           let image = await fetchImage(url, minimumSize: 16) {
            return Logo(image: image, fillsTile: image.size.width >= 120)
        }
        if let image = await fetchImage(base.appendingPathComponent("favicon.ico"), minimumSize: 16) {
            return Logo(image: image, fillsTile: false)
        }
        return nil
    }

    private func appStoreIcon(for name: String) async -> Logo? {
        let term = Self.appStoreAliases[name.lowercased()] ?? name
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "entity", value: "software"),
            URLQueryItem(name: "limit", value: "8"),
            URLQueryItem(name: "country", value: Locale.current.region?.identifier.lowercased() ?? "us"),
        ]
        guard let url = components.url,
              let (data, _) = try? await session.data(from: url),
              let results = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["results"] as? [[String: Any]],
              let match = Self.bestAppMatch(results, for: name, term: term),
              let artwork = (match["artworkUrl512"] ?? match["artworkUrl100"]) as? String,
              let artworkURL = URL(string: artwork),
              let image = await fetchImage(artworkURL, minimumSize: 64) else { return nil }
        return Logo(image: image, fillsTile: true)
    }

    // MARK: - Parsing (static for tests)

    /// Picks the largest icon declared in a page's `<head>`.
    static func bestIconHref(in html: String) -> String? {
        let pattern = #"(?is)<link\b[^>]*\brel\s*=\s*["']([^"']*)["'][^>]*>"#
        var best: (href: String, score: Int)?
        let ns = html as NSString
        for match in RegexKit.regex(pattern).matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let tag = ns.substring(with: match.range)
            let rel = ns.substring(with: match.range(at: 1)).lowercased()
            guard rel.contains("icon"), !rel.contains("mask"),
                  let href = RegexKit.firstMatch(#"(?i)\bhref\s*=\s*["']([^"']+)["']"#, in: tag)?[1] else { continue }
            let size = Int(RegexKit.firstMatch(#"(?i)\bsizes\s*=\s*["'](\d+)x\d+["']"#, in: tag)?[1] ?? "") ?? 0
            let score = (rel.contains("apple-touch-icon") ? 1_000 : 0) + size + (href.hasSuffix(".svg") ? -2_000 : 0)
            if best == nil || score > best!.score { best = (href, score) }
        }
        return best?.href
    }

    /// Exact-name App Store match only, so we never show the wrong company's icon.
    static func bestAppMatch(_ results: [[String: Any]], for name: String, term: String) -> [String: Any]? {
        let wanted = [normalize(name), normalize(term)]
        let requiresApple = appleAppNames.contains(name.lowercased())
        return results.first { result in
            guard let title = result["trackName"] as? String else { return false }
            if requiresApple, (result["artistName"] as? String) != "Apple" { return false }
            let full = normalize(title)
            // "ChatGPT", "Slack for iPhone", "Reddit: Community & Chat" all reduce to their app name.
            let short = normalize(title.components(separatedBy: CharacterSet(charactersIn: ":–—-|")).first ?? title)
            // "Claude by Anthropic" style titles.
            let byline = full.components(separatedBy: " by ").first ?? full
            return wanted.contains(full) || wanted.contains(short) || wanted.contains(byline)
        }
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: " for iphone", with: "")
            .replacingOccurrences(of: " for ipad", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Networking

    private func fetchImage(_ url: URL, minimumSize: CGFloat) async -> UIImage? {
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("Notchman/1.0 (logo lookup)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false,
              let image = UIImage(data: data),
              image.size.width >= minimumSize else { return nil }
        return Self.downscaled(image, to: 180)
    }

    private func fetchText(_ url: URL) async -> String? {
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("Mozilla/5.0 (iPhone) Notchman/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await session.data(for: request) else { return nil }
        // Icons are declared in <head>; don't hold whole pages in memory.
        return String(decoding: data.prefix(200_000), as: UTF8.self)
    }

    private static func downscaled(_ image: UIImage, to side: CGFloat) -> UIImage {
        guard image.size.width > side else { return image }
        let size = CGSize(width: side, height: side * image.size.height / image.size.width)
        return UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }

    // MARK: - Bundled & disk cache

    private static func bundledLogo(named name: String) -> Logo? {
        let slug = name.lowercased().filter { $0.isLetter || $0.isNumber }
        guard !slug.isEmpty, let image = UIImage(named: "logo-\(slug)") else { return nil }
        return Logo(image: image, fillsTile: true)
    }

    private static var directory: URL {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logos", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func readDisk(_ key: String) -> Logo? {
        for (suffix, fills) in [("fill", true), ("pad", false)] {
            let url = directory.appendingPathComponent("\(key)-\(suffix).png")
            if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                return Logo(image: image, fillsTile: fills)
            }
        }
        return nil
    }

    private static func writeDisk(_ logo: Logo, key: String) {
        let url = directory.appendingPathComponent("\(key)-\(logo.fillsTile ? "fill" : "pad").png")
        try? logo.image.pngData()?.write(to: url, options: .atomic)
    }

    private static func recentlyMissed(_ key: String) -> Bool {
        let url = directory.appendingPathComponent("\(key).miss")
        guard let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else {
            return false
        }
        return date.timeIntervalSinceNow > -missRetryInterval
    }

    private static func recordMiss(_ key: String) {
        FileManager.default.createFile(atPath: directory.appendingPathComponent("\(key).miss").path, contents: Data())
    }
}
