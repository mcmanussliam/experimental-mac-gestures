import Foundation
import GestureCore

/// One engine step of a replayed session, with the pointer hand's state captured at that time.
struct Sample {
    var time: Double
    var output: EngineOutput
    var pointerID: Int?
    var continuity: Int
    var poseName: String?
    var features: HandFeatures?
    var fresh: Bool
    var knuckles: Vec2?
}

/// Pointer-quality and recognition-stability metrics for a replayed session. The recordings have
/// no intent labels, so event counts describe behaviour, not accuracy.
struct Score {
    let samples: [Sample]
    let config: EngineConfig

    private var present: [Sample] { samples.filter { $0.pointerID != nil } }
    private var duration: Double { (samples.last?.time ?? 0) - (samples.first?.time ?? 0) }

    static func percentile(_ values: [Double], _ p: Double) -> Double {
        guard !values.isEmpty else { return .nan }
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * p))]
    }

    static func format(_ value: Double, _ digits: Int = 2) -> String { String(format: "%.\(digits)f", value) }

    func report() {
        let presence = Double(present.count) / Double(max(samples.count, 1)) * 100
        print("Session: \(samples.count) frames, \(Self.format(duration, 1)) s, pointer hand present \(Self.format(presence, 0))%")
        let paused = samples.filter { $0.output.hud.mode == .paused }.count
        print("  paused frames \(paused); replay has no intent labels, so event counts are not accuracy scores")
        reportPointer()
        reportTracking()
        reportPoses()
        reportScrolling()
        reportClicking()
    }

    /// Still-hand jitter, large steps and spikiness. A frame is "still" if the raw knuckle centre
    /// moved less than 2% of the frame within ±0.25 s.
    private func reportPointer() {
        var still: [Bool?] = Array(repeating: nil, count: samples.count)
        for index in samples.indices {
            let sample = samples[index]
            guard sample.knuckles != nil, sample.fresh, sample.output.hud.mode == .pointing else { continue }
            let window = neighbours(of: index, radius: 0.25).compactMap(\.knuckles)
            guard window.count >= 8 else { continue }
            let xs = window.map(\.x), ys = window.map(\.y)
            still[index] = max(xs.max()! - xs.min()!, ys.max()! - ys.min()!) < 0.02
        }
        var deviations: [Double] = [], steps: [Double] = [], accelerations: [Double] = []
        for index in samples.indices {
            guard let cursor = samples[index].output.cursor, let isStill = still[index] else { continue }
            if isStill {
                let window = neighbours(of: index, radius: 0.15).compactMap { $0.output.cursor }
                deviations.append((cursor - window.reduce(Vec2.zero, +) / Double(window.count)).length)
            } else if let (previous, next) = movingNeighbours(of: index) {
                steps.append(cursor.distance(to: previous))
                accelerations.append((next - cursor * 2 + previous).length)
            }
        }
        let rms = deviations.isEmpty ? Double.nan
            : (deviations.map { $0 * $0 }.reduce(0, +) / Double(deviations.count)).squareRoot()
        print("\nPointer (\(config.cursorMode.rawValue))")
        print("  still-hand jitter      \(Self.format(rms)) pt RMS over \(deviations.count) frames")
        print("  moving: steps >150 pt  \(steps.filter { $0 > 150 }.count) of \(steps.count)")
        print("  moving: |accel| p50/p95  \(Self.format(Self.percentile(accelerations, 0.5), 1)) / \(Self.format(Self.percentile(accelerations, 0.95), 1)) pt/frame²")
    }

    private func reportTracking() {
        var identityChanges = 0, reacquisitions = 0
        for (a, b) in zip(samples, samples.dropFirst()) {
            if let x = a.pointerID, let y = b.pointerID, x != y { identityChanges += 1 }
            if a.pointerID == b.pointerID, b.continuity > a.continuity { reacquisitions += 1 }
        }
        let coasting = present.filter { !$0.fresh }.count
        print("\nTracking")
        print("  pointer identity changes \(identityChanges), re-acquisitions \(reacquisitions), coasting frames \(coasting)")
    }

    private func reportPoses() {
        var changes = 0, unknown = 0
        var frames: [String: Int] = [:]
        for (a, b) in zip(present, present.dropFirst()) where a.poseName != b.poseName { changes += 1 }
        for sample in present {
            frames[sample.poseName ?? "-", default: 0] += 1
            if sample.poseName == "unknown" { unknown += 1 }
        }
        let unknownShare = Double(unknown) / Double(max(present.count, 1)) * 100
        print("\nPoses")
        print("  committed pose changes \(Self.format(Double(changes) / max(duration, 1), 2))/s, unknown \(Self.format(unknownShare, 0))%")
        print("  " + frames.sorted { $0.value > $1.value }.prefix(8).map { "\($0.key) \($0.value)" }.joined(separator: ", "))
    }

    /// A re-entry shortly after an exit is usually one stroke chopped up by pose flicker.
    private func reportScrolling() {
        var entries = 0, reentries = 0, liveFrames = 0, coastFrames = 0
        var lastExit: Double?
        for index in samples.indices {
            let scrolling = samples[index].output.hud.mode == .scrolling
            let wasScrolling = index > 0 && samples[index - 1].output.hud.mode == .scrolling
            if scrolling && !wasScrolling {
                entries += 1
                if let exit = lastExit, samples[index].time - exit < 0.6 { reentries += 1 }
            }
            if !scrolling && wasScrolling { lastExit = samples[index].time }
            for event in samples[index].output.events {
                if case .scroll(_, _, let coasting) = event {
                    if coasting { coastFrames += 1 } else { liveFrames += 1 }
                    break
                }
            }
        }
        print("\nScrolling")
        print("  entries \(entries) (re-entered within 0.6 s: \(reentries)), live event frames \(liveFrames), momentum frames \(coastFrames)")
    }

    /// An "approach" is pinch progress crossing 0.5, where the pointer is noticeably damped.
    private func reportClicking() {
        var presses = 0, drags = 0, approaches = 0, approachesWithoutPress = 0
        var pressDistances: [Double] = []
        var pressedAt: Vec2?
        for index in samples.indices {
            for event in samples[index].output.events {
                switch event {
                case .down(_, let position, _): presses += 1; pressedAt = position
                case .up(_, let position, _):
                    if let start = pressedAt { pressDistances.append(start.distance(to: position)) }
                    pressedAt = nil
                default: break
                }
            }
            guard index > 0 else { continue }
            let hud = samples[index].output.hud, previous = samples[index - 1].output.hud
            if hud.mode == .pointing, hud.pinchProgress >= 0.5, previous.pinchProgress < 0.5 {
                approaches += 1
                let pressed = samples[index...].prefix { $0.time - samples[index].time < 0.5 }
                    .contains { $0.output.hud.mode == .pressed }
                if !pressed { approachesWithoutPress += 1 }
            }
            if hud.mode == .dragging, previous.mode != .dragging { drags += 1 }
        }
        let damped = present.filter { $0.output.hud.mode == .pointing && $0.output.hud.pinchProgress > 0 }.count
        let dampedShare = Double(damped) / Double(max(present.count, 1)) * 100
        print("\nClicking")
        print("  presses \(presses), of which became drags \(drags); press→release distances (pt): " +
              pressDistances.map { String(Int($0)) }.joined(separator: " "))
        print("  pointer damped by pinch approach in \(Self.format(dampedShare, 0))% of frames; " +
              "strong approaches \(approaches), not followed by a press: \(approachesWithoutPress)")

        let drifts = clickDrifts()
        print("  pointer drift while the fingers close, approach start → click p50/p95/max: "
              + "\(Self.format(Self.percentile(drifts, 0.5), 1)) / \(Self.format(Self.percentile(drifts, 0.95), 1)) / "
              + "\(Self.format(drifts.max() ?? 0, 1)) pt over \(drifts.count) clicks")

        let open = present.filter { $0.output.hud.mode == .pointing }.compactMap { $0.features?.pinchIndex }
        let closed = present.filter { $0.output.hud.mode == .pressed || $0.output.hud.mode == .dragging }
            .compactMap { $0.features?.pinchIndex }
        print("  thumb–index ratio while pointing p5/p25/p50: \(Self.format(Self.percentile(open, 0.05))) / \(Self.format(Self.percentile(open, 0.25))) / \(Self.format(Self.percentile(open, 0.5)))")
        print("  thumb–index ratio while pressed  p50/p95:    \(Self.format(Self.percentile(closed, 0.5))) / \(Self.format(Self.percentile(closed, 0.95)))")
        print("  thresholds: damp start \(config.pinchDampStart), enter \(config.pinchEnter), exit \(config.pinchExit)")
    }

    /// How far the pointer moved between the fingers starting to close (pinch progress leaving
    /// zero, at most 0.4 s earlier) and the click: the Heisenberg effect left after damping.
    private func clickDrifts() -> [Double] {
        samples.indices.compactMap { index -> Double? in
            guard samples[index].output.events.contains(where: { if case .down = $0 { return true }; return false }),
                  let clickedAt = samples[index].output.events.compactMap({ event -> Vec2? in
                      if case .down(_, let position, _) = event { return position }; return nil }).first
            else { return nil }
            var start = index
            while start > 0, samples[start - 1].output.hud.pinchProgress > 0.02,
                  samples[start - 1].output.hud.mode == .pointing,
                  samples[index].time - samples[start - 1].time < 0.4 { start -= 1 }
            guard start < index, let before = samples[start].output.cursor else { return nil }
            return before.distance(to: clickedAt)
        }
    }

    /// Fresh pointing samples of the same hand and track within `radius` seconds.
    private func neighbours(of index: Int, radius: Double) -> [Sample] {
        let center = samples[index]
        let range = lowerBound(center.time - radius)..<lowerBound(center.time + radius + 1e-9)
        return samples[range].filter {
            $0.fresh && $0.pointerID == center.pointerID && $0.continuity == center.continuity
                && $0.output.hud.mode == .pointing
        }
    }

    /// The cursor one frame either side, when all three frames are consecutive fresh pointing frames
    /// of the same track.
    private func movingNeighbours(of index: Int) -> (Vec2, Vec2)? {
        guard index > 0, index + 1 < samples.count else { return nil }
        let window = samples[(index - 1)...(index + 1)]
        let center = samples[index]
        guard let previous = samples[index - 1].output.cursor, let next = samples[index + 1].output.cursor,
              samples[index + 1].time - samples[index - 1].time < 0.08,
              window.allSatisfy({ $0.fresh && $0.pointerID == center.pointerID && $0.continuity == center.continuity
                                    && $0.output.hud.mode == .pointing })
        else { return nil }
        return (previous, next)
    }

    /// First sample at or after `time`.
    private func lowerBound(_ time: Double) -> Int {
        var low = 0, high = samples.count
        while low < high {
            let mid = (low + high) / 2
            if samples[mid].time < time { low = mid + 1 } else { high = mid }
        }
        return low
    }
}
