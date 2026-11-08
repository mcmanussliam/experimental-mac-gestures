import Foundation

/// 1€ filter (Casiez, Roussel & Vogel, CHI 2012): an adaptive low-pass whose cutoff
/// increases with signal speed: low jitter when still, low lag when moving.
public struct OneEuroFilter: Sendable {
    public var minCutoff: Double
    public var beta: Double
    public var dCutoff: Double

    private var x: Double?
    private var dx: Double = 0
    private var lastT: Double?

    public init(minCutoff: Double, beta: Double, dCutoff: Double = 1.0) {
        self.minCutoff = minCutoff; self.beta = beta; self.dCutoff = dCutoff
    }

    @inline(__always) private static func alpha(_ cutoff: Double, _ dt: Double) -> Double {
        let tau = 1.0 / (2 * .pi * cutoff)
        return 1.0 / (1.0 + tau / dt)
    }

    public var value: Double? { x }
    public var derivative: Double { dx }

    public mutating func reset() { x = nil; dx = 0; lastT = nil }

    public mutating func filter(_ v: Double, t: Double) -> Double {
        guard let px = x, let lt = lastT else {
            x = v; lastT = t; dx = 0
            return v
        }
        let dt = max(t - lt, 1e-4)
        lastT = t
        let rawDx = (v - px) / dt
        dx += Self.alpha(dCutoff, dt) * (rawDx - dx)
        let cutoff = minCutoff + beta * abs(dx)
        let nx = px + Self.alpha(cutoff, dt) * (v - px)
        x = nx
        return nx
    }
}

/// 2D 1€ filter driven by the joint speed (so x and y share one adaptive cutoff,
/// which avoids diagonal-motion artefacts of independent per-axis filters).
public struct OneEuroFilter2D: Sendable {
    public var minCutoff: Double
    public var beta: Double
    public var dCutoff: Double

    private var x: Vec2?
    private var dx: Vec2 = .zero
    private var lastT: Double?

    public init(minCutoff: Double, beta: Double, dCutoff: Double = 1.0) {
        self.minCutoff = minCutoff; self.beta = beta; self.dCutoff = dCutoff
    }

    public var value: Vec2? { x }
    /// Smoothed velocity (units/s).
    public var velocity: Vec2 { dx }

    public mutating func reset() { x = nil; dx = .zero; lastT = nil }

    public mutating func filter(_ v: Vec2, t: Double) -> Vec2 {
        guard let px = x, let lt = lastT else {
            x = v; lastT = t; dx = .zero
            return v
        }
        let dt = max(t - lt, 1e-4)
        lastT = t
        let rawDx = (v - px) / dt
        let ad = 1.0 / (1.0 + 1.0 / (2 * .pi * dCutoff * dt))
        dx = dx + (rawDx - dx) * ad
        let cutoff = minCutoff + beta * dx.length
        let a = 1.0 / (1.0 + 1.0 / (2 * .pi * cutoff * dt))
        let nx = px + (v - px) * a
        x = nx
        return nx
    }
}
