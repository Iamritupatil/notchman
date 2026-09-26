import Foundation

/// Small cached wrapper around NSRegularExpression with closure-based replacement.
enum RegexKit {
    private static var cache: [String: NSRegularExpression] = [:]
    private static let lock = NSLock()

    static func regex(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
        let key = "\(options.rawValue)|\(pattern)"
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[key] { return cached }
        // Patterns are compile-time constants; a failure here is a programmer error.
        let compiled = try! NSRegularExpression(pattern: pattern, options: options)
        cache[key] = compiled
        return compiled
    }

    /// Template replacement (`$1` etc.).
    static func replace(_ pattern: String, in text: String, with template: String,
                        options: NSRegularExpression.Options = []) -> String {
        let re = regex(pattern, options)
        let range = NSRange(location: 0, length: (text as NSString).length)
        return re.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }

    /// Closure replacement. `groups[0]` is the whole match; unmatched groups are nil.
    /// Matches are visited in document order.
    static func replace(_ pattern: String, in text: String,
                        options: NSRegularExpression.Options = [],
                        using transform: ([String?]) -> String) -> String {
        let re = regex(pattern, options)
        let ns = text as NSString
        let matches = re.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }

        var result = ""
        var cursor = 0
        for match in matches {
            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let groups: [String?] = (0..<match.numberOfRanges).map { index in
                let range = match.range(at: index)
                return range.location == NSNotFound ? nil : ns.substring(with: range)
            }
            result += transform(groups)
            cursor = match.range.location + match.range.length
        }
        result += ns.substring(from: cursor)
        return result
    }

    static func matches(_ pattern: String, in text: String, options: NSRegularExpression.Options = []) -> Bool {
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex(pattern, options).firstMatch(in: text, range: range) != nil
    }

    static func firstMatch(_ pattern: String, in text: String,
                           options: NSRegularExpression.Options = []) -> [String?]? {
        let ns = text as NSString
        guard let match = regex(pattern, options).firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        return (0..<match.numberOfRanges).map { index in
            let range = match.range(at: index)
            return range.location == NSNotFound ? nil : ns.substring(with: range)
        }
    }
}

enum HTMLEntities {
    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "#39": "'",
        "nbsp": " ", "mdash": "—", "ndash": "–", "hellip": "…", "rsquo": "’", "lsquo": "‘",
        "ldquo": "“", "rdquo": "”", "copy": "©", "reg": "®", "trade": "™", "middot": "·",
        "bull": "•", "rarr": "→", "larr": "←", "times": "×", "deg": "°", "euro": "€", "pound": "£",
    ]

    static func decode(_ text: String) -> String {
        guard text.contains("&") else { return text }
        return RegexKit.replace("&(#[0-9]+|#[xX][0-9a-fA-F]+|[a-zA-Z]+);", in: text) { groups in
            let entity = groups[1] ?? ""
            if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
                if let value = UInt32(entity.dropFirst(2), radix: 16), let scalar = Unicode.Scalar(value) {
                    return String(Character(scalar))
                }
            } else if entity.hasPrefix("#") {
                if let value = UInt32(entity.dropFirst()), let scalar = Unicode.Scalar(value) {
                    return String(Character(scalar))
                }
            }
            return named[entity.lowercased()] ?? groups[0] ?? ""
        }
    }
}
