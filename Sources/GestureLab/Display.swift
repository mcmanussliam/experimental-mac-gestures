import Foundation
import GestureCore

/// What the user actually sees: the engine's pointer targets rendered at display rate through
/// `DisplayInterpolator`, as the app does. Measures overshoot when the hand stops (bounce), lag
/// against an unsmoothed reference, and stillness.
enum Display {
    struct Result {
        /// Pt past the resting target, one per stop.
        var overshoots: [Double]
        var lagMs: Double
        /// Pt RMS around the local mean while the target is still.
        var stillJitter: Double
    }

    static let displayHz = 120.0

    static func run(_ frames: [HandFrame], config: EngineConfig, screen: Vec2, smoothing: Double) -> Result {
        // Reference: the same engine with the pointer filter disabled and no display easing.
        var refConfig = config
        refConfig.cursorMinCutoff = 1e4; refConfig.cursorBeta = 0
        let engine = GestureEngine(config: config), reference = GestureEngine(config: refConfig)
        var interpolator = DisplayInterpolator(smoothing: smoothing)
        let fps = estimatedFPS(frames)

        var shown: [(t: Double, p: Vec2)] = []
        var targets: [(t: Double, p: Vec2?, frozen: Bool)] = []
        var refs: [(t: Double, p: Vec2?)] = []
        for (i, f) in frames.enumerated() {
            let out = engine.process(f, screen: screen)
            refs.append((f.timestamp, reference.process(f, screen: screen).cursor))
            for e in out.events {
                if case .down(_, let p, _) = e { interpolator.snap(to: p) }
                if case .up(_, let p, _) = e { interpolator.snap(to: p) }
            }
            let frozen = [EngineMode.pressed, .dragging, .scrolling, .zooming].contains(out.hud.mode)
            let pressing = out.hud.mode == .pressed || out.hud.mode == .dragging
            if out.cursor != nil || !pressing { interpolator.push(out.cursor) }
            targets.append((f.timestamp, out.cursor, frozen))
            let end = i + 1 < frames.count ? frames[i + 1].timestamp : f.timestamp + 1 / fps
            var now = f.timestamp
            while now + 1 / displayHz <= end {
                now += 1 / displayHz
                if let p = interpolator.tick(dt: 1 / displayHz) { shown.append((now, p)) }
            }
        }
        return Result(overshoots: overshoots(targets, shown), lagMs: lag(shown, refs),
                      stillJitter: stillJitter(targets, shown))
    }

    /// A stop: the target moved > 300 pt/s and then stays within 2 pt for the next 150 ms.
    /// Overshoot is how far the shown pointer passes the resting target along the approach.
    private static func overshoots(_ targets: [(t: Double, p: Vec2?, frozen: Bool)],
                                   _ shown: [(t: Double, p: Vec2)]) -> [Double] {
        var out: [Double] = []
        var j = 0
        for i in 1..<max(targets.count, 1) {
            guard let a = targets[i - 1].p, let b = targets[i].p, !targets[i].frozen else { continue }
            let dt = targets[i].t - targets[i - 1].t
            guard dt > 0, a.distance(to: b) / dt > 300 else { continue }
            let rest = targets[(i + 1)...].prefix { $0.t - targets[i].t <= 0.15 }
            guard rest.count >= 2, rest.allSatisfy({ $0.p.map { $0.distance(to: b) < 2 } ?? false }) else { continue }
            let dir = (b - a).normalized
            while j < shown.count && shown[j].t < targets[i].t { j += 1 }
            var worst = 0.0, k = j
            while k < shown.count && shown[k].t <= targets[i].t + 0.15 { worst = max(worst, (shown[k].p - b).dot(dir)); k += 1 }
            out.append(worst)
        }
        return out
    }

    /// Delay (ms) that best aligns the shown pointer with the unsmoothed reference while moving.
    private static func lag(_ shown: [(t: Double, p: Vec2)], _ refs: [(t: Double, p: Vec2?)]) -> Double {
        func ref(at t: Double) -> Vec2? {
            var lo = 0, hi = refs.count
            while lo < hi { let m = (lo + hi) / 2; if refs[m].t < t { lo = m + 1 } else { hi = m } }
            guard lo > 0, lo < refs.count, let a = refs[lo - 1].p, let b = refs[lo].p, b.distance(to: a) > 3 else { return nil }
            return a.lerp(to: b, (t - refs[lo - 1].t) / max(refs[lo].t - refs[lo - 1].t, 1e-6))
        }
        var best = (ms: 0.0, err: Double.infinity)
        for ms in stride(from: 0.0, through: 200, by: 5) {
            var sum = 0.0, n = 0
            for s in shown.enumerated() where s.offset % 4 == 0 {
                if let r = ref(at: s.element.t - ms / 1000) { sum += s.element.p.distance(to: r); n += 1 }
            }
            if n > 50, sum / Double(n) < best.err { best = (ms, sum / Double(n)) }
        }
        return best.ms
    }

    /// RMS deviation of the shown pointer from its 0.3 s local mean, where the target is still.
    private static func stillJitter(_ targets: [(t: Double, p: Vec2?, frozen: Bool)],
                                    _ shown: [(t: Double, p: Vec2)]) -> Double {
        var sum = 0.0, n = 0, lo = 0, hi = 0
        var acc = Vec2.zero
        for s in shown {
            while hi < shown.count && shown[hi].t <= s.t + 0.15 { acc += shown[hi].p; hi += 1 }
            while lo < hi && shown[lo].t < s.t - 0.15 { acc -= shown[lo].p; lo += 1 }
            let mean = acc / Double(max(hi - lo, 1))
            let span = shown[lo..<hi].map { $0.p.distance(to: mean) }.max() ?? 0
            if hi - lo > 20 && span < 15 { sum += (s.p - mean).dot(s.p - mean); n += 1 }
        }
        return n > 0 ? (sum / Double(n)).squareRoot() : .nan
    }

    private static func estimatedFPS(_ frames: [HandFrame]) -> Double {
        guard frames.count > 1 else { return 30 }
        let span = frames.last!.timestamp - frames.first!.timestamp
        return Double(frames.count - 1) / max(span, 1e-3)
    }

    static func report(_ result: Result, smoothing: Double) {
        let overshoots = result.overshoots
        let format = Score.format, percentile = Score.percentile
        print("Display (\(Int(displayHz)) Hz, smoothing \(Int(smoothing * 1000)) ms)")
        print("  stops \(overshoots.count), overshoot > 3 pt: \(overshoots.filter { $0 > 3 }.count); "
              + "overshoot p50/p95/max \(format(percentile(overshoots, 0.5), 1)) / \(format(percentile(overshoots, 0.95), 1)) / "
              + "\(format(overshoots.max() ?? 0, 1)) pt")
        print("  lag behind unsmoothed pointer \(Int(result.lagMs)) ms")
        print("  still jitter \(format(result.stillJitter, 2)) pt RMS")
    }
}
