import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Proportional remapping between usable areas (SO-035).
public enum Reflow {
    public static func remap(_ frame: CGRect, from old: CGRect, to new: CGRect) -> CGRect {
        guard old.width > 0, old.height > 0 else { return frame.clamped(to: new) }
        let sx = new.width / old.width, sy = new.height / old.height
        let r = CGRect(x: new.minX + (frame.minX - old.minX) * sx,
                       y: new.minY + (frame.minY - old.minY) * sy,
                       width: frame.width * sx,
                       height: frame.height * sy)
        return r.clamped(to: new).rounded()
    }
}

/// SO-056: scenes saved across several displays, restored onto fewer.
public enum DisplayFold {
    /// The saved display a window belonged to: the one its frame overlaps most.
    public static func display(of frame: CGRect, in displays: [StageScene.Display]) -> StageScene.Display? {
        let scored = displays.map { ($0, CGRect(array: $0.frame).overlapArea(with: frame)) }
        guard let best = scored.max(by: { $0.1 < $1.1 }), best.1 > 0 else { return nil }
        return best.0
    }

    /// Moves a window from a missing display's usable area into another one, keeping its
    /// size (shrunk only if it doesn't fit) and its relative position.
    public static func fold(_ frame: CGRect, from old: CGRect, to new: CGRect) -> CGRect {
        guard old.width > 0, old.height > 0 else { return frame.clamped(to: new).rounded() }
        let w = min(frame.width, new.width), h = min(frame.height, new.height)
        let fx = (frame.minX - old.minX) / max(1, old.width - frame.width)
        let fy = (frame.minY - old.minY) / max(1, old.height - frame.height)
        let x = new.minX + max(0, min(1, fx)) * (new.width - w)
        let y = new.minY + max(0, min(1, fy)) * (new.height - h)
        return CGRect(x: x, y: y, width: w, height: h).rounded()
    }

    /// Saved displays that aren't connected now.
    public static func missing(_ saved: [StageScene.Display], connected: Set<String>) -> [StageScene.Display] {
        saved.filter { !connected.contains($0.id) }
    }
}
