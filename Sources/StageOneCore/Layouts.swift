import Foundation

/// Per-stage layouts (SO-040).
public enum LayoutKind: String, Codable, Sendable, CaseIterable {
    case free, halves, focus, thirds, grid

    public var title: String {
        switch self {
        case .free: return "Free"
        case .halves: return "Halves"
        case .focus: return "Main + side"
        case .thirds: return "Thirds"
        case .grid: return "Grid"
        }
    }

    /// Accepts CLI spellings like "main", "main+side", "split".
    public init?(loose: String) {
        let s = loose.lowercased().replacingOccurrences(of: " ", with: "")
        switch s {
        case "free": self = .free
        case "halves", "half", "split": self = .halves
        case "focus", "main", "main+side", "mainside": self = .focus
        case "thirds", "third": self = .thirds
        case "grid": self = .grid
        default: return nil
        }
    }
}

public enum LayoutEngine {
    public static let gap: CGFloat = 8

    /// Frames for `count` windows in `area`. Returns nil for `.free` (keep frames).
    public static func frames(for kind: LayoutKind, count: Int, in area: CGRect, gap: CGFloat = gap) -> [CGRect]? {
        guard count > 0 else { return [] }
        let a = area.insetBy(dx: gap, dy: gap)
        switch kind {
        case .free:
            return nil
        case .halves:
            if count == 1 { return [a] }
            return columns(a, weights: [1, 1], gap: gap, count: count)
        case .thirds:
            if count == 1 { return [a] }
            return columns(a, weights: [1, 1, 1], gap: gap, count: count)
        case .focus:
            if count == 1 { return [a] }
            let mainW = ((a.width - gap) * 0.62).rounded()
            let main = CGRect(x: a.minX, y: a.minY, width: mainW, height: a.height)
            let side = CGRect(x: main.maxX + gap, y: a.minY, width: a.width - mainW - gap, height: a.height)
            return [main] + rows(side, count: count - 1, gap: gap)
        case .grid:
            let cols = Int(ceil(sqrt(Double(count))))
            let rowsN = Int(ceil(Double(count) / Double(cols)))
            let w = (a.width - gap * CGFloat(cols - 1)) / CGFloat(cols)
            let h = (a.height - gap * CGFloat(rowsN - 1)) / CGFloat(rowsN)
            return (0..<count).map { i in
                let c = i % cols, r = i / cols
                return CGRect(x: a.minX + CGFloat(c) * (w + gap), y: a.minY + CGFloat(r) * (h + gap), width: w, height: h).rounded()
            }
        }
    }

    /// Columns for the first N slots; extra windows stack in the last column.
    private static func columns(_ a: CGRect, weights: [CGFloat], gap: CGFloat, count: Int) -> [CGRect] {
        let n = min(weights.count, count)
        let w = (a.width - gap * CGFloat(n - 1)) / CGFloat(n)
        var cols = (0..<n).map { i in CGRect(x: a.minX + CGFloat(i) * (w + gap), y: a.minY, width: w, height: a.height).rounded() }
        if count > n {
            let last = cols.removeLast()
            cols += rows(last, count: count - n + 1, gap: gap)
        }
        return cols
    }

    private static func rows(_ a: CGRect, count: Int, gap: CGFloat) -> [CGRect] {
        guard count > 0 else { return [] }
        let h = (a.height - gap * CGFloat(count - 1)) / CGFloat(count)
        return (0..<count).map { i in CGRect(x: a.minX, y: a.minY + CGFloat(i) * (h + gap), width: a.width, height: h).rounded() }
    }
}

/// Edge snapping (SO-041).
public enum SnapZone: Sendable, Equatable {
    case leftHalf, rightHalf, fill

    /// Pointer within `threshold` of an edge of the usable area picks a zone.
    public static func zone(for point: CGPoint, in usable: CGRect, threshold: CGFloat = 6) -> SnapZone? {
        guard usable.insetBy(dx: -threshold * 4, dy: -threshold * 4).contains(point) else { return nil }
        if point.x <= usable.minX + threshold { return .leftHalf }
        if point.x >= usable.maxX - threshold { return .rightHalf }
        if point.y <= usable.minY + threshold { return .fill }
        return nil
    }

    public func frame(in usable: CGRect, gap: CGFloat = LayoutEngine.gap) -> CGRect {
        let a = usable.insetBy(dx: gap, dy: gap)
        let half = (a.width - gap) / 2
        switch self {
        case .leftHalf: return CGRect(x: a.minX, y: a.minY, width: half, height: a.height).rounded()
        case .rightHalf: return CGRect(x: a.minX + half + gap, y: a.minY, width: half, height: a.height).rounded()
        case .fill: return a.rounded()
        }
    }
}
