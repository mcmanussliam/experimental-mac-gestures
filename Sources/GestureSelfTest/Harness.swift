import Foundation
import GestureCore

// Minimal test harness (XCTest / swift-testing are unavailable with Command Line Tools only).
var failures = 0
var passes = 0
func check(_ cond: @autoclosure () -> Bool, _ msg: String, file: StaticString = #fileID, line: Int = #line) {
    if cond() { passes += 1 } else { failures += 1; print("  ✗ \(msg)  (\(file):\(line))") }
}
func test(_ name: String, _ body: () throws -> Void) {
    let before = failures
    do { try body() } catch { failures += 1; print("  ✗ threw \(error)") }
    print(failures == before ? "✓ \(name)" : "✗ \(name)")
}

let screen = Vec2(1600, 1000)
let fps = 60.0

/// Drives an engine with a sequence of synthetic hands, collecting all output.
final class Driver {
    let engine: GestureEngine
    var t = 100.0
    var events: [PointerEvent] = []
    var commands: [GestureCommand] = []
    var last = EngineOutput()

    init(_ config: EngineConfig = EngineConfig()) { engine = GestureEngine(config: config) }

    @discardableResult
    func run(_ hands: [SyntheticHand], seconds: Double) -> [EngineOutput] {
        var outs: [EngineOutput] = []
        let n = max(1, Int((seconds * fps).rounded()))
        for _ in 0..<n { outs.append(step(hands)) }
        return outs
    }

    @discardableResult
    func step(_ hands: [SyntheticHand]) -> EngineOutput {
        stepRaw(hands.map { $0.raw() })
    }

    @discardableResult
    func stepRaw(_ hands: [RawHand]) -> EngineOutput {
        t += 1 / fps
        let o = engine.process(HandFrame(timestamp: t, aspect: 16 / 9, hands: hands), screen: screen)
        events += o.events; commands += o.commands; last = o
        return o
    }

    /// Linearly animates between two hands' centres over `seconds`.
    func move(_ h: SyntheticHand, to c: Vec2, seconds: Double) {
        let n = max(1, Int(seconds * fps)); let start = h.center
        for k in 1...n { var x = h; x.center = start.lerp(to: c, Double(k) / Double(n)); step([x]) }
    }

    var downs: [PointerEvent] { events.filter { if case .down = $0 { return true }; return false } }
    var ups: [PointerEvent] { events.filter { if case .up = $0 { return true }; return false } }
    var drags: [PointerEvent] { events.filter { if case .drag = $0 { return true }; return false } }
    var scrolls: [(Double, Double, Bool)] { events.compactMap { if case .scroll(let x, let y, let m) = $0 { return (x, y, m) }; return nil } }
}

func pinched(_ gap: Double, base: SyntheticHand = SyntheticHand()) -> SyntheticHand {
    var h = base; h.pinchIndexGap = gap; return h
}

/// Opens, pinches, and moves while pinched until a drag (with its button held) is under way.
func startDrag(_ d: Driver) {
    d.run([SyntheticHand()], seconds: 0.4)
    d.run([pinched(0)], seconds: 0.1)
    d.move(pinched(0), to: Vec2(0.58, 0.45), seconds: 0.3)
}

/// Index + little extended: a shape outside the built-in vocabulary.
func horns() -> SyntheticHand {
    var h = SyntheticHand(); h.extended = [false, true, false, false, true]; return h
}

/// The pinch gap whose observed thumb–index ratio first reaches `ratio` palms.
func gap(forRatio ratio: Double) -> Double {
    stride(from: 0.0, through: 1.0, by: 0.005).first { g in
        let r = pinched(g).raw()
        return HandFeatures.compute(points: r.points, confidence: r.confidence, aspect: 16 / 9).pinchIndex >= ratio
    } ?? 1
}
