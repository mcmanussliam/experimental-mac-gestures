import Foundation

/// Minimal 2D vector. Kept separate from CoreGraphics so GestureCore stays platform-neutral.
public struct Vec2: Equatable, Codable, Sendable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    public static let zero = Vec2(0, 0)

    public static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
    public static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }
    public static func * (a: Vec2, s: Double) -> Vec2 { Vec2(a.x * s, a.y * s) }
    public static func * (s: Double, a: Vec2) -> Vec2 { Vec2(a.x * s, a.y * s) }
    public static func / (a: Vec2, s: Double) -> Vec2 { Vec2(a.x / s, a.y / s) }
    public static func += (a: inout Vec2, b: Vec2) { a = a + b }
    public static func -= (a: inout Vec2, b: Vec2) { a = a - b }

    public var length: Double { (x * x + y * y).squareRoot() }
    public func distance(to o: Vec2) -> Double { (self - o).length }
    public func dot(_ o: Vec2) -> Double { x * o.x + y * o.y }
    public func cross(_ o: Vec2) -> Double { x * o.y - y * o.x }
    public var normalized: Vec2 { let l = length; return l > 1e-12 ? self / l : .zero }
    public func rotated(by a: Double) -> Vec2 {
        let c = cos(a), s = sin(a)
        return Vec2(x * c - y * s, x * s + y * c)
    }
    public func lerp(to o: Vec2, _ t: Double) -> Vec2 { self + (o - self) * t }
}

@inlinable func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(max(v, lo), hi) }
@inlinable func clamp01(_ v: Double) -> Double { clamp(v, 0, 1) }

/// Linear remap of `v` from [a,b] to [0,1], clamped.
@inlinable func ramp(_ v: Double, _ a: Double, _ b: Double) -> Double { clamp01((v - a) / (b - a)) }

/// Fixed-capacity time-indexed history used for rewinds and windowed velocity.
public struct TimedHistory<T> {
    public private(set) var items: [(t: Double, v: T)] = []
    public let horizon: Double

    public init(horizon: Double) { self.horizon = horizon }

    public mutating func append(_ v: T, at t: Double) {
        items.append((t, v))
        let cutoff = t - horizon
        if let firstKeep = items.firstIndex(where: { $0.t >= cutoff }), firstKeep > 0 {
            items.removeFirst(firstKeep)
        }
    }

    /// Latest sample at or before `t` (falls back to the oldest sample).
    public func value(atOrBefore t: Double) -> T? {
        guard !items.isEmpty else { return nil }
        for item in items.reversed() where item.t <= t { return item.v }
        return items.first?.v
    }

    public var last: (t: Double, v: T)? { items.last }
    public var first: (t: Double, v: T)? { items.first }
    public mutating func removeAll() { items.removeAll(keepingCapacity: true) }
}
