import Foundation

public enum Pose: String, Codable, CaseIterable, Sendable {
    case unknown
    /// Four fingers extended.
    case open
    /// Index only.
    case point
    /// Index + middle extended, ring + little bent: scroll.
    case twoFinger
    /// Four fingers curled, thumb tucked: pause / relative-mode clutch.
    case fist

    /// Poses in which the cursor keeps following the hand.
    public var movesCursor: Bool {
        switch self {
        case .unknown, .open, .point: return true
        case .twoFinger, .fist: return false
        }
    }
}

public enum FingerState: Sendable { case extended, curled, ambiguous }

/// Rule-based pose classifier. Stateful: one instance per tracked hand.
///
/// Each finger's extension score is mapped to a *three-state* reading (extended, curled, or
/// ambiguous) with hysteresis only around the decisive states. A half-bent finger is reported
/// as ambiguous rather than forced into a class, and an ambiguous finger that matters makes the
/// pose `.unknown`: the pointer keeps working, but nothing that changes mode fires.
///
/// The vocabulary is deliberately small. Recordings showed the thumb's reading is ambiguous in
/// ~30% of frames, so it is only consulted to tell a fist from a pinch made with curled fingers.
public struct PoseClassifier: Sendable {
    public private(set) var fingers = [FingerState](repeating: .ambiguous, count: 5)

    public init() {}

    public var extendedCount: Int { fingers[1...4].filter { $0 == .extended }.count }

    public mutating func classify(_ f: HandFeatures, config: EngineConfig) -> Pose {
        for i in 0..<5 {
            fingers[i] = f.fingerConfidence[i] >= HandRepair.reliable
                ? Self.next(fingers[i], score: f.extensionScore[i], config: config) : .ambiguous
        }
        // Scrolling should not require squeezing the other fingers into a tight fist, so ring and
        // little only need to be visibly bent, not decisively curled.
        if fingers[1] == .extended && fingers[2] == .extended,
           f.fingerConfidence[3] >= HandRepair.reliable, f.fingerConfidence[4] >= HandRepair.reliable,
           f.extensionScore[3] <= config.scrollFingerCurledBelow,
           f.extensionScore[4] <= config.scrollFingerCurledBelow {
            return .twoFinger
        }
        let four = fingers[1...4]
        if four.contains(.ambiguous) { return .unknown }
        let extended = four.map { $0 == .extended }
        switch (extended[0], extended[1], extended[2], extended[3]) {
        case (true, true, true, true): return .open
        case (true, false, false, false): return .point
        // A decisively tucked thumb: with an uncertain thumb this may be a pinch made with the
        // other fingers curled, and a fist blocks clicking.
        case (false, false, false, false): return fingers[0] == .curled ? .fist : .unknown
        default: return .unknown
        }
    }

    static func next(_ state: FingerState, score s: Double, config: EngineConfig) -> FingerState {
        let on = config.fingerExtendedAbove, off = config.fingerCurledBelow, h = config.fingerHysteresis
        switch state {
        case .extended where s >= on - h: return .extended
        case .curled where s <= off + h: return .curled
        default: return s >= on ? .extended : s <= off ? .curled : .ambiguous
        }
    }

    public mutating func reset() {
        fingers = [FingerState](repeating: .ambiguous, count: 5)
    }
}
