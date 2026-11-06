import Foundation

/// SO-060: when to keep, skip and drop automatic snapshots of the desk.
public enum RewindPolicy {
    public static let interval: TimeInterval = 15 * 60
    public static let keep: TimeInterval = 7 * 24 * 60 * 60
    public static let maxBytes = 20 * 1024 * 1024

    public struct Entry: Sendable, Equatable {
        public var date: Date
        public var bytes: Int
        public var fingerprint: String?
        public init(date: Date, bytes: Int, fingerprint: String? = nil) {
            self.date = date; self.bytes = bytes; self.fingerprint = fingerprint
        }
    }

    /// A snapshot identical to the latest one is skipped.
    public static func shouldSave(_ fingerprint: String, latest: String?) -> Bool { fingerprint != latest }

    /// Indexes of entries to delete: older than 7 days, then the oldest until the total fits in 20 MB.
    public static func prune(_ entries: [Entry], now: Date, maxBytes: Int = maxBytes, keep: TimeInterval = keep) -> [Int] {
        let order = entries.indices.sorted { entries[$0].date < entries[$1].date }
        var drop = Set(order.filter { now.timeIntervalSince(entries[$0].date) > keep })
        var total = order.filter { !drop.contains($0) }.reduce(0) { $0 + entries[$1].bytes }
        for i in order where total > maxBytes && !drop.contains(i) {
            drop.insert(i)
            total -= entries[i].bytes
        }
        return drop.sorted()
    }

    /// The snapshot to go back to for "rewind to `date`": the latest one at or before it.
    /// Without a date, the latest one older than `now - 60s` (so "rewind" goes back, not nowhere).
    public static func target(for date: Date?, in dates: [Date], now: Date) -> Int? {
        let limit = date ?? now.addingTimeInterval(-60)
        return dates.indices.filter { dates[$0] <= limit }.max { dates[$0] < dates[$1] }
    }

    /// File names sort by time: 2026-11-06T09-15-00Z.stagescene
    public static func fileName(for date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date).replacingOccurrences(of: ":", with: "-") + "." + StageScene.fileExtension
    }

    public static func date(fromFileName name: String) -> Date? {
        let base = name.replacingOccurrences(of: "." + StageScene.fileExtension, with: "")
        guard let t = base.firstIndex(of: "T") else { return nil }
        let fixed = base[..<t] + base[t...].replacingOccurrences(of: "-", with: ":")
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: String(fixed))
    }
}
