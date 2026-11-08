import Foundation
import GestureCore

/// User configuration: engine tunables + gesture → action bindings + app preferences.
///
/// `config.json` stores only what differs from the built-in defaults (it is deep-merged over
/// them on load), so improved defaults reach existing users. `config.defaults.json` is a
/// regenerated reference copy of every setting. The file is watched and reloads live.
struct AppConfig: Codable, Equatable {
    var engine = EngineConfig()

    /// Binding keys: `swipe.left|right|up|down`, `pose.custom.<name>`, `zoom.in|out`.
    /// Actions: see `Action.parse` (key:, media:, shell:, open:, none).
    var bindings: [String: String] = [
        "swipe.left": "key:ctrl+right",      // hand moves left → next Space (like a trackpad)
        "swipe.right": "key:ctrl+left",
        "swipe.up": "key:ctrl+up",           // Mission Control
        "swipe.down": "key:ctrl+down",       // App Exposé
        "zoom.in": "key:cmd+=",
        "zoom.out": "key:cmd+-",
    ]

    var showPointerRing = true
    var showNotifications = true
    /// AVCaptureDevice.uniqueID; nil = system default camera.
    var cameraID: String? = nil
    var preferredFPS = 60
    /// After this many seconds without a hand, only every `idleFrameStride`-th frame is analysed.
    var idleAfter = 3.0
    var idleFrameStride = 3
    var maxHands = 2
    /// Display-rate pointer rendering between camera frames: easing time constant (ms).
    var pointerSmoothingMs = 8.0
    var scrollSmoothingMs = 30.0

    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Gesture", isDirectory: true)
    }
    static var fileURL: URL { directory.appendingPathComponent("config.json") }
    static var defaultsURL: URL { directory.appendingPathComponent("config.defaults.json") }
    static var customPosesURL: URL { directory.appendingPathComponent("custom-poses.json") }
    static var sessionsDirectory: URL { directory.appendingPathComponent("Sessions", isDirectory: true) }

    static func load() -> AppConfig {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        writeJSON(AppConfig(), to: defaultsURL)
        let data = try? Data(contentsOf: fileURL)
        if data == nil { try? Data("{\n}\n".utf8).write(to: fileURL) }
        do {
            return try JSONMerge.decode(AppConfig.self, defaults: AppConfig(), overlay: data)
        } catch {
            Log.app.error("Config file is invalid, using defaults: \(error.localizedDescription, privacy: .public)")
            return AppConfig()
        }
    }

    /// Writes only the settings that differ from the defaults.
    func save() {
        guard let overrides = try? JSONMerge.overrides(self, defaults: AppConfig()),
              let data = try? JSONSerialization.data(withJSONObject: overrides, options: [.prettyPrinted, .sortedKeys])
        else { return }
        if (try? Data(contentsOf: Self.fileURL)) != data { try? data.write(to: Self.fileURL, options: .atomic) }
    }

    private static func writeJSON<T: Encodable>(_ value: T, to url: URL) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        // Only touch the file when it changes: the config directory is watched for edits.
        if let d = try? enc.encode(value), (try? Data(contentsOf: url)) != d { try? d.write(to: url, options: .atomic) }
    }

    static func loadCustomPoses() -> CustomPoseLibrary {
        guard let d = try? Data(contentsOf: customPosesURL),
              let lib = try? JSONDecoder().decode(CustomPoseLibrary.self, from: d) else { return CustomPoseLibrary() }
        return lib
    }

    static func saveCustomPoses(_ lib: CustomPoseLibrary) {
        if let d = try? JSONEncoder().encode(lib) { try? d.write(to: customPosesURL, options: .atomic) }
    }
}
