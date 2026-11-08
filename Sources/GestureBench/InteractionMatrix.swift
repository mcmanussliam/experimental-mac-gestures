import Foundation
import GestureCore

private struct Trial {
    var mode: CursorMode
    var fps: Double
    var scale: Double
    var rotation: Double
    var chirality: Chirality
    var noise: Double
    var tuned: Bool
    var label: String { "\(mode.rawValue)/\(Int(fps))fps/scale=\(scale)/rot=\(rotation)/\(chirality)/noise=\(noise)/tuned=\(tuned)" }
    var hand: SyntheticHand {
        var h = SyntheticHand()
        h.scale = scale; h.rotation = rotation; h.chirality = chirality
        return h
    }
    var config: EngineConfig {
        var c = EngineConfig(); c.cursorMode = mode
        if tuned {
            // Hand-tuned wide thresholds, as a user might set in config.json.
            c.pinchEnter = 0.39; c.pinchExit = 0.60; c.pinchDampStart = 0.85
        }
        return c
    }
}

private final class MatrixDriver {
    let engine: GestureEngine
    let trial: Trial
    var t = 100.0
    var frames: [(Double, EngineOutput)] = []
    var seed: UInt64 = 42
    init(_ trial: Trial) { self.trial = trial; engine = GestureEngine(config: trial.config) }
    func random() -> Double {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Double(seed >> 11) / Double(UInt64.max >> 11) * 2 - 1
    }
    @discardableResult func step(_ hand: SyntheticHand?) -> EngineOutput {
        t += 1 / trial.fps
        let raw = hand.map { h -> RawHand in
            var r = h.raw()
            for j in r.points.indices {
                r.points[j].x += random() * trial.noise * trial.scale / (16 / 9)
                r.points[j].y += random() * trial.noise * trial.scale
            }
            return r
        }
        let out = engine.process(HandFrame(timestamp: t, aspect: 16 / 9, hands: raw.map { [$0] } ?? []), screen: Vec2(1600, 1000))
        frames.append((t, out)); return out
    }
    func hold(_ h: SyntheticHand?, _ seconds: Double) {
        for _ in 0..<max(1, Int((seconds * trial.fps).rounded())) { step(h) }
    }
    func ramp(_ from: SyntheticHand, _ to: SyntheticHand, _ seconds: Double) {
        let n = max(1, Int((seconds * trial.fps).rounded()))
        for i in 1...n {
            let f = Double(i) / Double(n)
            var h = from
            h.center = from.center.lerp(to: to.center, f)
            if from.pinchIndexGap != nil || to.pinchIndexGap != nil {
                h.pinchIndexGap = (from.pinchIndexGap ?? 1) * (1 - f) + (to.pinchIndexGap ?? 1) * f
            }
            step(h)
        }
    }
    var events: [PointerEvent] { frames.flatMap { $0.1.events } }
    var downs: [PointerEvent] { events.filter { if case .down = $0 { return true }; return false } }
    var ups: [PointerEvent] { events.filter { if case .up = $0 { return true }; return false } }
    var commands: Int { frames.reduce(0) { $0 + $1.1.commands.count } }
    var dragFrames: Int { frames.filter { $0.1.hud.mode == .dragging }.count }
}

