import Foundation
import GestureCore

/// Two simple pointer controls for Settings, each mapped onto several engine parameters.
extension AppModel {
    /// 0 … 1. Relative mode: acceleration curve gain. Direct mode: size of the hand area.
    var pointerSpeed: Double {
        get {
            switch config.engine.cursorMode {
            case .relative: return clampedToUnit((config.engine.relativeGainMax - 2) / 6)
            case .absolute: return clampedToUnit((0.75 - config.engine.activeRegionWidth) / 0.45)
            }
        }
        set {
            switch config.engine.cursorMode {
            case .relative:
                config.engine.relativeGainMax = 2 + 6 * newValue
                config.engine.relativeGainMin = 0.225 * config.engine.relativeGainMax
            case .absolute:
                config.engine.activeRegionWidth = 0.75 - 0.45 * newValue
            }
        }
    }

    /// 0 … 1: more steadiness = lower 1€ minimum cutoff (less jitter, a little more lag).
    var steadiness: Double {
        get { clampedToUnit(log(config.engine.cursorMinCutoff / 2.4) / log(0.15)) }
        set { config.engine.cursorMinCutoff = 2.4 * pow(0.15, newValue) }
    }

    private func clampedToUnit(_ value: Double) -> Double { min(max(value, 0), 1) }
}
