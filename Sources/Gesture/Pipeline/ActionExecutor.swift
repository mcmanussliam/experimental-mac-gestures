import AppKit
import CoreGraphics
import GestureCore

/// Turns engine output into real input events. Owned by the main thread together with
/// PointerAnimator; bindings, commands and pointer events share that ordering.
final class ActionExecutor {
    private let source = CGEventSource(stateID: .hidSystemState)
    private var scrollRemainder = Vec2.zero
    private var bindings: [String: Action] = [:]
    var displayOrigin = CGPoint.zero
    var enabled = true

    func setBindings(_ raw: [String: String]) {
        var parsed: [String: Action] = [:]
        for (key, text) in raw {
            if let action = Action.parse(text) { parsed[key] = action } else { NSLog("Gesture: cannot parse action '\(text)' for \(key)") }
        }
        bindings = parsed
    }

    private func global(_ point: Vec2) -> CGPoint { CGPoint(x: displayOrigin.x + point.x, y: displayOrigin.y + point.y) }

    func apply(_ events: [PointerEvent]) {
        guard enabled else { return }
        for event in events {
            switch event {
            case .move(let position):
                postMouse(.mouseMoved, at: global(position), button: .left)
            case .drag(let button, let position):
                postMouse(button == .left ? .leftMouseDragged : .rightMouseDragged, at: global(position), button: button.cgButton)
            case .down(let button, let position, let count):
                postMouse(button == .left ? .leftMouseDown : .rightMouseDown, at: global(position), button: button.cgButton, clicks: count)
            case .up(let button, let position, let count):
                postMouse(button == .left ? .leftMouseUp : .rightMouseUp, at: global(position), button: button.cgButton, clicks: count)
            case .scroll(let dx, let dy, _):
                postScroll(Vec2(dx, dy))
            }
        }
    }

    private func postMouse(_ type: CGEventType, at point: CGPoint, button: CGMouseButton, clicks: Int = 1) {
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: button)
        else { return }
        if type != .mouseMoved { event.setIntegerValueField(.mouseEventClickState, value: Int64(clicks)) }
        event.post(tap: .cghidEventTap)
    }

    /// Scroll events carry whole pixels; fractions accumulate until they add up to one.
    private func postScroll(_ delta: Vec2) {
        scrollRemainder += delta
        let whole = Vec2(scrollRemainder.x.rounded(.towardZero), scrollRemainder.y.rounded(.towardZero))
        guard whole != .zero else { return }
        scrollRemainder -= whole
        CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                wheel1: Int32(whole.y), wheel2: Int32(whole.x), wheel3: 0)?.post(tap: .cghidEventTap)
    }

    /// Runs the action bound to a command. Returns whether an action actually ran.
    @discardableResult
    func run(_ command: GestureCommand) -> Bool {
        guard enabled, let action = bindings[command.bindingKey] else { return false }
        perform(action)
        if case .none = action { return false }
        return true
    }

    func perform(_ action: Action) {
        switch action {
        case .none: break
        case .key(let code, let flags):
            for down in [true, false] {
                let ev = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
                ev?.flags = flags
                ev?.post(tap: .cghidEventTap)
            }
        case .media(let key):
            for down in [true, false] {
                let flags = NSEvent.ModifierFlags(rawValue: down ? 0xa00 : 0xb00)
                let data1 = Int((key << 16) | ((down ? 0xa : 0xb) << 8))
                NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0,
                                   windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1)?
                    .cgEvent?.post(tap: .cghidEventTap)
            }
        case .shell(let cmd):
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = ["-lc", cmd]
            try? p.run()
        case .open(let target):
            DispatchQueue.main.async {
                if let u = URL(string: target), u.scheme != nil { NSWorkspace.shared.open(u) }
                else { NSWorkspace.shared.open(URL(fileURLWithPath: (target as NSString).expandingTildeInPath)) }
            }
        }
    }
}

private extension MouseButton {
    var cgButton: CGMouseButton { self == .left ? .left : .right }
}
