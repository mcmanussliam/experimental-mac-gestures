import Foundation
import GestureCore

/// Swipes, pause, the keyboard zone and two-hand zoom.
func commandTests() {
    test("Open-palm swipe left fires once; return stroke suppressed") {
        let d = Driver()
        let h = SyntheticHand()
        d.run([h], seconds: 0.3)
        d.move(h, to: Vec2(0.15, 0.45), seconds: 0.18)
        var back = h; back.center = Vec2(0.15, 0.45)
        d.run([back], seconds: 0.1)
        d.move(back, to: Vec2(0.5, 0.45), seconds: 0.18)
        let swipes = d.commands.filter { if case .swipe = $0 { return true }; return false }
        check(swipes == [.swipe(.left)], "swipes \(swipes)")
    }

    test("Slow movement is not a swipe") {
        let d = Driver()
        let h = SyntheticHand()
        d.run([h], seconds: 0.3)
        d.move(h, to: Vec2(0.2, 0.45), seconds: 2.0)
        check(d.commands.isEmpty, "commands \(d.commands)")
    }

    test("Fist held → pause, again → resume") {
        let d = Driver()
        d.run([SyntheticHand.pose(.fist)], seconds: 1.3)
        check(d.commands.contains(.paused(true)), "paused")
        d.run([SyntheticHand()], seconds: 0.3)
        d.run([pinched(0)], seconds: 0.2)
        check(d.downs.isEmpty, "no clicks while paused")
        d.run([SyntheticHand.pose(.fist)], seconds: 1.3)
        check(d.commands.contains(.paused(false)), "resumed")
    }

    test("Hands in the keyboard zone are ignored") {
        let d = Driver()
        var h = SyntheticHand(); h.center = Vec2(0.5, 0.97)
        d.run([h], seconds: 0.3)
        d.run([pinched(0, base: h)], seconds: 0.2)
        check(d.downs.isEmpty && d.last.cursor == nil, "ignored")
    }

    test("Two-hand pinch spread → zoom in") {
        let d = Driver()
        var a = SyntheticHand(); a.center = Vec2(0.4, 0.45)
        var b = SyntheticHand(); b.center = Vec2(0.6, 0.45); b.chirality = .left
        d.run([a, b], seconds: 0.3)
        b.pinchIndexGap = 0; d.run([a, b], seconds: 0.1)
        a.pinchIndexGap = 0; d.run([a, b], seconds: 0.1)
        for k in 1...20 {
            a.center = Vec2(0.4 - Double(k) * 0.006, 0.45); b.center = Vec2(0.6 + Double(k) * 0.006, 0.45)
            d.step([a, b])
        }
        let z = d.commands.filter { $0 == .zoomIn }.count
        check(z >= 2, "zoomIn ×\(z)")
        check(d.downs.isEmpty, "no click during zoom")
    }
}
