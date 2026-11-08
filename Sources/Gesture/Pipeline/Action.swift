import AppKit
import CoreGraphics

/// A bound action, parsed from the config DSL:
///   key:cmd+shift+4   media:playpause   shell:say hi   open:/Applications/Safari.app   none
enum Action {
    case key(code: CGKeyCode, flags: CGEventFlags)
    case media(Int32)
    case shell(String)
    case open(String)
    case none

    static func parse(_ s: String) -> Action? {
        let parts = s.split(separator: ":", maxSplits: 1).map(String.init)
        guard let kind = parts.first?.lowercased() else { return nil }
        let arg = parts.count > 1 ? parts[1] : ""
        switch kind {
        case "none", "": return Action.none
        case "shell": return .shell(arg)
        case "open": return .open(arg)
        case "media":
            let map: [String: Int32] = [
                "volumeup": 0, "volumedown": 1, "brightnessup": 2, "brightnessdown": 3, "mute": 7,
                "playpause": 16, "play": 16, "next": 17, "previous": 18, "prev": 18,
            ]
            return map[arg.lowercased()].map { .media($0) }
        case "key":
            var flags: CGEventFlags = []
            var code: CGKeyCode?
            // Split on "+" but allow "+" / "=" / "-" as the key itself (e.g. "cmd+=").
            var tokens = arg.lowercased().components(separatedBy: "+")
            if arg.hasSuffix("++") { tokens.removeLast(2); tokens.append("=") }
            for tok in tokens where !tok.isEmpty {
                switch tok {
                case "cmd", "command", "⌘": flags.insert(.maskCommand)
                case "ctrl", "control", "⌃": flags.insert(.maskControl)
                case "opt", "option", "alt", "⌥": flags.insert(.maskAlternate)
                case "shift", "⇧": flags.insert(.maskShift)
                case "fn": flags.insert(.maskSecondaryFn)
                default: code = keyCodes[tok]
                }
            }
            guard let c = code else { return nil }
            // Arrow / nav keys carry these flags from real keyboards; system hotkeys
            // (e.g. ⌃→ for Spaces) only match when they are present.
            if (123...126).contains(Int(c)) { flags.insert([.maskSecondaryFn, .maskNumericPad]) }
            return .key(code: c, flags: flags)
        default: return nil
        }
    }

    static let keyCodes: [String: CGKeyCode] = {
        var m: [String: CGKeyCode] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11,
            "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21,
            "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31,
            "u": 32, "[": 33, "i": 34, "p": 35, "return": 36, "enter": 36, "l": 37, "j": 38, "'": 39,
            "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48,
            "space": 49, "`": 50, "delete": 51, "backspace": 51, "escape": 53, "esc": 53,
            "left": 123, "right": 124, "down": 125, "up": 126,
            "home": 115, "end": 119, "pageup": 116, "pagedown": 121, "forwarddelete": 117,
            "plus": 24, "minus": 27,
        ]
        let fkeys: [CGKeyCode] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
        for (i, c) in fkeys.enumerated() { m["f\(i + 1)"] = c }
        return m
    }()
}
