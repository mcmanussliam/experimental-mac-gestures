import Foundation
import GestureCore

/// Click, double-click, right click, drag and release robustness.
func clickTests() {
    test("Pinch tap → instant left click at the pre-pinch position") {
        let d = Driver()
        d.run([SyntheticHand()], seconds: 0.5)
        let before = d.last.cursor!
        for g in stride(from: 1.0, through: 0.0, by: -0.2) { d.step([pinched(g)]) }
        d.run([pinched(0)], seconds: 0.08)
        for g in stride(from: 0.0, through: 1.0, by: 0.25) { d.step([pinched(g)]) }
        d.run([SyntheticHand()], seconds: 0.3)
        check(d.downs.count == 1 && d.ups.count == 1, "one down/up (\(d.downs.count)/\(d.ups.count))")
        if case .down(let b, let p, let n)? = d.downs.first {
            check(b == .left && n == 1, "left, clickCount 1")
            check(p.distance(to: before) < 4, "click lands where pointer was before pinch (Δ=\(p.distance(to: before)))")
        }
        check(d.drags.isEmpty, "no drag")
    }

    test("A click is instant: down and up in the same frame, however long the pinch") {
        let d = Driver()
        d.run([SyntheticHand()], seconds: 0.4)
        let outs = d.run([pinched(0)], seconds: 1.0)
        let clickFrames = outs.filter { o in
            o.events.contains { if case .down = $0 { return true }; return false } &&
            o.events.contains { if case .up = $0 { return true }; return false }
        }
        check(clickFrames.count == 1 && d.downs.count == 1 && d.ups.count == 1, "one instant click during a 1 s pinch")
    }

    test("Two quick pinches → double click") {
        let d = Driver()
        d.run([SyntheticHand()], seconds: 0.4)
        for _ in 0..<2 {
            d.run([pinched(0.6)], seconds: 0.03)
            d.run([pinched(0)], seconds: 0.07)
            d.run([pinched(1)], seconds: 0.08)
        }
        let counts = d.downs.compactMap { if case .down(_, _, let n) = $0 { return n }; return nil }
        check(counts == [1, 2], "click counts \(counts)")
    }

    test("Pinch and move → drag, release lands at drag end") {
        let d = Driver()
        d.run([SyntheticHand()], seconds: 0.4)
        d.run([pinched(0)], seconds: 0.1)
        var h = pinched(0)
        d.move(h, to: Vec2(0.62, 0.45), seconds: 0.4)
        h.center = Vec2(0.62, 0.45)
        d.run([h], seconds: 0.2)
        h.pinchIndexGap = 1
        d.run([h], seconds: 0.2)
        check(d.downs.count == 2 && d.ups.count == 2, "click, then drag press/release (\(d.downs.count)/\(d.ups.count))")
        check(d.drags.count > 5, "drag events emitted (\(d.drags.count))")
        if case .down(_, let p0, _)? = d.downs.first, case .down(_, let p1, _)? = d.downs.last {
            check(p0.distance(to: p1) < 1, "drag starts where the click landed")
        }
        if case .down(_, let p0, _)? = d.downs.last, case .up(_, let p1, _)? = d.ups.last {
            check(p1.x - p0.x > 200, "dragged right (\(p1.x - p0.x) pt)")
        }
    }

    test("Thumb–middle pinch → right click") {
        var c = EngineConfig(); c.enableRightClick = true
        let d = Driver(c)
        d.run([SyntheticHand()], seconds: 0.3)
        var h = SyntheticHand(); h.pinchMiddleGap = 0
        d.run([h], seconds: 0.1)
        h.pinchMiddleGap = 1
        d.run([h], seconds: 0.1)
        if case .down(let b, _, _)? = d.downs.first { check(b == .right, "right button") } else { check(false, "no down") }
    }

    test("Fist does not click (thumb on curled fingers)") {
        let d = Driver()
        d.run([SyntheticHand()], seconds: 0.3)
        d.run([SyntheticHand.pose(.fist)], seconds: 0.5)
        check(d.downs.isEmpty, "no presses from fist")
    }

    test("Far-away hand (small) still pinches") {
        let d = Driver()
        var h = SyntheticHand(); h.scale = 0.05
        d.run([h], seconds: 0.3)
        d.run([pinched(0, base: h)], seconds: 0.1)
        d.run([pinched(1, base: h)], seconds: 0.1)
        check(d.downs.count == 1, "click at 0.05 palm scale")
    }

    test("Hand lost mid-drag releases the button") {
        let d = Driver()
        d.run([SyntheticHand()], seconds: 0.3)
        d.run([pinched(0)], seconds: 0.6)
        d.run([], seconds: 0.5)
        check(d.downs.count == 1 && d.ups.count == 1, "button released after loss")
    }

    test("A long, still pinch stays a click (no accidental drag)") {
        let d = Driver()
        d.run([SyntheticHand()], seconds: 0.4)
        d.run([pinched(0)], seconds: 1.2)
        d.run([pinched(1)], seconds: 0.2)
        check(d.downs.count == 1 && d.drags.isEmpty, "no drag from holding")
    }

    test("Left pinch does not depend on middle-finger visibility or curling") {
        let d = Driver()
        d.run([SyntheticHand()], seconds: 0.4)
        var h = pinched(0).raw()
        for joint in Finger.middle.joints { h.confidence[joint.rawValue] = 0.05 }
        for _ in 0..<20 { d.stepRaw([h]) }
        check(d.downs.count == 1 && d.ups.count == 1, "one left click with hidden middle finger")
    }

    test("Low-confidence pinch opening cannot release a hold; prolonged loss does") {
        let d = Driver()
        startDrag(d)
        var open = pinched(1); open.center = Vec2(0.58, 0.45)
        var bad = open.raw()
        bad.confidence[Joint.thumbTip.rawValue] = 0.05
        for _ in 0..<6 { d.stepRaw([bad]) }
        check(d.ups.count == 1, "short occlusion preserves the drag")
        for _ in 0..<20 { d.stepRaw([bad]) }
        check(d.ups.count == 2, "prolonged fingertip loss releases exactly once")
    }

    test("A single reliable release spike does not break a hold") {
        var c = EngineConfig(); c.landmarkMinCutoff = 1000; c.landmarkBeta = 0
        let d = Driver(c)
        startDrag(d)
        var h = pinched(1); h.center = Vec2(0.58, 0.45)
        d.step([h])
        h.pinchIndexGap = 0
        d.run([h], seconds: 0.2)
        check(d.downs.count == 2 && d.ups.count == 1, "drag survives one-frame opening")
        h.pinchIndexGap = 1
        d.run([h], seconds: 0.2)
        check(d.ups.count == 2, "sustained opening releases")
    }

    test("A drag whose pinch drifts partly open stays held") {
        let d = Driver()
        startDrag(d)
        // Recorded holds creep open at ~0.2 palms/s.
        let drifted = gap(forRatio: 0.45)
        var h = pinched(0); h.center = Vec2(0.58, 0.45)
        for k in 1...90 { h.pinchIndexGap = drifted * Double(k) / 90; d.step([h]) }
        d.run([h], seconds: 0.5)
        check(d.downs.count == 2 && d.ups.count == 1, "drift to 0.45 palms does not drop the drag")
        h.pinchIndexGap = 1
        d.run([h], seconds: 0.2)
        check(d.ups.count == 2, "deliberate opening drops it")
    }

    test("Slowly closing fingers do not make the pointer sticky (any frame rate)") {
        for rate in [30.0, 60.0] {
            func travel(closing: Bool) -> Double {
                var c = EngineConfig(); c.cursorMode = .relative
                let e = GestureEngine(config: c)
                var t = 0.0, first: Vec2?, last: Vec2?
                // ~0.6 palms/s: a hand drifting half-closed, not a deliberate pinch.
                let n = Int(rate * 0.7), near = gap(forRatio: 0.34)
                for k in 0...n + Int(rate * 0.4) {
                    t += 1 / rate
                    var h = SyntheticHand()
                    let f = max(0, Double(k) - rate * 0.4) / Double(n)
                    if closing { h.pinchIndexGap = 1 - (1 - near) * min(f, 1) }
                    h.center = Vec2(0.4 + 0.1 * min(f, 1), 0.45)
                    let o = e.process(HandFrame(timestamp: t, aspect: 16 / 9, hands: [h.raw()]), screen: screen)
                    if Double(k) >= rate * 0.4, first == nil { first = o.cursor }
                    last = o.cursor ?? last
                }
                return (last ?? .zero).distance(to: first ?? .zero)
            }
            let open = travel(closing: false), closing = travel(closing: true)
            check(closing > open * 0.85, "\(Int(rate)) fps: pointer keeps \(Int(closing / open * 100))% of its travel")
        }
    }

    test("Relative mode: pinch-and-move drags (hand displacement, not pointer travel)") {
        var cfg = EngineConfig(); cfg.cursorMode = .relative
        let d = Driver(cfg)
        d.run([SyntheticHand()], seconds: 0.4)
        d.run([pinched(0)], seconds: 0.1)
        d.move(pinched(0), to: Vec2(0.6, 0.45), seconds: 0.4)
        var h = pinched(0); h.center = Vec2(0.6, 0.45); h.pinchIndexGap = 1
        d.run([h], seconds: 0.2)
        check(d.drags.count > 5, "dragged (\(d.drags.count) drag events)")
    }

    test("Relative pointer speed doesn't depend on distance from the camera") {
        func travel(scale: Double) -> Double {
            var config = EngineConfig(); config.cursorMode = .relative
            let engine = GestureEngine(config: config)
            var hand = SyntheticHand(); hand.scale = scale
            var time = 0.0, first: Vec2?, last: Vec2?
            // The same physical movement: a hand twice as far moves half as far in the image.
            for frame in 0..<120 {
                time += 1.0 / 60
                let progress = min(max(Double(frame - 50) / 40, 0), 1)
                hand.center = Vec2(0.4 + scale * progress, 0.45)
                let output = engine.process(HandFrame(timestamp: time, aspect: 16 / 9, hands: [hand.raw()]), screen: screen)
                if frame == 49 { first = output.cursor }
                last = output.cursor ?? last
            }
            return (last ?? .zero).distance(to: first ?? .zero)
        }
        let near = travel(scale: 0.3), far = travel(scale: 0.15)
        check(abs(far / near - 1) < 0.1, "near \(Int(near)) pt, far \(Int(far)) pt")
    }
}
