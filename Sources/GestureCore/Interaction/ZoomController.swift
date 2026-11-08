import Foundation

/// Two-hand zoom: once both hands pinch, spreading them apart or squeezing them together fires
/// one zoom step per `zoomStep` change in their distance.
struct ZoomController {
    private var base: Double?

    var active: Bool { base != nil }

    mutating func reset() { base = nil }

    /// - Parameters:
    ///   - distance: between the two hands' pinch points (aspect-corrected), when both pinch.
    ///   - eitherPinching: zoom ends only when both hands have let go.
    ///   - canStart: false while the pointer hand is busy (pressing).
    mutating func update(distance: Double?, eitherPinching: Bool, canStart: Bool, config: EngineConfig) -> GestureCommand? {
        guard let d = distance, canStart || active else {
            if active && !eitherPinching { base = nil }
            return nil
        }
        guard let b = base else { base = d; return nil }
        if d / b >= config.zoomStep { base = b * config.zoomStep; return .zoomIn }
        if d / b <= 1 / config.zoomStep { base = b / config.zoomStep; return .zoomOut }
        return nil
    }
}
