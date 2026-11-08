import Foundation
import GestureCore

/// Landmark repair, tracking, phantom hands, resets and malformed input.
func robustnessTests() {
    test("Repair: wrist cut off by the frame edge (garbage, zero confidence)") {
        let truth = SyntheticHand().raw()
        var bad = truth
        bad.points[Joint.wrist.rawValue] = Vec2(0.5, 0.02)       // Vision's wild guess
        bad.confidence[Joint.wrist.rawValue] = 0
        guard let fixed = HandRepair.repair(bad, aspect: 16 / 9) else { check(false, "dropped"); return }
        let err = fixed.points[Joint.wrist.rawValue].distance(to: truth.points[Joint.wrist.rawValue])
        check(err < 0.03, "wrist re-estimated near truth (err \(err))")
        let f0 = HandFeatures.compute(points: truth.points, confidence: truth.confidence, aspect: 16 / 9)
        let f1 = HandFeatures.compute(points: fixed.points, confidence: fixed.confidence, aspect: 16 / 9)
        check(abs(f1.palmScale - f0.palmScale) / f0.palmScale < 0.1, "palm scale preserved")
        check(f1.palmCenter.distance(to: f0.palmCenter) < 1e-9, "anchor independent of wrist")
    }

    test("Repair: one unreliable knuckle is re-fitted; two drop the hand") {
        let truth = SyntheticHand().raw()
        var one = truth
        one.points[Joint.ringMCP.rawValue] = Vec2(0.9, 0.9); one.confidence[Joint.ringMCP.rawValue] = 0.05
        let fixed = HandRepair.repair(one, aspect: 16 / 9)
        check(fixed != nil, "kept with 3 good knuckles")
        if let f = fixed {
            check(f.points[Joint.ringMCP.rawValue].distance(to: truth.points[Joint.ringMCP.rawValue]) < 0.01, "ring MCP re-fitted")
        }
        var two = one
        two.confidence[Joint.littleMCP.rawValue] = 0.05
        check(HandRepair.repair(two, aspect: 16 / 9) == nil, "dropped with 2 good knuckles")
    }

    test("Tracker: one-frame detector outlier neither moves the pointer nor spawns a hand") {
        let d = Driver()
        let h = SyntheticHand()
        d.run([h], seconds: 0.5)
        let before = d.last.cursor!
        var glitch = h; glitch.center = Vec2(0.5, 0.15)
        d.step([glitch])
        d.run([h], seconds: 0.2)
        check(d.engine.tracker.hands.count == 1, "one hand (\(d.engine.tracker.hands.count))")
        check(d.engine.tracker.hands.first?.continuity == 0, "no re-acquisition")
        check(d.last.cursor!.distance(to: before) < 3, "pointer unmoved (Δ=\(d.last.cursor!.distance(to: before)))")
    }

    test("Tracker: a persistent jump is re-acquired with the same identity") {
        var cfg = EngineConfig(); cfg.cursorMode = .relative
        let d = Driver(cfg)
        let h = SyntheticHand()
        d.run([h], seconds: 0.5)
        let id = d.engine.tracker.hands.first?.id
        let before = d.last.cursor!
        var moved = h; moved.center = Vec2(0.8, 0.3)
        d.run([moved], seconds: 0.3)
        check(d.engine.tracker.hands.count == 1 && d.engine.tracker.hands.first?.id == id, "same hand id")
        check(d.engine.tracker.hands.first?.continuity == 1, "re-acquired once")
        check(d.last.cursor!.distance(to: before) < 3, "relative pointer ignores the teleport (Δ=\(d.last.cursor!.distance(to: before)))")
    }

    test("Two-frame phantom cannot control the pointer or click") {
        let d = Driver()
        d.step([pinched(0)]); d.step([pinched(0)])
        check(d.last.cursor == nil && d.downs.isEmpty, "unconfirmed detection is passive")
        d.run([], seconds: 0.4)
        check(d.commands.isEmpty && d.ups.isEmpty, "no delayed phantom actions")
    }

    test("Coasting mid-drag never integrates stale landmarks") {
        let d = Driver()
        d.run([SyntheticHand()], seconds: 0.4)
        d.run([pinched(0)], seconds: 0.3)
        d.move(pinched(0), to: Vec2(0.6, 0.45), seconds: 0.3)
        let before = d.last.cursor!
        let out = d.step([])
        check(out.cursor == before, "no cursor drift during missing frame")
        check(!out.events.contains { if case .drag = $0 { return true }; return false }, "no stale drag event")
    }

    test("Config reload releases a held button before replacing cursor state") {
        let d = Driver()
        d.run([SyntheticHand()], seconds: 0.4)
        d.run([pinched(0)], seconds: 0.3)
        var changed = d.engine.config; changed.cursorBeta += 1
        d.engine.config = changed
        d.step([pinched(0)])
        check(d.ups.count == 1 && d.downs.count == 1, "balanced button state after reload")
    }

    test("Suspend clears confirmation, double-click history and frame timing") {
        let d = Driver()
        startDrag(d)
        let released = d.engine.suspend()
        check(released.count == 1, "suspend releases the drag once")
        d.run([SyntheticHand()], seconds: 0.3)
        d.run([pinched(0)], seconds: 0.3)
        let counts = d.downs.compactMap { if case .down(_, _, let n) = $0 { return n }; return nil }
        check(counts == [1, 1, 1], "new session starts a fresh click sequence (\(counts))")
    }

    test("Malformed and scattered detector artifacts are rejected") {
        var h = SyntheticHand().raw()
        h.points = []
        check(HandRepair.repair(h, aspect: 16 / 9) == nil, "malformed arrays rejected before indexing")
        h = SyntheticHand().raw(); h.points[8].x = .nan
        check(HandRepair.repair(h, aspect: 16 / 9) == nil, "NaN rejected")
        h = SyntheticHand().raw(); h.score = 0.1
        check(HandRepair.repair(h, aspect: 16 / 9) == nil, "weak observation rejected")
        h = SyntheticHand().raw(); h.points[8] = Vec2(0.99, 0.01)
        check(HandRepair.repair(h, aspect: 16 / 9) == nil, "impossible finger segment rejected")
    }

    test("Invalid frame metadata releases safely") {
        let d = Driver()
        startDrag(d)
        let out = d.engine.process(HandFrame(timestamp: .nan, aspect: 0, hands: []), screen: screen)
        check(out.events.contains { if case .up = $0 { return true }; return false }, "invalid frame releases the drag")
        check(out.cursor == nil, "no invalid cursor escapes")
    }

    test("Recording reports malformed lines instead of silently skipping them") {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let frame = HandFrame(timestamp: 1, aspect: 16 / 9, hands: [])
        var data = try JSONEncoder().encode(frame)
        data.append(Data("\n{broken}\n".utf8))
        try data.write(to: url)
        do {
            _ = try Recording.load(url)
            check(false, "malformed recording should fail")
        } catch let error as Recording.InvalidLine {
            check(error.line == 2, "reports exact failing line")
        }
    }

    test("Performance: engine per-frame cost") {
        let d = Driver()
        let start = Date()
        var a = SyntheticHand(); var b = SyntheticHand(); b.center = Vec2(0.7, 0.5)
        for k in 0..<6000 { a.center.x = 0.3 + 0.1 * sin(Double(k) / 20); d.step([a, b]) }
        let us = Date().timeIntervalSince(start) / 6000 * 1e6
        print(String(format: "    %.1f µs/frame (2 hands)", us))
        check(us < 500, "under 0.5 ms/frame")
    }
}
