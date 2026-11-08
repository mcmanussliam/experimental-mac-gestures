import Foundation

/// Human-facing descriptions of gestures and the actions they can be bound to.
enum GestureCatalog {
    struct Gesture: Identifiable {
        /// Binding key.
        let id: String
        let title: String
        /// SF Symbol name.
        let symbol: String
        let detail: String
    }

    struct Preset: Identifiable, Hashable {
        var id: String { action }
        let title: String
        let action: String
    }

    /// Gestures with a fixed meaning (not bindable).
    static let pointer: [Gesture] = [
        Gesture(id: "move", title: "Move pointer", symbol: "hand.raised", detail: "Move an open or pointing hand"),
        Gesture(id: "click", title: "Click", symbol: "hand.pinch", detail: "Tap thumb and index finger together; twice to double-click"),
        Gesture(id: "drag", title: "Drag", symbol: "hand.draw", detail: "Pinch, then move while holding"),
        Gesture(id: "right", title: "Right click", symbol: "hand.pinch.fill", detail: "Tap thumb and middle finger together"),
        Gesture(id: "scroll", title: "Scroll", symbol: "hand.point.up.braille", detail: "Raise index and middle fingers, then move off-centre like a joystick: further is faster, back to centre stops"),
        Gesture(id: "pause", title: "Pause / resume", symbol: "hand.raised.slash", detail: "Hold a fist for a second, or press ⌃⌥⌘G"),
    ]

    static let bindable: [Gesture] = [
        Gesture(id: "swipe.left", title: "Swipe left", symbol: "arrow.left", detail: "Open palm, quick stroke"),
        Gesture(id: "swipe.right", title: "Swipe right", symbol: "arrow.right", detail: "Open palm, quick stroke"),
        Gesture(id: "swipe.up", title: "Swipe up", symbol: "arrow.up", detail: "Open palm, quick stroke"),
        Gesture(id: "swipe.down", title: "Swipe down", symbol: "arrow.down", detail: "Open palm, quick stroke"),
        Gesture(id: "zoom.in", title: "Spread both hands", symbol: "plus.magnifyingglass", detail: "Pinch with both hands, pull apart"),
        Gesture(id: "zoom.out", title: "Squeeze both hands", symbol: "minus.magnifyingglass", detail: "Pinch with both hands, push together"),
    ]

    static let presets: [Preset] = [
        Preset(title: "Nothing", action: "none"),
        Preset(title: "Mission Control", action: "key:ctrl+up"),
        Preset(title: "App Exposé", action: "key:ctrl+down"),
        Preset(title: "Next Space", action: "key:ctrl+right"),
        Preset(title: "Previous Space", action: "key:ctrl+left"),
        Preset(title: "Spotlight", action: "key:cmd+space"),
        Preset(title: "Switch to Last App", action: "key:cmd+tab"),
        Preset(title: "Play / Pause", action: "media:playpause"),
        Preset(title: "Next Track", action: "media:next"),
        Preset(title: "Previous Track", action: "media:previous"),
        Preset(title: "Volume Up", action: "media:volumeup"),
        Preset(title: "Volume Down", action: "media:volumedown"),
        Preset(title: "Mute", action: "media:mute"),
        Preset(title: "Zoom In", action: "key:cmd+="),
        Preset(title: "Zoom Out", action: "key:cmd+-"),
        Preset(title: "Back", action: "key:cmd+["),
        Preset(title: "Forward", action: "key:cmd+]"),
        Preset(title: "Close Window", action: "key:cmd+w"),
        Preset(title: "Screenshot", action: "key:cmd+shift+4"),
    ]

    static func title(forAction action: String) -> String {
        presets.first { $0.action == action }?.title ?? action
    }

    static func title(forBinding key: String) -> String {
        if key.hasPrefix("pose.custom.") { return String(key.dropFirst("pose.custom.".count)) }
        return bindable.first { $0.id == key }?.title ?? key
    }
}
