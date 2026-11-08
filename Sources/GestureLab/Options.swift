import Foundation
import GestureCore

/// Command-line options, and the engine configuration they select.
struct Options {
    static let usage = """
    usage: gesture-lab <command> SESSION.jsonl [options]

    commands
      replay     print clicks, drags and commands
      score      pointer-quality metrics (still-hand jitter, step sizes, spikiness, stability)
      trace      per-frame pointer CSV: t,x,y,mode
      features   per-frame pointer-hand features CSV (pinch ratios, extension scores, pose, …)
      display    what is shown at display rate: overshoot on stops (bounce), lag, still jitter

    options
      --mode absolute|relative     override the cursor mode
      --set key=value              override any engine setting (repeatable), e.g. --set pinchEnter=0.28
      --config FILE                user config to read (default: the app's config.json)
      --smoothing MS               display easing time constant (default 8 ms)
    """

    let command: String
    let session: URL
    private let arguments: [String]

    init?(_ arguments: [String]) {
        guard arguments.count >= 2 else { return nil }
        command = arguments[0]
        session = URL(fileURLWithPath: arguments[1])
        self.arguments = Array(arguments.dropFirst(2))
    }

    /// Every value given for `name`, in order.
    func values(_ name: String) -> [String] {
        zip(arguments, arguments.dropFirst()).filter { $0.0 == name }.map(\.1)
    }

    var configURL: URL {
        values("--config").first.map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Gesture/config.json")
    }

    var displaySmoothing: Double { (values("--smoothing").first.flatMap(Double.init) ?? 8) / 1000 }

    /// The user's config file, with `--mode` and `--set` applied over it.
    func engineConfig() throws -> EngineConfig {
        var overrides: [String: Any] = [:]
        if let mode = values("--mode").first { overrides["cursorMode"] = mode }
        for assignment in values("--set") {
            let parts = assignment.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            overrides[parts[0]] = Double(parts[1]) ?? Bool(parts[1]).map { $0 as Any } ?? parts[1]
        }
        let config = EngineConfig.fromUserConfig(try? Data(contentsOf: configURL))
        guard !overrides.isEmpty else { return config }
        let base = try JSONSerialization.jsonObject(with: JSONEncoder().encode(config))
        let merged = try JSONSerialization.data(withJSONObject: JSONMerge.merge(base, overrides))
        return try JSONDecoder().decode(EngineConfig.self, from: merged)
    }

    var customPoses: CustomPoseLibrary {
        let url = configURL.deletingLastPathComponent().appendingPathComponent("custom-poses.json")
        return (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(CustomPoseLibrary.self, from: $0) }
            ?? CustomPoseLibrary()
    }
}
