import Foundation

/// Turns camera-rate pointer targets into display-rate positions.
///
/// Webcams typically deliver 30 fps while displays refresh at 60–120 Hz, so posting one move per
/// camera frame makes the pointer step visibly. Each display tick eases toward the latest target
/// with time constant `smoothing`.
///
/// It deliberately does not extrapolate. Dead-reckoning along the last velocity was measured on
/// recorded sessions: almost every stop overshot (p50 20–50 pt, up to 430 pt) and sprang back,
/// because a stop is only visible one camera frame later. Removing it cost ~5 ms of lag, which the
/// pointer filter wins back. Pure, so replay can measure exactly what is shown.
public struct DisplayInterpolator: Sendable {
    /// Easing time constant toward the target (s).
    public var smoothing: Double

    private var target: Vec2?
    public private(set) var rendered: Vec2?

    public init(smoothing: Double = 0.008) { self.smoothing = smoothing }

    public var hasTarget: Bool { target != nil }

    public mutating func reset() { target = nil; rendered = nil }

    /// A new engine target; nil when there is no pointer hand.
    public mutating func push(_ p: Vec2?) {
        target = p
        if p == nil { rendered = nil }
    }

    /// Jump straight to `p` (button presses land exactly where the engine decided).
    public mutating func snap(to p: Vec2) { rendered = p; target = p }

    /// Advances one display tick; returns the position to show.
    public mutating func tick(dt: Double) -> Vec2? {
        guard let tgt = target else { return nil }
        let cur = rendered ?? tgt
        let next = cur + (tgt - cur) * (1 - exp(-dt / max(smoothing, 1e-4)))
        rendered = next
        return next
    }
}
