import Foundation

/// The 21-joint hand topology shared by Apple Vision and MediaPipe.
public enum Joint: Int, CaseIterable, Codable, Sendable {
    case wrist = 0
    case thumbCMC, thumbMP, thumbIP, thumbTip
    case indexMCP, indexPIP, indexDIP, indexTip
    case middleMCP, middlePIP, middleDIP, middleTip
    case ringMCP, ringPIP, ringDIP, ringTip
    case littleMCP, littlePIP, littleDIP, littleTip

    public static let count = 21
}

public enum Finger: Int, CaseIterable, Codable, Sendable {
    case thumb, index, middle, ring, little

    /// Four joints from base to tip.
    public var joints: [Joint] {
        switch self {
        case .thumb: return [.thumbCMC, .thumbMP, .thumbIP, .thumbTip]
        case .index: return [.indexMCP, .indexPIP, .indexDIP, .indexTip]
        case .middle: return [.middleMCP, .middlePIP, .middleDIP, .middleTip]
        case .ring: return [.ringMCP, .ringPIP, .ringDIP, .ringTip]
        case .little: return [.littleMCP, .littlePIP, .littleDIP, .littleTip]
        }
    }
    public var tip: Joint { joints[3] }
}

/// Bone list for drawing skeletons.
public let handBones: [(Joint, Joint)] = {
    var b: [(Joint, Joint)] = []
    for f in Finger.allCases {
        let j = f.joints
        b.append((.wrist, j[0])); b.append((j[0], j[1])); b.append((j[1], j[2])); b.append((j[2], j[3]))
    }
    b.append((.indexMCP, .middleMCP)); b.append((.middleMCP, .ringMCP)); b.append((.ringMCP, .littleMCP))
    return b
}()

public enum Chirality: String, Codable, Sendable { case left, right, unknown }

/// One detected hand in **user-view coordinates**: x in [0,1] left→right as the user sees
/// themselves (mirrored camera), y in [0,1] top→bottom (like screen coordinates).
public struct RawHand: Codable, Sendable {
    /// 21 entries, indexed by Joint.rawValue.
    public var points: [Vec2]
    /// 21 entries in [0,1].
    public var confidence: [Double]
    public var chirality: Chirality
    /// Overall observation confidence.
    public var score: Double

    public init(points: [Vec2], confidence: [Double], chirality: Chirality, score: Double) {
        precondition(points.count == Joint.count && confidence.count == Joint.count)
        self.points = points; self.confidence = confidence; self.chirality = chirality; self.score = score
    }

    public subscript(_ j: Joint) -> Vec2 { points[j.rawValue] }

    /// Axis-aligned bounds of confident points.
    public var bounds: (min: Vec2, max: Vec2) {
        var lo = Vec2(1, 1), hi = Vec2(0, 0)
        for (i, p) in points.enumerated() where confidence[i] > 0.1 {
            lo = Vec2(min(lo.x, p.x), min(lo.y, p.y)); hi = Vec2(max(hi.x, p.x), max(hi.y, p.y))
        }
        return (lo, hi)
    }
}

/// One camera frame's worth of detections.
public struct HandFrame: Codable, Sendable {
    /// Seconds, monotonic.
    public var timestamp: Double
    /// Image width / height.
    public var aspect: Double
    public var hands: [RawHand]

    public init(timestamp: Double, aspect: Double, hands: [RawHand]) {
        self.timestamp = timestamp; self.aspect = aspect; self.hands = hands
    }
}
