import Foundation
import GestureCore

/// Config merging.
func configTests() {
    test("Config: partial JSON merges over defaults") {
        let json = #"{"pinchEnter": 0.2, "cursorMode": "relative"}"#.data(using: .utf8)!
        let c = try JSONMerge.decode(EngineConfig.self, defaults: EngineConfig(), overlay: json)
        check(c.pinchEnter == 0.2 && c.cursorMode == .relative && c.pinchExit == EngineConfig().pinchExit, "merged")
    }

    test("Config: overrides contain only changed values and round-trip") {
        var c = EngineConfig(); c.pinchEnter = 0.21; c.cursorMode = .relative
        let o = try JSONMerge.overrides(c, defaults: EngineConfig())
        check(Set(o.keys) == ["pinchEnter", "cursorMode"], "keys \(o.keys.sorted())")
        let back = try JSONMerge.decode(EngineConfig.self, defaults: EngineConfig(), overlay: JSONSerialization.data(withJSONObject: o))
        check(back.pinchEnter == 0.21 && back.cursorMode == .relative, "round-trip")
    }
}
