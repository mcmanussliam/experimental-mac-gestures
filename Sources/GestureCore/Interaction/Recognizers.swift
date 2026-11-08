import Foundation

public enum SwipeDirection: String, Codable, Sendable { case left, right, up, down
    var opposite: SwipeDirection {
        switch self { case .left: return .right; case .right: return .left; case .up: return .down; case .down: return .up }
    }
}

/// Detects fast open-palm strokes. Distances are in palms, so it works at any range.
/// The return stroke (hand coming back) is suppressed for `swipeOppositeSuppress` seconds.
struct SwipeRecognizer {
    private struct Sample { var center: Vec2; var palm: Double; var open: Bool }
    private var history = TimedHistory<Sample>(horizon: 0.6)
    private var lastFire: (t: Double, dir: SwipeDirection)?

    /// Time at which the stroke that just fired started (for cursor rewind).
    private(set) var lastStrokeStart: Double = 0

    mutating func reset() { history.removeAll() }

    /// `center` is aspect-corrected metric palm centre.
    mutating func update(center: Vec2, palm: Double, open: Bool, eligible: Bool, time t: Double,
                         config: EngineConfig) -> SwipeDirection? {
        history.append(Sample(center: center, palm: palm, open: open), at: t)
        guard eligible else { return nil }
        if let lf = lastFire, t - lf.t < config.swipeCooldown { return nil }

        let window = history.items.filter { t - $0.t <= config.swipeWindow }
        guard window.count >= 3, let first = window.first, let last = window.last else { return nil }
        let palm = window.map(\.v.palm).reduce(0, +) / Double(window.count)
        guard palm > 1e-4 else { return nil }

        let openFrac = Double(window.filter { $0.v.open }.count) / Double(window.count)
        guard openFrac >= config.swipeMinOpenFraction else { return nil }

        let d = (last.v.center - first.v.center) / palm
        var peak = 0.0
        for k in 1..<window.count {
            let dt = max(window[k].t - window[k - 1].t, 1e-3)
            peak = max(peak, (window[k].v.center - window[k - 1].v.center).length / palm / dt)
        }
        guard d.length >= config.swipeMinDistance, peak >= config.swipeMinSpeed else { return nil }

        let dir: SwipeDirection
        if abs(d.x) >= abs(d.y) * config.swipeAxisRatio { dir = d.x > 0 ? .right : .left }
        else if abs(d.y) >= abs(d.x) * config.swipeAxisRatio { dir = d.y > 0 ? .down : .up }
        else { return nil }

        if let lf = lastFire, lf.dir == dir.opposite, t - lf.t < config.swipeOppositeSuppress { return nil }
        lastFire = (t, dir)
        lastStrokeStart = first.t
        history.removeAll()
        return dir
    }
}

/// Fires once after a committed pose has been held for `holdTime`.
struct PoseHoldRecognizer {
    private var firedFor: String?

    mutating func reset() { firedFor = nil }

    mutating func update(poseName: String, since: Double, eligible: Bool, holdTime: Double, time t: Double) -> Bool {
        guard eligible else { firedFor = nil; return false }
        if firedFor != nil && firedFor != poseName { firedFor = nil }
        guard firedFor == nil, t - since >= holdTime else { return false }
        firedFor = poseName
        return true
    }
}
