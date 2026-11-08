import Foundation
import GestureCore

/// Deterministic interaction benchmarks. Uses only public APIs shared by the baseline engine.
/// These measure state-machine behaviour, not camera recognition accuracy or user intent.
final class Scenario {
    let engine = GestureEngine()
    let fps: Double
    var t = 100.0
    var outputs: [EngineOutput] = []
    init(fps: Double) { self.fps = fps }

    @discardableResult
    func step(_ hand: RawHand?) -> EngineOutput {
        t += 1 / fps
        let out = engine.process(HandFrame(timestamp: t, aspect: 16 / 9, hands: hand.map { [$0] } ?? []),
                                 screen: Vec2(1600, 1000))
        outputs.append(out)
        return out
    }

    func hold(_ hand: RawHand?, seconds: Double) {
        for _ in 0..<max(1, Int((seconds * fps).rounded())) { step(hand) }
    }

    var presses: Int { outputs.flatMap(\.events).filter { if case .down = $0 { return true }; return false }.count }
    var releases: Int { outputs.flatMap(\.events).filter { if case .up = $0 { return true }; return false }.count }
}

if CommandLine.arguments.contains("--matrix") {
    try InteractionMatrix.run(check: CommandLine.arguments.contains("--check"))
    exit(0)
}

var metrics: [String: Double] = [:]
for fps in [15.0, 30, 60] {
    let prefix = "\(Int(fps))fps."
    let open = SyntheticHand().raw()
    var pinch = SyntheticHand(); pinch.pinchIndexGap = 0

    let scroll = Scenario(fps: fps)
    scroll.hold(open, seconds: 0.4)
    let start = scroll.t
    var onset: Double?
    for k in 0..<Int(fps * 0.5) {
        var h = SyntheticHand.pose(.twoFinger)
        h.center.y += Double(k) / fps * 0.12
        let out = scroll.step(h.raw())
        if onset == nil && out.events.contains(where: { if case .scroll = $0 { return true }; return false }) {
            onset = scroll.t - start
        }
    }
    metrics[prefix + "scroll_onset_ms"] = (onset ?? 1) * 1000

    let click = Scenario(fps: fps)
    click.hold(open, seconds: 0.4)
    var occluded = pinch.raw()
    for joint in Finger.middle.joints { occluded.confidence[joint.rawValue] = 0.05 }
    click.hold(occluded, seconds: 0.4)
    metrics[prefix + "left_clicks_with_middle_occluded"] = Double(click.presses)

    let phantom = Scenario(fps: fps)
    phantom.hold(pinch.raw(), seconds: 2 / fps)
    phantom.hold(nil, seconds: 0.4)
    metrics[prefix + "two_frame_phantom_clicks"] = Double(phantom.presses)
    metrics[prefix + "two_frame_phantom_cursor_frames"] = Double(phantom.outputs.filter { $0.cursor != nil }.count)

    // A held button (a drag in progress) survives a short thumb occlusion.
    let hold = Scenario(fps: fps)
    hold.hold(open, seconds: 0.4)
    hold.hold(pinch.raw(), seconds: 0.1)
    var moved = pinch
    for k in 1...Int(fps * 0.3) { moved.center.x = pinch.center.x + Double(k) / fps * 0.3; hold.step(moved.raw()) }
    let releasesBefore = hold.releases
    var noisy = moved.raw()
    noisy.points[Joint.thumbTip.rawValue] = Vec2(0.1, 0.1)
    noisy.confidence[Joint.thumbTip.rawValue] = 0.05
    hold.hold(noisy, seconds: 0.10)
    hold.hold(moved.raw(), seconds: 0.2)
    metrics[prefix + "occlusion_hold_releases"] = Double(hold.releases - releasesBefore)

    // Click latency: fingers start closing (open → touching over 120 ms, held 150 ms, reopening
    // over 120 ms, a typical tap) until the click is complete (button up).
    let tap = Scenario(fps: fps)
    tap.hold(open, seconds: 0.4)
    let closeStart = tap.t
    var clickedAt: Double?
    let ramp = fps * 0.12, held = fps * 0.15
    for k in 1...Int(fps * 0.8) {
        let x = Double(k)
        var h = SyntheticHand()
        h.pinchIndexGap = x < ramp ? 1 - x / ramp : x < ramp + held ? 0 : min(1, (x - ramp - held) / ramp)
        let out = tap.step(h.raw())
        if clickedAt == nil && out.events.contains(where: { if case .up = $0 { return true }; return false }) {
            clickedAt = tap.t
        }
    }
    metrics[prefix + "click_latency_ms"] = ((clickedAt ?? closeStart + 1) - closeStart) * 1000

    let drag = Scenario(fps: fps)
    drag.hold(open, seconds: 0.4)
    drag.hold(pinch.raw(), seconds: 0.3)
    for k in 1...Int(fps * 0.4) {
        var h = pinch; h.center.x += Double(k) / fps * 0.3
        drag.step(h.raw())
    }
    let before = drag.outputs.last!.cursor!
    let missing = drag.step(nil)
    metrics[prefix + "missing_frame_drag_drift_pt"] = missing.cursor?.distance(to: before) ?? 0
}

let performance = Scenario(fps: 60)
let hand = SyntheticHand().raw()
let start = DispatchTime.now().uptimeNanoseconds
for _ in 0..<10000 { performance.step(hand) }
metrics["engine_us_per_frame_one_hand"] = Double(DispatchTime.now().uptimeNanoseconds - start) / 10000 / 1000
let data = try JSONSerialization.data(withJSONObject: metrics, options: [.prettyPrinted, .sortedKeys])
print(String(decoding: data, as: UTF8.self))

if CommandLine.arguments.contains("--check") {
    let acceptable = [15, 30, 60].allSatisfy { fps in
        let prefix = "\(fps)fps."
        return metrics[prefix + "left_clicks_with_middle_occluded"] == 1 &&
            metrics[prefix + "two_frame_phantom_clicks"] == 0 &&
            metrics[prefix + "two_frame_phantom_cursor_frames"] == 0 &&
            metrics[prefix + "occlusion_hold_releases"] == 0 &&
            metrics[prefix + "missing_frame_drag_drift_pt"] == 0 &&
            (metrics[prefix + "scroll_onset_ms"] ?? .infinity) < (fps == 15 ? 300 : fps == 30 ? 230 : 190)
    }
    exit(acceptable ? 0 : 1)
}
