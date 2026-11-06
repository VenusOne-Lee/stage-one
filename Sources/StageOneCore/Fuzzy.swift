import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Small fuzzy matcher for the ⌘K palette, Alfred and the CLI.
public enum Fuzzy {
    /// Returns a score (higher is better) or nil when `query` isn't a subsequence of `text`.
    public static func score(_ query: String, in text: String) -> Double? {
        let q = Array(query.lowercased()), t = Array(text.lowercased())
        if q.isEmpty { return 0 }
        var score = 0.0, ti = 0, last = -1, streak = 0
        for c in q {
            var found = false
            while ti < t.count {
                if t[ti] == c {
                    streak = (last == ti - 1) ? streak + 1 : 1
                    score += 1 + Double(streak) * 0.5
                    if ti == 0 || t[ti - 1] == " " { score += 2 }
                    last = ti; ti += 1; found = true
                    break
                }
                ti += 1
            }
            if !found { return nil }
        }
        return score - Double(t.count) * 0.01
    }

    public static func rank<T>(_ items: [T], query: String, key: (T) -> String) -> [T] {
        items.compactMap { i in score(query, in: key(i)).map { (i, $0) } }.sorted { $0.1 > $1.1 }.map(\.0)
    }
}

/// SO-024: the strip's search field, shown once there are more groups than visible slots.
public enum StripSearch {
    /// More groups than this and the strip shows a search field.
    public static let threshold = 8

    /// Groups whose name or one of whose apps matches `query`, in strip order.
    public static func filter(_ groups: [StageGroup], query: String, apps: (StageGroup) -> [String]) -> [StageGroup] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return groups }
        return groups.filter { g in
            Fuzzy.score(q, in: g.name) != nil || apps(g).contains { Fuzzy.score(q, in: $0) != nil }
        }
    }
}
