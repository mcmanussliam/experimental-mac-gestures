import Foundation
import GestureCore

/// Two-finger scrolling, a joystick: offset from where the pose formed sets the speed.
func scrollTests() {
    func liveScroll(_ driver: Driver) -> Vec2 {
        driver.scrolls.filter { !$0.2 }.reduce(Vec2.zero) { $0 + Vec2($1.0, $1.1) }
    }

    /// Moves the hand smoothly by `palms` (down positive), as a real hand would.
    func offset(_ hand: inout SyntheticHand, by palms: Double, sideways: Double = 0, _ driver: Driver) {
        let target = Vec2(hand.center.x + hand.scale * sideways, hand.center.y + hand.scale * palms)
        driver.move(hand, to: target, seconds: 0.2)
        hand.center = target
    }

    test("Holding two fingers offset keeps scrolling; back to neutral stops") {
        let driver = Driver()
        var hand = SyntheticHand.pose(.twoFinger)
        driver.run([hand], seconds: 0.3)
        driver.move(hand, to: Vec2(0.5, 0.45 + hand.scale), seconds: 0.2)
        hand.center = Vec2(0.5, 0.45 + hand.scale)
        let before = liveScroll(driver).y
        driver.run([hand], seconds: 0.5)
        let held = liveScroll(driver).y - before
        check(held > 600, "a held offset keeps scrolling down (\(Int(held)) pt in 0.5 s)")

        driver.move(hand, to: Vec2(0.5, 0.45), seconds: 0.2)
        hand.center = Vec2(0.5, 0.45)
        driver.run([hand], seconds: 0.3)
        let settled = liveScroll(driver).y
        driver.run([hand], seconds: 0.3)
        check(abs(liveScroll(driver).y - settled) < 1, "back at neutral it stops")
        check(driver.scrolls.allSatisfy { $0.1 >= 0 }, "returning never scrolls backwards")
        check(driver.downs.isEmpty, "no clicks while scrolling")
    }

    test("Small hand tremor at neutral doesn't scroll") {
        let driver = Driver()
        var hand = SyntheticHand.pose(.twoFinger)
        driver.run([hand], seconds: 0.3)
        for k in 0..<60 {
            hand.center = Vec2(0.5 + 0.004 * sin(Double(k)), 0.45 + 0.004 * cos(Double(k) * 1.3))
            driver.step([hand])
        }
        check(liveScroll(driver).length < 1, "dead zone absorbs tremor (\(liveScroll(driver).length) pt)")
    }

    test("Speed grows with offset") {
        func speed(offset amount: Double) -> Double {
            let driver = Driver()
            var hand = SyntheticHand.pose(.twoFinger)
            driver.run([hand], seconds: 0.3)
            offset(&hand, by: amount, driver)
            driver.run([hand], seconds: 0.1)
            let before = liveScroll(driver).y
            driver.run([hand], seconds: 0.5)
            return (liveScroll(driver).y - before) / 0.5
        }
        let small = speed(offset: 0.3), large = speed(offset: 0.9)
        check(small > 30 && large > small * 3, "\(Int(small)) pt/s at 0.3 palms, \(Int(large)) pt/s at 0.9")
    }

    test("Raising the hand scrolls the other way; sideways leaks nothing") {
        let driver = Driver()
        var hand = SyntheticHand.pose(.twoFinger)
        driver.run([hand], seconds: 0.3)
        offset(&hand, by: -0.8, sideways: 0.1, driver)
        driver.run([hand], seconds: 0.4)
        let total = liveScroll(driver)
        check(total.y < -300 && total.x == 0, "content moves up, no sideways scroll (\(total))")
    }

    test("Ending the pose eases to a stop") {
        let driver = Driver()
        var hand = SyntheticHand.pose(.twoFinger)
        driver.run([hand], seconds: 0.3)
        offset(&hand, by: 1, driver)
        driver.run([hand], seconds: 0.2)
        var open = SyntheticHand(); open.center = hand.center
        driver.run([open], seconds: 0.6)
        let tail = driver.scrolls.filter { $0.2 }
        check(!tail.isEmpty && tail.allSatisfy { $0.1 > 0 }, "a short coast in the same direction")
        check(driver.last.hud.mode != .scrolling, "scrolling ended")
    }

    test("A spread V also scrolls") {
        let driver = Driver()
        var hand = SyntheticHand.pose(.twoFinger); hand.spread = 0.45
        driver.run([hand], seconds: 0.3)
        offset(&hand, by: 1, driver)
        driver.run([hand], seconds: 0.3)
        check(liveScroll(driver).y > 300, "V scrolls")
    }

    test("Scroll rides through brief ambiguous frames") {
        let driver = Driver()
        var hand = SyntheticHand.pose(.twoFinger)
        driver.run([hand], seconds: 0.3)
        var modes: [EngineMode] = []
        for k in 1...30 {
            hand.center = Vec2(0.5, 0.45 + Double(k) * 0.004)
            var raw = hand.raw()
            // The ring finger becomes unreadable for ~200 ms, as in recorded sessions.
            if (10..<22).contains(k) { for joint in Finger.ring.joints { raw.confidence[joint.rawValue] = 0.05 } }
            modes.append(driver.stepRaw([raw]).hud.mode)
        }
        check(modes.allSatisfy { $0 == .scrolling }, "stays scrolling (\(Set(modes.map(\.rawValue))))")
    }

    test("A long ambiguous spell still ends scrolling") {
        let driver = Driver()
        let hand = SyntheticHand.pose(.twoFinger)
        driver.run([hand], seconds: 0.4)
        var raw = hand.raw()
        for joint in Finger.ring.joints { raw.confidence[joint.rawValue] = 0.05 }
        for _ in 0..<60 { driver.stepRaw([raw]) }
        check(driver.last.hud.mode != .scrolling, "exited after timeout")
    }

    test("The HUD shows the joystick's deflection") {
        let driver = Driver()
        var hand = SyntheticHand.pose(.twoFinger)
        driver.run([hand], seconds: 0.3)
        offset(&hand, by: 1, driver)
        driver.run([hand], seconds: 0.1)
        check(driver.last.hud.scrollDeflection.y > 0.9 && driver.last.hud.scrollDeflection.x == 0,
              "full downward deflection (\(driver.last.hud.scrollDeflection))")
    }
}
