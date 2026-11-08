import Foundation

/// Recorded sessions are JSON lines: one `HandFrame` per line, optionally with extra
/// diagnostic keys (ignored when decoding).
public enum Recording {
    public struct InvalidLine: Error, LocalizedError {
        public let line: Int
        public var errorDescription: String? { "Invalid recording at line \(line). Replay stopped instead of skipping a frame." }
    }

    public static func load(_ url: URL) throws -> [HandFrame] {
        let text = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        return try text.components(separatedBy: .newlines).enumerated().compactMap { index, line in
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            guard let frame = try? decoder.decode(HandFrame.self, from: Data(line.utf8)),
                  frame.timestamp.isFinite, frame.aspect.isFinite, frame.aspect > 0,
                  frame.hands.allSatisfy({ $0.points.count == Joint.count && $0.confidence.count == Joint.count })
            else { throw InvalidLine(line: index + 1) }
            return frame
        }
    }
}
