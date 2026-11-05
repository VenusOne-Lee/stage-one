import Foundation

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
