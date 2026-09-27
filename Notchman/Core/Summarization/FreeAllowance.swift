import Foundation

/// The Free plan's TL;DRs: 10 a month, made on the iPhone.
///
/// On-device TL;DRs cost nothing to run, but the plan still has a limit. The
/// count lives in the Keychain, so deleting and reinstalling the app doesn't
/// reset it.
struct FreeAllowance {
    static let monthlyLimit = 10

    /// Where the "yyyy-MM:count" record is kept. Swappable for tests.
    var load: () -> String? = { KeychainStore.string(for: "free-tldrs") }
    var save: (String) -> Void = { KeychainStore.set($0, for: "free-tldrs") }
    var calendar = Calendar.current

    func usage(now: Date = .now) -> CloudUsage {
        let used = count(in: month(now))
        return CloudUsage(plan: "free", used: used, limit: Self.monthlyLimit,
                          remaining: max(0, Self.monthlyLimit - used))
    }

    /// Takes one TL;DR from this month, or throws `CloudError.quotaExceeded`.
    @discardableResult
    func consume(now: Date = .now) throws -> CloudUsage {
        let key = month(now)
        let used = count(in: key)
        guard used < Self.monthlyLimit else { throw CloudError.quotaExceeded(usage(now: now)) }
        save("\(key):\(used + 1)")
        return usage(now: now)
    }

    /// Gives back a TL;DR that failed, so users aren't charged for errors.
    func refund(now: Date = .now) {
        let key = month(now)
        save("\(key):\(max(0, count(in: key) - 1))")
    }

    /// When this month's allowance comes back.
    func resetDate(now: Date = .now) -> Date {
        let start = calendar.dateInterval(of: .month, for: now)?.start ?? now
        return calendar.date(byAdding: .month, value: 1, to: start) ?? now
    }

    private func month(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    private func count(in month: String) -> Int {
        guard let record = load() else { return 0 }
        let parts = record.split(separator: ":")
        guard parts.count == 2, parts[0] == month else { return 0 }
        return Int(parts[1]) ?? 0
    }
}
