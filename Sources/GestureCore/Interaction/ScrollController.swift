import Foundation

enum ScrollIntent {
    /// The scroll pose.
    case engage
    /// No decisive reading, usually one finger wobbling: keep doing whatever was being done.
    case ambiguous
    /// A decisive different pose.
    case release
}

/// Two-finger scrolling as a joystick: where the hand is when the pose forms becomes neutral, and
/// moving away from it scrolls at a speed that grows with the distance. Holding still at an offset
/// keeps scrolling; returning to neutral stops.
///
/// Rate control suits low-precision input and long distances, and needs no clutching. The previous
/// drag-the-content model scrolled backwards on every return stroke.
///
/// Scrolling is sticky: once engaged, only a decisive different pose, or a long ambiguous spell,
/// ends it. Recorded scroll exits were mostly the pose flickering to "unknown" for a few frames.
struct ScrollController {
    private enum Axis { case horizontal, vertical }

    private(set) var active = false
    /// Content velocity in points per second.
    private(set) var velocity = Vec2.zero
    /// Hand offset from neutral along the locked axis, −1 … 1 of full deflection.
    private(set) var deflection = Vec2.zero

    private var engageSince: Double?
    /// Hand position when the pose was first seen; it becomes neutral once scrolling engages, so
    /// movement during the confirmation dwell already counts.
    private var engageAnchor: Vec2?
    private var releaseSince: Double?
    private var ambiguousSince: Double?
    private var neutral: Vec2?
    private var axis: Axis?
    private var lastTime: Double?

    mutating func reset() { self = ScrollController() }

    /// The hand was not observed: hold the content still rather than scroll on stale data.
    mutating func interrupt() {
        engageSince = nil; releaseSince = nil; ambiguousSince = nil
        lastTime = nil
        velocity = .zero; deflection = .zero
    }

    /// - Parameters:
    ///   - anchor: hand position, aspect-corrected camera units.
    ///   - palm: palm size in the same units; offsets are measured in palms.
    mutating func update(intent: ScrollIntent, anchor: Vec2, palm: Double, time: Double,
                         config: EngineConfig) -> [PointerEvent] {
        let dt = lastTime.map { max(time - $0, 1e-4) } ?? 0
        lastTime = time
        track(intent, anchor: anchor, time: time, config: config)

        var target = Vec2.zero
        deflection = .zero
        if active && intent != .release, let neutral {
            let offset = (anchor - neutral) / max(palm, 1e-4)
            if axis == nil && offset.length > config.scrollDeadzone {
                axis = abs(offset.y) >= abs(offset.x) ? .vertical : .horizontal
            }
            let along = axis == .horizontal ? offset.x : axis == .vertical ? offset.y : 0
            let amount = pow(ramp(abs(along), config.scrollDeadzone, config.scrollFullDeflection), config.scrollCurve)
            let signed = (along < 0 ? -amount : amount) * (config.invertScroll ? -1 : 1)
            deflection = axis == .horizontal ? Vec2(signed, 0) : Vec2(0, signed)
            target = deflection * config.scrollMaxSpeed
        }
        let response = active && intent != .release ? config.scrollResponseTime : config.scrollStopTime
        if dt > 0 { velocity = velocity.lerp(to: target, 1 - exp(-dt / max(response, 1e-3))) }
        if velocity.length < 5 && target == .zero { velocity = .zero }

        let delta = velocity * dt
        return delta.length > 0.05 ? [.scroll(dx: delta.x, dy: delta.y, momentum: !active)] : []
    }

    /// Keeps the content coasting to a stop when there is no pointer hand.
    mutating func coast(dt: Double, config: EngineConfig) -> [PointerEvent] {
        guard dt > 0, velocity != .zero else { return [] }
        velocity = velocity * exp(-dt / max(config.scrollStopTime, 1e-3))
        if velocity.length < 5 { velocity = .zero; return [] }
        let delta = velocity * dt
        return [.scroll(dx: delta.x, dy: delta.y, momentum: true)]
    }

    private mutating func track(_ intent: ScrollIntent, anchor: Vec2, time: Double, config: EngineConfig) {
        switch intent {
        case .engage:
            releaseSince = nil; ambiguousSince = nil
            if engageSince == nil { engageSince = time; engageAnchor = anchor }
            if !active, let since = engageSince, time - since >= config.scrollEnterTime {
                active = true; neutral = engageAnchor ?? anchor; axis = nil
            }
        case .ambiguous:
            if !active { engageSince = nil }
            if ambiguousSince == nil { ambiguousSince = time }
            if active, let since = ambiguousSince, time - since >= config.scrollAmbiguousTimeout { stop() }
        case .release:
            engageSince = nil; ambiguousSince = nil
            if active {
                if releaseSince == nil { releaseSince = time }
                if let since = releaseSince, time - since >= config.scrollExitTime { stop() }
            }
        }
    }

    private mutating func stop() {
        active = false; neutral = nil; axis = nil
        releaseSince = nil; ambiguousSince = nil
    }
}
