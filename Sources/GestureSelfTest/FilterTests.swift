import Foundation
import GestureCore

/// Smoothing: the 1€ filter and display interpolation.
func filterTests() {
    test("1€ filter: converges and removes jitter") {
        var f = OneEuroFilter(minCutoff: 1, beta: 0)
        var t = 0.0, out = 0.0
        var rawVar = 0.0, filtVar = 0.0
        for i in 0..<600 {
            t += 1 / 60
            let noise = 0.01 * sin(Double(i) * 2.3999632297)
            out = f.filter(1 + noise, t: t)
            if i > 300 { rawVar += noise * noise; filtVar += (out - 1) * (out - 1) }
        }
        check(abs(out - 1) < 0.01, "converges to 1 (got \(out))")
        check(filtVar < rawVar * 0.25, "jitter variance reduced ≥4× (\(filtVar / rawVar))")
    }

    test("1€ filter: low lag on fast motion with beta") {
        var slow = OneEuroFilter(minCutoff: 1, beta: 0), fast = OneEuroFilter(minCutoff: 1, beta: 10)
        var t = 0.0, a = 0.0, b = 0.0
        for i in 0..<30 { t += 1 / 60; let x = Double(i) * 0.03; a = slow.filter(x, t: t); b = fast.filter(x, t: t) }
        let truth = 29 * 0.03
        check(abs(truth - b) < abs(truth - a) * 0.5, "beta reduces lag (\(truth - b) vs \(truth - a))")
    }

    test("Display interpolation never overshoots a stop") {
        var d = DisplayInterpolator()
        var worst = 0.0
        // 30 fps targets moving right at 1500 pt/s, then stopping at x = 500; display at 120 Hz.
        for frame in 0..<20 {
            let x = min(Double(frame) * 50, 500)
            d.push(Vec2(x, 300))
            for _ in 0..<4 { if let p = d.tick(dt: 1.0 / 120), frame >= 10 { worst = max(worst, p.x - 500) } }
        }
        check(worst <= 0.01, "never passes the resting target (overshoot \(worst) pt)")
        check(abs((d.rendered?.x ?? 0) - 500) < 0.5, "settles on it")
    }
}
