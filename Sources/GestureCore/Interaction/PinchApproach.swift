import Foundation

/// A closing motion can briefly steady a click, but a half-closed resting hand must still
/// point normally. After the window expires, require reopening before damping again.
///
/// The approach is detected from closing *speed* (palms/s), so it behaves the same at 15, 30 or
/// 60 fps, and slow drift of a relaxed hand does not make the pointer sticky.
struct PinchApproach {
    private enum State { case ready, steadying(Double), expired }
    private var state: State = .ready
    private var previous: (ratio: Double, t: Double)?
    private(set) var steadying = false

    mutating func reset() { self = PinchApproach() }

    mutating func update(ratio: Double, eligible: Bool, time t: Double, config: EngineConfig) -> Double {
        defer { previous = ratio.isFinite ? (ratio, t) : nil }
        steadying = false
        guard eligible, ratio.isFinite, ratio < config.pinchDampStart else {
            state = .ready
            return 0
        }
        switch state {
        case .ready:
            if let p = previous, t > p.t, (p.ratio - ratio) / (t - p.t) > config.pinchApproachSpeed { state = .steadying(t) }
        case .steadying(let since):
            if t - since > config.pinchIntentTime { state = .expired }
        case .expired: break
        }
        if case .steadying = state {
            steadying = true
            let progress = ramp(config.pinchDampStart - ratio, 0, max(config.pinchDampStart - config.pinchEnter, 1e-4))
            return progress * progress
        }
        return 0
    }
}
