import Foundation

/// Maps the hand anchor to a screen position: 1€ smoothing, then an absolute or relative
/// (accelerated) transfer function, then *damping*.
///
/// Damping (0 = follow the hand, 1 = hold still) is how every Heisenberg-effect countermeasure
/// is expressed: it rises continuously as the fingers close for a pinch, is 1 while a button is
/// pressed or a command pose is held, and briefly after a click. Whatever the pointer was held
/// back by is kept as an offset from the hand position and blended away afterwards, so there is
/// never a jump.
public struct CursorController {
    private var filter: OneEuroFilter2D
    /// Where the hand maps to, ignoring damping (screen points).
    private var live: Vec2?
    /// Relative mode: previous filtered anchor.
    private var lastMetric: Vec2?
    /// Absolute mode: output − live, decaying back to zero.
    private var offset: Vec2 = .zero
    private var holdUntil = -Double.infinity
    private var holdAnchor: Vec2?
    private var history = TimedHistory<Vec2>(horizon: 1.0)
    private var lastT: Double?
    private var mode: CursorMode = .absolute
    /// Relative mode: palm scale smoothed over ~0.5 s, to make motion distance-independent.
    private var palm: Double?

    public private(set) var position: Vec2?
    /// While true the offset doesn't decay, so a drag tracks the hand exactly.
    public var lockOffset = false

    public init(config: EngineConfig) {
        filter = OneEuroFilter2D(minCutoff: config.cursorMinCutoff, beta: config.cursorBeta)
    }

    public mutating func reset() {
        filter.reset(); live = nil; lastMetric = nil; offset = .zero
        history.removeAll(); position = nil; lastT = nil; lockOffset = false; holdUntil = -.infinity
        holdAnchor = nil; palm = nil
    }

    /// The anchor jumped discontinuously (hand re-acquired elsewhere): restart smoothing and,
    /// in relative mode, don't count the jump as motion. The pointer stays where it is.
    public mutating func rebase() {
        filter.reset(); lastMetric = nil
    }

    /// Keep the pointer still until `t` (e.g. after a click, so a double-click lands).
    public mutating func hold(until t: Double) {
        holdUntil = max(holdUntil, t)
        holdAnchor = filter.value
    }

    /// Move the pointer back to where it was at time `t`.
    public mutating func rewind(to t: Double) {
        guard let p = history.value(atOrBefore: t) else { return }
        position = p
        if mode == .relative { live = p } else if let l = live { offset = p - l }
    }

    public mutating func update(anchor: Vec2, time t: Double, aspect: Double, screen: Vec2,
                                externalMouse: Vec2?, damping requested: Double, config: EngineConfig,
                                palmScale: Double = 0.12, dragging: Bool = false) -> Vec2 {
        let metric = filter.filter(Vec2(anchor.x * aspect, anchor.y), t: t)
        let dt = lastT.map { max(t - $0, 1e-4) } ?? 0
        lastT = t
        mode = config.cursorMode
        if let holdAnchor, metric.distance(to: holdAnchor) > config.postClickMovePalms * max(palmScale, 1e-4) {
            holdUntil = -.infinity
        }
        let damping = t < holdUntil && !dragging ? 1 : clamp01(requested)
        func clampToScreen(_ p: Vec2) -> Vec2 { Vec2(clamp(p.x, 0, screen.x), clamp(p.y, 0, screen.y)) }

        let out: Vec2
        switch config.cursorMode {
        case .absolute:
            let w = config.activeRegionWidth
            let h = w * aspect / (screen.x / max(screen.y, 1))
            let nx = (metric.x / aspect - (config.activeRegionCenterX - w / 2)) / w
            let ny = (metric.y - (config.activeRegionCenterY - h / 2)) / h
            let l = Vec2(clamp01(nx) * screen.x, clamp01(ny) * screen.y)
            live = l
            if !lockOffset && dt > 0 {
                offset = offset * exp(-dt / max(config.catchUpTau, 1e-3))
                if offset.length < 0.5 { offset = .zero }
            }
            let desired = l + offset
            let prev = position ?? desired
            out = clampToScreen(prev + (desired - prev) * (1 - damping))
            offset = out - l

        case .relative:
            // Adopt the real mouse position if something else (a trackpad) moved it.
            if let m = externalMouse, let p = position, m.distance(to: p) > 3 { live = m }
            var l = live ?? externalMouse ?? screen / 2
            if dt > 0 { palm = palm.map { $0 + (palmScale - $0) * (1 - exp(-dt / 0.5)) } ?? palmScale }
            if let prev = lastMetric, dt > 0 {
                // A hand twice as far away looks half the size and moves half as far in the image
                // for the same movement, so motion is measured in palms, scaled to a typical palm.
                let distance = clamp(config.relativeReferencePalm / max(palm ?? palmScale, 1e-4), 0.5, 2)
                // Gain from the filter's smoothed velocity: a per-frame speed estimate is
                // dominated by detector noise and would make the gain itself flicker.
                let speed = filter.velocity.length * distance
                let gain = dragging ? config.dragGain : config.relativeGainMin + (config.relativeGainMax - config.relativeGainMin)
                    * ramp(speed, 0.02, config.relativeGainSpeed)
                l = clampToScreen(l + (metric - prev) * distance * gain * screen.y * (1 - damping))
            }
            live = l
            out = l
        }
        lastMetric = metric
        position = out
        history.append(out, at: t)
        return out
    }
}
