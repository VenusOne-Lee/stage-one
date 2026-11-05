import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Window identity matching across launches (SO-013).
///
/// Each saved window is scored against live windows by bundle ID, document, title
/// similarity and order. Matches below `threshold` are left unmatched rather than guessed.
public enum IdentityMatcher {
    public static let threshold = 0.6

    public struct Match: Sendable, Equatable {
        public var savedIndex: Int
        public var windowID: UInt32
        public var confidence: Double
    }

    public struct Result: Sendable, Equatable {
        public var matches: [Match]
        /// Indices of saved windows with no confident live match.
        public var unmatchedSaved: [Int]
        /// Live windows nobody claimed.
        public var unmatchedLive: [UInt32]
    }

    public static func score(saved: StageScene.Window, savedOrder: Int, savedCountForApp: Int,
                             live: WindowSnapshot, liveOrder: Int, liveCountForApp: Int) -> Double {
        score(saved: saved, savedOrder: savedOrder, savedCountForApp: savedCountForApp,
              live: live, liveOrder: liveOrder, liveCountForApp: liveCountForApp,
              titleSimilarity: { similarity(normalize(saved.title), normalize(live.title)) })
    }

    /// `titleSimilarity` is only evaluated when the document doesn't decide the match, so
    /// `match` can pass in a version that reuses titles normalised once per window (SO-130).
    static func score(saved: StageScene.Window, savedOrder: Int, savedCountForApp: Int,
                      live: WindowSnapshot, liveOrder: Int, liveCountForApp: Int,
                      titleSimilarity: () -> Double) -> Double {
        guard saved.bundleId == live.bundleID else { return 0 }
        var s = 0.35 // same app
        if let d = saved.document, let ld = live.document, !d.isEmpty {
            if d == ld { return 1.0 }
            s -= 0.2
        }
        let sim = titleSimilarity()
        s += 0.45 * sim
        // Single window for the app on both sides: very likely the same one.
        if savedCountForApp == 1 && liveCountForApp == 1 { s += 0.3 }
        if savedOrder == liveOrder { s += 0.1 }
        // Similar size hints at the same window.
        let sf = saved.cgFrame, lf = live.frame
        if sf.width > 0, lf.width > 0 {
            let ratio = min(sf.width, lf.width) / max(sf.width, lf.width) * min(sf.height, lf.height) / max(sf.height, lf.height)
            s += 0.1 * Double(ratio)
        }
        return min(1, max(0, s))
    }

    /// Greedy best-first assignment over all candidate pairs.
    public static func match(saved: [StageScene.Window], live: [WindowSnapshot], threshold: Double = threshold) -> Result {
        var savedOrder: [Int] = [], savedCount: [String: Int] = [:]
        for w in saved { savedOrder.append(savedCount[w.bundleId, default: 0]); savedCount[w.bundleId, default: 0] += 1 }
        var liveOrder: [Int] = [], liveCount: [String: Int] = [:]
        for w in live { liveOrder.append(liveCount[w.bundleID, default: 0]); liveCount[w.bundleID, default: 0] += 1 }

        // Normalise and tokenise each title once, and only compare windows of the same app
        // (SO-130: keeps 200 windows well under the 50ms budget).
        let savedTitles = saved.map { Title($0.title) }
        let liveTitles = live.map { Title($0.title) }
        var liveByApp: [String: [Int]] = [:]
        for (j, l) in live.enumerated() { liveByApp[l.bundleID, default: []].append(j) }

        var pairs: [(Int, Int, Double)] = []
        for (i, s) in saved.enumerated() {
            for j in liveByApp[s.bundleId] ?? [] {
                let l = live[j]
                let c = score(saved: s, savedOrder: savedOrder[i], savedCountForApp: savedCount[s.bundleId] ?? 0,
                              live: l, liveOrder: liveOrder[j], liveCountForApp: liveCount[l.bundleID] ?? 0,
                              titleSimilarity: { savedTitles[i].similarity(to: liveTitles[j]) })
                if c >= threshold { pairs.append((i, j, c)) }
            }
        }
        pairs.sort { $0.2 != $1.2 ? $0.2 > $1.2 : ($0.0, $0.1) < ($1.0, $1.1) }
        var usedS = Set<Int>(), usedL = Set<Int>(), matches: [Match] = []
        for (i, j, c) in pairs where !usedS.contains(i) && !usedL.contains(j) {
            usedS.insert(i); usedL.insert(j)
            matches.append(Match(savedIndex: i, windowID: live[j].windowID, confidence: c))
        }
        matches.sort { $0.savedIndex < $1.savedIndex }
        return Result(matches: matches,
                      unmatchedSaved: saved.indices.filter { !usedS.contains($0) },
                      unmatchedLive: live.indices.filter { !usedL.contains($0) }.map { live[$0].windowID })
    }

    /// Drops app-name suffixes, counters and badge prefixes like "(3) ".
    public static func normalize(_ title: String) -> String {
        var t = title.lowercased()
        if let r = t.range(of: #"^\(\d+\)\s*"#, options: .regularExpression) { t.removeSubrange(r) }
        for sep in [" — ", " - ", " – "] {
            // Keep the most specific part (the first) when the title ends in an app or profile name.
            let parts = t.components(separatedBy: sep)
            if parts.count > 2 { t = parts.dropLast().joined(separator: sep) }
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Token Jaccard blended with a prefix bonus. 0...1.
    public static func similarity(_ a: String, _ b: String) -> Double {
        similarity(a, tokens(a), b, tokens(b))
    }

    static func tokens(_ s: String) -> Set<String> {
        Set(s.split { !$0.isLetter && !$0.isNumber }.map(String.init))
    }

    static func similarity(_ a: String, _ ta: Set<String>, _ b: String, _ tb: Set<String>) -> Double {
        if a == b { return 1 }
        if a.isEmpty || b.isEmpty { return 0 }
        guard !ta.isEmpty || !tb.isEmpty else { return 0 }
        let j = Double(ta.intersection(tb).count) / Double(ta.union(tb).count)
        let prefix = Double(zip(a, b).prefix { $0 == $1 }.count) / Double(max(a.count, b.count))
        return min(1, 0.75 * j + 0.25 * prefix)
    }

    /// A title normalised and tokenised once.
    struct Title {
        let text: String
        let tokens: Set<String>

        init(_ raw: String) {
            text = IdentityMatcher.normalize(raw)
            tokens = IdentityMatcher.tokens(text)
        }

        func similarity(to other: Title) -> Double {
            IdentityMatcher.similarity(text, tokens, other.text, other.tokens)
        }
    }
}