/// 648 input conditions × 8 episodes. The same file runs against the previous engine.
/// A pass means its explicit synthetic contract held, not camera recognition accuracy.
enum InteractionMatrix {
    static func run(check: Bool) throws {
        var totals: [String: Int] = [:], passes: [String: Int] = [:]
        var failures: [String] = []
        var releaseDistances: [Double] = []
        var dragOnsets: [Double] = []
        var scrollLeakages: [Double] = []
        func record(_ name: String, _ passed: Bool, _ trial: Trial) {
            totals[name, default: 0] += 1
            if passed { passes[name, default: 0] += 1 }
            else if failures.count < 32 { failures.append("\(name): \(trial.label)") }
        }
        for mode in [CursorMode.absolute, .relative] {
            for fps in [15.0, 30, 60] {
                for scale in [0.06, 0.12, 0.20] {
                    for rotation in [-0.4, 0, 0.4] {
                        for chirality in [Chirality.left, .right] {
                            for noise in [0.0, 0.015, 0.035] {
                                for tuned in [false, true] {
                                    let v = Trial(mode: mode, fps: fps, scale: scale, rotation: rotation,
                                                  chirality: chirality, noise: noise, tuned: tuned)
                                    let h = v.hand
                                    var closed = h; closed.pinchIndexGap = 0

                                    let tap = MatrixDriver(v)
                                    tap.hold(h, 0.5); tap.ramp(h, closed, 0.12); tap.hold(closed, 0.12)
                                    tap.ramp(closed, h, 0.12); tap.hold(h, 0.2)
                                    record("tap", tap.downs.count == 1 && tap.ups.count == 1 && tap.dragFrames == 0, v)

                                    let double = MatrixDriver(v)
                                    double.hold(h, 0.5)
                                    for _ in 0..<2 { double.hold(closed, 0.12); double.hold(h, 0.14) }
                                    let counts = double.downs.compactMap { if case .down(_, _, let n) = $0 { return n }; return nil }
                                    record("double_click", counts == [1, 2] && double.ups.count == 2, v)

                                    let hold = MatrixDriver(v)
                                    hold.hold(h, 0.5); hold.ramp(h, closed, 0.12); hold.hold(closed, 1.2)
                                    // A long still pinch is still one instant click, never a drag.
                                    record("stationary_hold", hold.downs.count == 1 && hold.ups.count == 1 && hold.dragFrames == 0, v)

                                    let drag = MatrixDriver(v)
                                    drag.hold(h, 0.5); drag.ramp(h, closed, 0.12); drag.hold(closed, 0.15)
                                    let moveStart = drag.t
                                    var end = closed; end.center.x += 0.12
                                    drag.ramp(closed, end, 0.65)
                                    let atOpening = drag.frames.last!.1.cursor ?? .zero
                                    var released = end; released.pinchIndexGap = nil
                                    // The hand continues moving while fingers separate: drop should stay put.
                                    var releaseEnd = released; releaseEnd.center.x += 0.04
                                    drag.ramp(released, releaseEnd, 0.16); drag.hold(releaseEnd, 0.15)
                                    let release = drag.ups.compactMap { if case .up(_, let p, _) = $0 { return p }; return nil }.last
                                    let distance = release.map { $0.distance(to: atOpening) } ?? .infinity
                                    if distance.isFinite { releaseDistances.append(distance) }
                                    if let onset = drag.frames.first(where: { $0.1.hud.mode == .dragging })?.0 { dragOnsets.append((onset - moveStart) * 1000) }
                                    // Instant click, then the drag's own press and release.
                                    record("drag_and_drop", drag.downs.count == 2 && drag.ups.count == 2 && drag.dragFrames > 1 && distance < 18, v)

                                    let scroll = MatrixDriver(v)
                                    scroll.hold(h, 0.5)
                                    var two = SyntheticHand.pose(.twoFinger)
                                    two.scale = scale; two.rotation = rotation; two.chirality = chirality
                                    scroll.hold(two, 0.3)
                                    // Joystick: offset the hand about a palm from where the pose formed, then hold.
                                    var scrollEnd = two; scrollEnd.center.y += scale
                                    // A small sideways component should not create sideways scroll.
                                    scrollEnd.center.x += scale * 0.03
                                    scroll.ramp(two, scrollEnd, 0.3)
                                    let heldFrom = scroll.events.count
                                    scroll.hold(scrollEnd, 0.4)
                                    let deltas: [Vec2] = scroll.events.compactMap { if case .scroll(let x, let y, false) = $0 { return Vec2(x, y) }; return nil }
                                    let held = scroll.events[heldFrom...].compactMap { e -> Double? in if case .scroll(_, let y, false) = e { return y }; return nil }
                                    let sum = deltas.reduce(Vec2.zero, +)
                                    if sum.y > 0 { scrollLeakages.append(abs(sum.x) / sum.y * 100) }
                                    record("two_finger_scroll", sum.y > 200 && held.reduce(0, +) > 100 && abs(sum.x) < max(12, abs(sum.y) * 0.08)
                                           && scroll.downs.isEmpty && scroll.commands == 0, v)

                                    let relaxed = MatrixDriver(v)
                                    relaxed.hold(h, 0.5)
                                    var commandShape = SyntheticHand.pose(.point)
                                    commandShape.scale = scale; commandShape.rotation = rotation; commandShape.chirality = chirality
                                    relaxed.hold(commandShape, 0.7)
                                    let pointerBefore = relaxed.frames.last!.1.cursor ?? .zero
                                    var moved = commandShape; moved.center.x += 0.06
                                    relaxed.ramp(commandShape, moved, 0.4)
                                    let travel = relaxed.frames.last!.1.cursor?.distance(to: pointerBefore) ?? 0
                                    record("pointing_motion", travel > 25 && relaxed.commands == 0 && relaxed.downs.isEmpty, v)

                                    let acquiredClosed = MatrixDriver(v)
                                    acquiredClosed.hold(closed, 0.6)
                                    record("closed_hand_entry", acquiredClosed.downs.isEmpty, v)

                                    let loss = MatrixDriver(v)
                                    loss.hold(h, 0.5); loss.hold(closed, 0.25)
                                    var movedClosed = closed; movedClosed.center.x += 0.08
                                    loss.ramp(closed, movedClosed, 0.4)
                                    loss.hold(nil, 0.5)
                                    // Every press is released, even when the hand vanishes mid-drag.
                                    record("loss_releases", !loss.downs.isEmpty && loss.downs.count == loss.ups.count, v)
                                }
                            }
                        }
                    }
                }
            }
        }
        func percentile(_ a: [Double], _ p: Double) -> Double {
            let sorted = a.sorted(); return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * p))]
        }
        let scenarios = totals.keys.sorted().map { name -> [String: Any] in
            ["name": name, "passed": passes[name, default: 0], "total": totals[name, default: 0]]
        }
        let report: [String: Any] = [
            "conditions": totals["tap", default: 0], "episodes": totals.values.reduce(0, +),
            "scenarios": scenarios, "failure_examples": failures,
            "release_displacement_p95_pt": percentile(releaseDistances, 0.95),
            "scroll_cross_axis_p95_percent": percentile(scrollLeakages, 0.95),
            "drag_onset_p50_ms": percentile(dragOnsets, 0.5),
            "drag_onset_p95_ms": percentile(dragOnsets, 0.95),
            "note": "Synthetic behavioural contracts; not real-camera accuracy."
        ]
        print(String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
        if check {
            // Keep failures visible. These are functional contracts, not implementation snapshots.
            let acceptable = totals.allSatisfy { name, count in Double(passes[name, default: 0]) / Double(count) >= 0.98 }
            exit(acceptable ? 0 : 1)
        }
    }
}
