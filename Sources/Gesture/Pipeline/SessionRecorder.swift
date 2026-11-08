import Foundation
import GestureCore

/// Writes sessions as JSON lines: `HandFrame` keys (so `gesture-lab` can replay them) plus
/// per-frame diagnostics.
final class SessionRecorder {
    let url: URL
    private let handle: FileHandle
    private let encoder = JSONEncoder()
    private let osVersion = ProcessInfo.processInfo.operatingSystemVersionString

    init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        self.url = url
        handle = try FileHandle(forWritingTo: url)
    }

    static func newSessionURL() -> URL {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd-HHmmss"
        return AppConfig.sessionsDirectory.appendingPathComponent("\(f.string(from: Date())).jsonl")
    }

    func write(_ frame: HandFrame, output out: EngineOutput, inferenceMs: Double, detectorRevision: Int) {
        let line = Line(timestamp: frame.timestamp, aspect: frame.aspect, hands: frame.hands,
                        inferMs: inferenceMs, detectorRevision: detectorRevision, osVersion: osVersion,
                        mode: out.hud.mode.rawValue, cursor: out.cursor,
                        poses: out.hands.map { "\($0.id):\($0.pose)\($0.isPointer ? "*" : "")" },
                        events: out.events.compactMap { if case .move = $0 { return nil }; return "\($0)" })
        if let d = try? encoder.encode(line) { handle.write(d); handle.write(Data([0x0A])) }
    }

    deinit { try? handle.close() }

    private struct Line: Encodable {
        var timestamp: Double
        var aspect: Double
        var hands: [RawHand]
        var inferMs: Double
        var detectorRevision: Int
        var osVersion: String
        var mode: String
        var cursor: Vec2?
        var poses: [String]
        var events: [String]
    }
}
